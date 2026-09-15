import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/strings.dart';
import 'widgets.dart';

/// Time without input before the controls lock themselves again.
const _relockAfter = Duration(seconds: 10);
const _hintVisible = Duration(seconds: 2);

class LockPlayerScreen extends StatefulWidget {
  const LockPlayerScreen({super.key});

  @override
  State<LockPlayerScreen> createState() => _LockPlayerScreenState();
}

class _LockPlayerScreenState extends State<LockPlayerScreen> {
  bool _locked = true;
  bool _hint = false;
  Timer? _relock;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _relock?.cancel();
    _hintTimer?.cancel();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _unlock() {
    _hintTimer?.cancel();
    setState(() {
      _locked = false;
      _hint = false;
    });
    _delayRelock();
  }

  void _lock() {
    _relock?.cancel();
    _hintTimer?.cancel();
    setState(() {
      _locked = true;
      _hint = false;
    });
  }

  /// Every touch on the unlocked controls pushes the auto-lock further away.
  void _delayRelock() {
    if (_locked) return;
    _relock?.cancel();
    _relock = Timer(_relockAfter, () {
      if (mounted) _lock();
    });
  }

  void _flashHint() {
    _hintTimer?.cancel();
    setState(() => _hint = true);
    _hintTimer = Timer(_hintVisible, () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final player = contextPlayer(context);
    final track = player.current;
    final accent = Theme.of(context).colorScheme.primary;

    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _flashHint();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerDown: (_) => _delayRelock(),
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  if (_locked) return;
                  if ((details.primaryVelocity ?? 0) > 400) Navigator.pop(context);
                },
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 36),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: _lock,
                              tooltip: s.lockNow,
                              icon: const Icon(Icons.lock_outline_rounded, size: 28),
                            ),
                          ],
                        ),
                        const Spacer(),
                        AspectRatio(
                          aspectRatio: 1,
                          child: CoverArt(
                            track: track,
                            expand: true,
                            radius: 8,
                            muted: true,
                            loadArtwork: true,
                            animate: true,
                          ),
                        ),
                        const SizedBox(height: 28),
                        MarqueeText(
                          track?.title ?? s.nothingPlaying,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        MarqueeText(
                          track == null ? '' : s.displayArtist(track.artist),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SeekBar(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              onPressed: player.previous,
                              icon: const Icon(Icons.skip_previous_rounded, size: 44),
                            ),
                            IconButton(
                              onPressed: player.playPause,
                              iconSize: 64,
                              color: accent,
                              icon: Icon(
                                player.playing
                                    ? Icons.pause_circle_filled_rounded
                                    : Icons.play_circle_filled_rounded,
                              ),
                            ),
                            IconButton(
                              onPressed: player.next,
                              icon: const Icon(Icons.skip_next_rounded, size: 44),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_locked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _flashHint,
                  onLongPress: _unlock,
                  child: _LockedVeil(hint: _hint, label: s.lockedHint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LockedVeil extends StatelessWidget {
  const _LockedVeil({required this.hint, required this.label});

  final bool hint;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: AnimatedOpacity(
            opacity: hint ? 1 : 0.35,
            duration: const Duration(milliseconds: 220),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
