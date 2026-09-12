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
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    final track = player.current;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF07141B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 32),
                ),
              ),
              const Spacer(),
              CoverArt(track: track, size: 220, radius: 20, muted: true),
              const SizedBox(height: 28),
              MarqueeText(
                track?.title ?? context.s.nothingPlaying,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              MarqueeText(
                track == null ? '' : context.s.displayArtist(track.artist),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: player.previous,
                    iconSize: 56,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: IconButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        player.playPause();
                      },
                      iconSize: 72,
                      color: Theme.of(context).colorScheme.onPrimary,
                      icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    ),
                  ),
                  IconButton(
                    onPressed: player.next,
                    iconSize: 56,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const SeekBar(),
            ],
          ),
        ),
      ),
    );
  }
}
