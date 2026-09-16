import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/artwork.dart';
import '../data/cover_image.dart';
import '../data/cover_search.dart';
import '../data/network.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'cover_crop.dart';
import 'cover_media.dart';
import 'widgets.dart';

Future<Uint8List?> showCoverSearch(
  BuildContext context,
  Track track, {
  CoverSearchKind kind = CoverSearchKind.art,
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => CoverSearchScreen(track: track, kind: kind)),
  );
}

class CoverSearchScreen extends StatefulWidget {
  const CoverSearchScreen({
    super.key,
    required this.track,
    this.kind = CoverSearchKind.art,
  });

  final Track track;
  final CoverSearchKind kind;

  @override
  State<CoverSearchScreen> createState() => _CoverSearchScreenState();
}

class _CoverSearchScreenState extends State<CoverSearchScreen> {
  late final TextEditingController _query;
  List<CoverCandidate> _hits = [];
  late bool _busy;
  bool _applying = false;
  String? _error;

  bool get _tiedToTrack => widget.kind == CoverSearchKind.art;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: _tiedToTrack ? coverSearchQuery(widget.track) : '');
    _busy = _tiedToTrack;
    if (_tiedToTrack) unawaited(_search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final failed = context.s.coverSearchFailed;
    if (NetworkGate.offline) {
      setState(() {
        _busy = false;
        _error = context.s.lyricsOffline;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final hits = await searchCoverCandidates(
        widget.track,
        query: _query.text,
        kind: widget.kind,
      );
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _busy = false;
        if (hits.isEmpty && _query.text.trim().length >= 2) _error = failed;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is SocketException || NetworkGate.offline ? context.s.lyricsOffline : failed;
      });
    }
  }

  Future<void> _apply(CoverCandidate hit) async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      var bytes = await downloadCoverBytes(hit.fullUrl);
      bytes ??= await downloadCoverBytes(hit.previewUrl);
      if (bytes == null || bytes.isEmpty) throw Exception('empty');
      if (!mounted) return;
      setState(() => _applying = false);
      final cropped = await showCoverCrop(context, bytes);
      if (!mounted) return;
      if (cropped == null || cropped.isEmpty) return;
      setState(() => _applying = true);
      final cover = await downscaleCover(cropped, maxSide: 900);
      await ArtworkStore.instance.put(widget.track.path, cover);
      if (!mounted) return;
      final player = contextPlayer(context, listen: false);
      if (player.current?.path == widget.track.path) {
        unawaited(player.refreshArtwork());
      }
      Navigator.pop(context, cover);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = context.s.coverSearchApplyFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final title = switch (widget.kind) {
      CoverSearchKind.art => s.autoStyle,
      CoverSearchKind.image => s.searchImage,
      CoverSearchKind.gif => s.searchGif,
    };
    final hint = switch (widget.kind) {
      CoverSearchKind.art => s.coverSearchHint,
      CoverSearchKind.image => s.imageSearchHint,
      CoverSearchKind.gif => s.gifSearchHint,
    };
    final sources = switch (widget.kind) {
      CoverSearchKind.art => s.coverSearchSources,
      CoverSearchKind.image => s.imageSearchSources,
      CoverSearchKind.gif => s.gifSearchSources,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_search()),
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: _busy ? null : () => unawaited(_search()),
                  icon: const Icon(Icons.auto_awesome_rounded),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              sources,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
            ),
          ),
          if (_busy || _applying)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_hits.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _error ?? (_tiedToTrack ? s.coverSearchFailed : hint),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemCount: _hits.length,
                itemBuilder: (context, index) {
                  final hit = _hits[index];
                  return InkWell(
                    onTap: () => unawaited(_apply(hit)),
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _CoverThumb(
                              url: hit.previewUrl,
                              animate: widget.kind == CoverSearchKind.gif,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          hit.source,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        Text(
                          hit.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverThumb extends StatefulWidget {
  const _CoverThumb({required this.url, this.animate = false});

  final String url;
  final bool animate;

  @override
  State<_CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends State<_CoverThumb> {
  late final Future<Uint8List?> _bytes = downloadCoverBytes(widget.url);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return CoverBytesView(
            bytes: bytes,
            fit: BoxFit.cover,
            animate: widget.animate,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFF1C3A48),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return const ColoredBox(
          color: Color(0xFF1C3A48),
          child: Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}
