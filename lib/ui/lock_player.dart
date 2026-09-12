import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/strings.dart';
import 'widgets.dart';

class LockPlayerScreen extends StatefulWidget {
  const LockPlayerScreen({super.key});

  @override
  State<LockPlayerScreen> createState() => _LockPlayerScreenState();
}

class _LockPlayerScreenState extends State<LockPlayerScreen> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    final track = player.current;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 400) Navigator.pop(context);
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            child: Column(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 36),
                ),
                const Spacer(),
                AspectRatio(
                  aspectRatio: 1,
                  child: CoverArt(track: track, expand: true, radius: 8, muted: true),
                ),
                const SizedBox(height: 28),
                MarqueeText(
                  track?.title ?? context.s.nothingPlaying,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                MarqueeText(
                  track == null ? '' : context.s.displayArtist(track.artist),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
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
                      icon: Icon(player.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded),
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
    );
  }
}
