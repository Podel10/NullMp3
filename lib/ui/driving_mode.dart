import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/strings.dart';
import 'widgets.dart';

class DrivingModeScreen extends StatefulWidget {
  const DrivingModeScreen({super.key});

  @override
  State<DrivingModeScreen> createState() => _DrivingModeScreenState();
}

class _DrivingModeScreenState extends State<DrivingModeScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      contextPlayer(context, listen: false).ensureBrowsableQueue();
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  void _skip(bool next) {
    HapticFeedback.mediumImpact();
    final player = contextPlayer(context, listen: false);
    player.ensureBrowsableQueue();
    if (next) {
      unawaited(player.next());
    } else {
      unawaited(player.previous());
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    final track = player.current;
    final accent = Theme.of(context).colorScheme.primary;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF05090C),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity <= -350) _skip(true);
          if (velocity >= 350) _skip(false);
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 36),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CoverArt(track: track, size: 220, radius: 18, muted: true, loadArtwork: true),
                      const SizedBox(height: 22),
                      MarqueeText(
                        track?.title ?? context.s.nothingPlaying,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      MarqueeText(
                        track == null ? '' : context.s.displayArtist(track.artist),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: const SeekBar(),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _DriveButton(
                      icon: Icons.skip_previous_rounded,
                      onTap: () => _skip(false),
                    ),
                    _DriveButton(
                      icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      filled: true,
                      color: accent,
                      size: 100,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        unawaited(player.playPause());
                      },
                    ),
                    _DriveButton(
                      icon: Icons.skip_next_rounded,
                      onTap: () => _skip(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveButton extends StatelessWidget {
  const _DriveButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.color,
    this.size = 84,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = filled ? (color ?? Colors.white) : const Color(0xFF1A242C);
    final foreground = filled ? Colors.black : Colors.white;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: size * 0.46, color: foreground),
        ),
      ),
    );
  }
}
