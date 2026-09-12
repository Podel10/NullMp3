import 'package:flutter/material.dart';

import '../data/lyrics.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'widgets.dart';

class LyricsScreen extends StatelessWidget {
  const LyricsScreen({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.s.lyrics)),
      body: LyricsView(path: track.path),
    );
  }
}

class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.path});

  final String path;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  LyricsResult? _lyrics;

  @override
  void initState() {
    super.initState();
    _lyrics = loadLyrics(widget.path);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _lyrics = loadLyrics(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return Center(child: Text(context.s.lyricsNotFound));
    }
    if (lyrics.lines.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          lyrics.plain ?? '',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    final player = contextPlayer(context);
    return StreamBuilder<Duration>(
      stream: player.player.positionStream,
      builder: (context, snapshot) {
        final pos = snapshot.data ?? Duration.zero;
        var active = 0;
        for (var i = 0; i < lyrics.lines.length; i++) {
          if (lyrics.lines[i].time <= pos) active = i;
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          itemCount: lyrics.lines.length,
          itemBuilder: (context, i) {
            final selected = i == active;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                lyrics.lines[i].text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: selected ? 1 : 0.4),
                    ),
              ),
            );
          },
        );
      },
    );
  }
}
