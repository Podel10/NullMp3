import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/artwork.dart';
import '../data/network.dart';
import '../data/web_audio.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/settings.dart';
import 'widgets.dart';

class WebAudioScreen extends StatefulWidget {
  const WebAudioScreen({super.key});

  @override
  State<WebAudioScreen> createState() => _WebAudioScreenState();
}

class _WebAudioScreenState extends State<WebAudioScreen> {
  final _link = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _searching = false;
  bool _cancel = false;
  String? _error;
  WebAudioProgress? _progress;
  final List<WebAudioFile> _done = [];
  final List<WebAudioSearchHit> _hits = [];

  @override
  void initState() {
    super.initState();
    _link.addListener(_onLinkChanged);
    unawaited(_pasteClipboard(onlyIfEmpty: true));
  }

  void _onLinkChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancel = true;
    _link.removeListener(_onLinkChanged);
    _link.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _pasteClipboard({bool onlyIfEmpty = false}) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;
      if (onlyIfEmpty && _link.text.trim().isNotEmpty) return;
      if (onlyIfEmpty && parseWebAudioUrl(text) == null) return;
      if (!mounted) return;
      setState(() {
        _link.text = text;
        _link.selection = TextSelection.collapsed(offset: text.length);
        _error = null;
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    final raw = _link.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = context.s.downloadAudioBadLink);
      return;
    }
    if (parseWebAudioUrl(raw) != null) {
      await _download(raw);
      return;
    }
    await _search(raw);
  }

  Future<void> _search(String query) async {
    final s = context.s;
    if (NetworkGate.offline) {
      setState(() => _error = s.downloadAudioOffline);
      return;
    }

    setState(() {
      _searching = true;
      _busy = false;
      _cancel = false;
      _error = null;
      _progress = null;
      _hits.clear();
      _done.clear();
    });

    try {
      final hits = await searchWebAudio(
        query,
        isCancelled: () => _cancel || !mounted,
      );
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hits
          ..clear()
          ..addAll(hits);
        if (hits.isEmpty) _error = s.downloadAudioNoResults;
      });
    } on WebAudioException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = switch (error.code) {
          'offline' => s.downloadAudioOffline,
          'cancelled' => s.downloadAudioCancelled,
          'badUrl' => s.downloadAudioBadLink,
          _ => s.downloadAudioFailed,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = s.downloadAudioFailed;
      });
    }
  }

  Future<void> _download(String raw) async {
    final s = context.s;
    if (raw.trim().isEmpty || parseWebAudioUrl(raw) == null) {
      setState(() => _error = s.downloadAudioBadLink);
      return;
    }
    if (NetworkGate.offline) {
      setState(() => _error = s.downloadAudioOffline);
      return;
    }

    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    await settings.requestMediaPermission();

    setState(() {
      _busy = true;
      _searching = false;
      _cancel = false;
      _error = null;
      _progress = null;
      _done.clear();
    });

    try {
      final files = await downloadWebAudio(
        raw,
        isCancelled: () => _cancel || !mounted,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      final dir = files.isEmpty ? null : p.dirname(files.first.path);
      if (dir != null) await settings.addFolderPath(dir);
      await settings.rememberFiles([for (final file in files) file.path]);
      await library.addFiles([for (final file in files) file.path]);
      for (final file in files) {
        if (file.cover != null) {
          await ArtworkStore.instance.put(file.path, file.cover!);
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done
          ..clear()
          ..addAll(files);
        _progress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.downloadAudioSaved(files.length))),
      );
    } on WebAudioException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = switch (error.code) {
          'offline' => s.downloadAudioOffline,
          'badUrl' => s.downloadAudioBadLink,
          'cancelled' => s.downloadAudioCancelled,
          _ => s.downloadAudioFailed,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _error = s.downloadAudioFailed;
      });
    }
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '';
    final total = (ms / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final progress = _progress;
    final locked = _busy || _searching;
    return Scaffold(
      appBar: AppBar(title: Text(s.downloadAudio)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(s.downloadAudioHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _link,
            focusNode: _focus,
            enabled: !locked,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onSubmitted: locked ? null : (_) => unawaited(_submit()),
            decoration: InputDecoration(
              labelText: s.downloadAudioLink,
              hintText: 'Song name or https://soundcloud.com/…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: s.downloadAudioPaste,
                onPressed: locked ? null : () => _pasteClipboard(),
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: locked ? null : () => unawaited(_submit()),
            icon: Icon(
              parseWebAudioUrl(_link.text.trim()) != null
                  ? Icons.download_rounded
                  : Icons.search_rounded,
            ),
            label: Text(
              _busy
                  ? s.downloadAudioBusy
                  : _searching
                      ? s.downloadAudioSearching
                      : parseWebAudioUrl(_link.text.trim()) != null
                          ? s.downloadAudioGo
                          : s.downloadAudioSearch,
            ),
          ),
          if (locked) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() => _cancel = true),
              child: Text(s.cancel),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress?.fraction),
              if (progress != null) ...[
                const SizedBox(height: 8),
                Text(
                  progress.stage == 'tag'
                      ? s.downloadAudioTagging
                      : s.downloadAudioItem(progress.index, progress.total, progress.title),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
            if (_searching) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          if (_hits.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(s.downloadAudioPick, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final hit in _hits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !locked,
                leading: hit.artworkUrl == null
                    ? CircleAvatar(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.music_note_rounded, size: 20),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          hit.artworkUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(Icons.music_note_rounded),
                          ),
                        ),
                      ),
                title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    hit.artist,
                    if (_formatDuration(hit.durationMs).isNotEmpty) _formatDuration(hit.durationMs),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.download_rounded),
                onTap: locked ? null : () => unawaited(_download(hit.url)),
              ),
          ],
          if (_done.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              p.dirname(_done.first.path),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 8),
            for (final file in _done)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CoverArt(
                  track: Track(
                    path: file.path,
                    title: file.title,
                    artist: file.artist,
                    album: '',
                    genre: '',
                    durationMs: 0,
                    modifiedMs: 0,
                  ),
                  size: 48,
                ),
                title: Text(file.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(file.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        ],
      ),
    );
  }
}
