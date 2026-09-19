import 'dart:async';

import 'package:flutter/material.dart';

import '../data/lyrics.dart';
import '../data/network.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'widgets.dart';

class LyricsScreen extends StatelessWidget {
  const LyricsScreen({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return LyricsView(track: track);
  }
}

class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.track});

  final Track track;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  late final TextEditingController _query;
  LyricsResult? _lyrics;
  List<LyricHit> _hits = [];
  LyricSearchFilters _filters = const LyricSearchFilters();
  bool _busy = true;
  bool _searchOpen = false;
  String? _error;
  int _active = 0;

  Track get _track => widget.track;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: defaultLyricsQuery(_track));
    unawaited(_load(onlineIfEmpty: true));
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.path != widget.track.path) {
      _query.text = defaultLyricsQuery(_track);
      unawaited(_load(onlineIfEmpty: true));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load({bool onlineIfEmpty = false}) async {
    final s = context.s;
    setState(() {
      _busy = true;
      _error = null;
      _searchOpen = false;
    });
    try {
      var lyrics = await loadLyricsFor(_track);
      if (onlineIfEmpty &&
          lyrics.isEmpty &&
          !NetworkGate.offline &&
          !await lyricsSearchSuppressed(_track.path)) {
        final exact = await fetchLyricsOnline(_track);
        if (!exact.isEmpty) {
          await saveLyrics(_track.path, exact.raw);
          lyrics = exact;
        } else {
          await _runSearch();
          if (!mounted) return;
          setState(() => _busy = false);
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _lyrics = lyrics;
        _busy = false;
      });
    } on LyricsOfflineException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lyrics ??= const LyricsResult();
        _error = s.lyricsOffline;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lyrics ??= const LyricsResult();
        _error = s.lyricsSearchFailed;
      });
    }
  }

  Future<void> _runSearch() async {
    final s = context.s;
    setState(() {
      _busy = true;
      _error = null;
      _searchOpen = true;
    });
    try {
      final hits = await searchLyricHits(_track, query: _query.text, filters: _filters);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _busy = false;
        if (hits.isEmpty) _error = s.lyricsSearchFailed;
      });
    } on LyricsOfflineException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = s.lyricsOffline;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = s.lyricsSearchFailed;
      });
    }
  }

  Future<void> _pick(LyricHit hit) async {
    await saveLyrics(_track.path, hit.lyrics.raw);
    if (!mounted) return;
    setState(() {
      _lyrics = hit.lyrics;
      _searchOpen = false;
    });
  }

  Future<void> _edit() async {
    final s = context.s;
    final edited = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _LyricsEditorSheet(
          title: s.editLyrics,
          hint: s.lyricsHint,
          initial: _lyrics?.raw ?? '',
          cancelLabel: s.cancel,
          saveLabel: s.save,
          clearLabel: s.clearLyrics,
        );
      },
    );
    if (!mounted || edited == null) return;
    if (edited.trim().isEmpty) {
      await clearSavedLyrics(_track.path);
      setState(() => _lyrics = const LyricsResult());
      return;
    }
    await saveLyrics(_track.path, edited);
    if (!mounted) return;
    setState(() => _lyrics = parseLyrics(edited));
  }

  void _followActive(int active) {
    if (!_scroll.hasClients || active == _active) return;
    _active = active;
    final offset = (active * 48.0) - 160;
    _scroll.animateTo(
      offset.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final lyrics = _lyrics;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.lyrics),
        actions: [
          if (_searchOpen && _lyrics != null && !_lyrics!.isEmpty)
            IconButton(
              tooltip: s.close,
              onPressed: () => setState(() => _searchOpen = false),
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: s.lyricsSearchOnline,
            onPressed: _busy ? null : () => unawaited(_runSearch()),
            icon: const Icon(Icons.travel_explore_rounded),
          ),
          IconButton(
            tooltip: s.editLyrics,
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: _searchOpen
          ? _LyricsSearchPanel(
              query: _query,
              filters: _filters,
              hits: _hits,
              busy: _busy,
              error: _error,
              onFilters: (filters) {
                setState(() => _filters = filters);
                unawaited(_runSearch());
              },
              onSearch: () => unawaited(_runSearch()),
              onPick: _pick,
              onWrite: _edit,
            )
          : _busy && lyrics == null
          ? const Center(child: CircularProgressIndicator())
          : lyrics == null || lyrics.isEmpty
              ? _EmptyLyrics(
                  searching: _busy,
                  error: _error,
                  offline: _error == s.lyricsOffline,
                  onSearch: () => unawaited(_runSearch()),
                  onWrite: _edit,
                )
              : lyrics.instrumental
                  ? Center(
                      child: Text(
                        s.instrumental,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    )
                  : lyrics.lines.isEmpty
                      ? _PlainLyrics(text: lyrics.plain ?? '')
                      : _SyncedLyrics(
                          lyrics: lyrics,
                          controller: _scroll,
                          onActive: _followActive,
                        ),
    );
  }
}

class _LyricsSearchPanel extends StatelessWidget {
  const _LyricsSearchPanel({
    required this.query,
    required this.filters,
    required this.hits,
    required this.busy,
    required this.onFilters,
    required this.onSearch,
    required this.onPick,
    required this.onWrite,
    this.error,
  });

  final TextEditingController query;
  final LyricSearchFilters filters;
  final List<LyricHit> hits;
  final bool busy;
  final String? error;
  final ValueChanged<LyricSearchFilters> onFilters;
  final VoidCallback onSearch;
  final ValueChanged<LyricHit> onPick;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: s.lyricsSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                onPressed: busy ? null : onSearch,
                icon: const Icon(Icons.travel_explore_rounded),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: Text(s.lyricsFilterDuration),
                selected: filters.similarDuration,
                onSelected: (value) => onFilters(filters.copyWith(similarDuration: value)),
              ),
              FilterChip(
                label: Text(s.lyricsFilterArtist),
                selected: filters.matchArtist,
                onSelected: (value) => onFilters(filters.copyWith(matchArtist: value)),
              ),
              FilterChip(
                label: Text(s.lyricsFilterSynced),
                selected: filters.syncedOnly,
                onSelected: (value) => onFilters(filters.copyWith(syncedOnly: value)),
              ),
            ],
          ),
        ),
        if (busy)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (hits.isEmpty)
          Expanded(
            child: _EmptyLyrics(
              searching: false,
              error: error,
              offline: error == s.lyricsOffline,
              onSearch: onSearch,
              onWrite: onWrite,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: hits.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(s.lyricsPickResult, style: theme.textTheme.titleSmall),
                  );
                }
                final hit = hits[index - 1];
                final duration = hit.durationSec > 0
                    ? formatDuration(Duration(seconds: hit.durationSec))
                    : '—';
                return ListTile(
                  title: Text(hit.title),
                  subtitle: Text(s.lyricsHitMeta(hit.artist, duration, hit.source)),
                  trailing: hit.lyrics.synced ? const Icon(Icons.closed_caption_rounded) : null,
                  onTap: () => onPick(hit),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({
    required this.searching,
    required this.onSearch,
    required this.onWrite,
    this.error,
    this.offline = false,
  });

  final bool searching;
  final String? error;
  final bool offline;
  final VoidCallback onSearch;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              offline ? Icons.wifi_off_rounded : Icons.lyrics_outlined,
              size: 56,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              searching ? s.lyricsSearching : (error ?? s.lyricsNotFound),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              offline ? s.lyricsOfflineHint : s.lyricsNotFoundHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 24),
            if (searching)
              const CircularProgressIndicator()
            else ...[
              FilledButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.travel_explore_rounded),
                label: Text(s.lyricsSearchOnline),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onWrite,
                icon: const Icon(Icons.edit_outlined),
                label: Text(s.lyricsWrite),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 40),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.55),
      ),
    );
  }
}

