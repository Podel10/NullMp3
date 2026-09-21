import 'dart:async';

import 'package:flutter/material.dart';

import '../data/lyrics.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'widgets.dart';

/// Karaoke / plain lyrics painted over the now-playing cover.
class CoverLyricsOverlay extends StatefulWidget {
  const CoverLyricsOverlay({super.key, required this.track});

  final Track track;

  @override
  State<CoverLyricsOverlay> createState() => _CoverLyricsOverlayState();
}

class _CoverLyricsOverlayState extends State<CoverLyricsOverlay> {
  LyricsResult? _lyrics;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CoverLyricsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.path != widget.track.path) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final lyrics = await loadLyricsFor(widget.track);
    if (!mounted) return;
    setState(() {
      _lyrics = lyrics;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: _busy
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                ),
              )
            : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty || lyrics.instrumental) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = _coverLyricSize(constraints.maxWidth, base: 0.042, min: 15, max: 22);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.s.noLyricsOnCover,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: size, height: 1.35),
              ),
            ),
          );
        },
      );
    }
    if (lyrics.synced) {
      return _CoverSyncedLyrics(lyrics: lyrics);
    }
    return _CoverPlainLyrics(text: lyrics.plain ?? '');
  }
}

double _coverLyricSize(double width, {required double base, required double min, required double max}) {
  if (width <= 0) return min;
  return (width * base).clamp(min, max);
}

class _CoverSyncedLyrics extends StatelessWidget {
  const _CoverSyncedLyrics({required this.lyrics});

  final LyricsResult lyrics;

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context, listen: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        // One size for all rows so the active line never jumps when focus moves.
        final size = _coverLyricSize(constraints.maxWidth, base: 0.058, min: 17, max: 30);
        final slotH = size * 1.3 * 2 + 6;
        return StreamBuilder<Duration>(
          stream: player.positionClock,
          builder: (context, snapshot) {
            final pos = snapshot.data ?? Duration.zero;
            var active = 0;
            for (var i = 0; i < lyrics.lines.length; i++) {
              if (lyrics.lines[i].time <= pos) active = i;
            }
            final prev = active > 0 ? lyrics.lines[active - 1].text : '';
            final current = lyrics.lines[active].text;
            final next =
                active + 1 < lyrics.lines.length ? lyrics.lines[active + 1].text : '';
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: const Alignment(0, -0.52),
                    child: _CoverLyricSlot(
                      lineKey: active - 1,
                      text: prev,
                      fontSize: size,
                      slotHeight: slotH,
                      active: false,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: _CoverLyricSlot(
                      lineKey: active,
                      text: current,
                      fontSize: size,
                      slotHeight: slotH,
                      active: true,
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.52),
                    child: _CoverLyricSlot(
                      lineKey: active + 1,
                      text: next,
                      fontSize: size,
                      slotHeight: slotH,
                      active: false,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Fixed-height row pinned in the stack — fade only, no size/layout shift.
class _CoverLyricSlot extends StatelessWidget {
  const _CoverLyricSlot({
    required this.lineKey,
    required this.text,
    required this.fontSize,
    required this.slotHeight,
    required this.active,
  });

  final int lineKey;
  final String text;
  final double fontSize;
  final double slotHeight;
  final bool active;

  static const _duration = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: slotHeight,
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: _duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) {
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ...previous,
              if (current != null) current,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: Text(
          text.isEmpty ? ' ' : text,
          key: ValueKey<int>(lineKey),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          strutStyle: StrutStyle(
            fontSize: fontSize,
            height: 1.3,
            forceStrutHeight: true,
          ),
          style: TextStyle(
            color: Colors.white.withValues(alpha: active ? 1 : 0.34),
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            fontSize: fontSize,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _CoverPlainLyrics extends StatelessWidget {
  const _CoverPlainLyrics({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _coverLyricSize(constraints.maxWidth, base: 0.055, min: 16, max: 30);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }
}