class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({
    required this.lyrics,
    required this.controller,
    required this.onActive,
  });

  final LyricsResult lyrics;
  final ScrollController controller;
  final ValueChanged<int> onActive;

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  int _lastActive = -1;

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    return StreamBuilder<Duration>(
      stream: player.positionClock,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        var active = 0;
        for (var i = 0; i < widget.lyrics.lines.length; i++) {
          if (widget.lyrics.lines[i].time <= pos) active = i;
        }
        if (active != _lastActive) {
          _lastActive = active;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onActive(active);
          });
        }
        return ListView.builder(
          controller: widget.controller,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          itemCount: widget.lyrics.lines.length,
          itemBuilder: (context, i) {
            final selected = i == active;
            return InkWell(
              onTap: () => player.seek(widget.lyrics.lines[i].time),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  widget.lyrics.lines[i].text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        height: 1.35,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: selected ? 1 : 0.38),
                      ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _LyricsEditorSheet extends StatefulWidget {
  const _LyricsEditorSheet({
    required this.title,
    required this.hint,
    required this.initial,
    required this.cancelLabel,
    required this.saveLabel,
    required this.clearLabel,
  });

  final String title;
  final String hint;
  final String initial;
  final String cancelLabel;
  final String saveLabel;
  final String clearLabel;

  @override
  State<_LyricsEditorSheet> createState() => _LyricsEditorSheetState();
}

class _LyricsEditorSheetState extends State<_LyricsEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 12,
            minLines: 8,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: Text(widget.clearLabel),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(widget.cancelLabel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _controller.text),
                child: Text(widget.saveLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
