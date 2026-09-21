import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import '../data/artwork.dart';
import '../data/cover_image.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/settings.dart';
import '../theme/app_theme.dart';
import 'beat_halo.dart';
import 'cover_lyrics.dart';
import 'interactive_cover.dart';
import 'platform_features.dart';
import 'widgets.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    final track = player.current;
    final theme = Theme.of(context);
    final settings = context.watch<SettingsController>();
    final gallery = settings.themeId == AppThemeId.gallery;

    if (track == null) {
      return Scaffold(
        appBar: embedded ? null : AppBar(),
        body: Center(child: Text(context.s.nothingPlaying)),
      );
    }

    final dark = theme.brightness == Brightness.dark;
    final ambient = AppTheme.ambientFromArtwork(player.artworkColor, dark: dark);
    final onAmbient = ambient.computeLuminance() < 0.45 ? Colors.white : const Color(0xFF1A1512);
    final muted = onAmbient.withValues(alpha: 0.62);
    final haloColor = _haloFromArtwork(player.artworkColor, theme.colorScheme.primary);
    final playFill = dark ? Colors.white : const Color(0xFF111111);
    final playIcon = dark ? const Color(0xFF111111) : Colors.white;

    final body = _ArtworkAtmosphere(
      track: track,
      tint: ambient,
      enabled: !gallery,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: BeatHalo(
            key: ValueKey('halo-${track.path}-${track.coverShape.name}'),
            enabled: settings.beatHalo,
            advanced: settings.beatHaloMode == BeatHaloMode.advanced,
            playing: player.playing,
            circle: track.isCircleCover,
            color: haloColor,
            artworkPath: track.path,
            sessionId: player.player.androidAudioSessionId,
            sessionIds: player.player.androidAudioSessionIdStream,
            positionStream: player.positionClock,
            durationOf: () => player.totalDuration,
            child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Row(
                  children: [
                    if (!embedded)
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        color: onAmbient,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      )
                    else
                      const SizedBox(width: 48),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            context.s.playingFrom,
                            style: theme.textTheme.bodySmall?.copyWith(color: muted, fontSize: 12),
                          ),
                          Text(
                            track.folderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(color: onAmbient.withValues(alpha: 0.78)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => showSongMenu(context, track),
                      color: onAmbient,
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.biggest.shortestSide;
                      return Center(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: _NowPlayingCover(
                            track: track,
                            onAmbient: onAmbient,
                            interactiveCover: pcParityEnabled && settings.interactiveCover,
                            interactiveMode: settings.interactiveCoverMode,
                            lyricsButton: pcParityEnabled && settings.showLyricsOnCover,
                            beatHalo: settings.beatHalo,
                            beatHaloAdvanced: settings.beatHaloMode == BeatHaloMode.advanced,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: player.toggleFavorite,
                      color: onAmbient,
                      icon: Icon(player.isFavorite(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          MarqueeText(
                            track.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: onAmbient,
                            ),
                          ),
                          const SizedBox(height: 2),
                          MarqueeText(
                            context.s.displayArtist(track.artist),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showQueue(context),
                      color: muted,
                      icon: const Icon(Icons.queue_music_rounded),
                    ),
                  ],
                ),
              ),
              _NowSeekBar(active: onAmbient, inactive: onAmbient.withValues(alpha: 0.22)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      onPressed: player.cycleRepeat,
                      tooltip: context.s.repeatTrack,
                      color: player.repeat == RepeatKind.one ? onAmbient : muted,
                      icon: const Icon(Icons.repeat_rounded),
                    ),
                    IconButton(
                      onPressed: player.previous,
                      tooltip: context.s.previousTrack,
                      color: onAmbient,
                      icon: const Icon(Icons.skip_previous_rounded, size: 42),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(color: playFill, shape: BoxShape.circle),
                      child: IconButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          player.playPause();
                        },
                        tooltip: player.playing ? context.s.pause : context.s.play,
                        iconSize: 46,
                        color: playIcon,
                        icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      ),
                    ),
                    IconButton(
                      onPressed: player.next,
                      tooltip: context.s.nextTrack,
                      color: onAmbient,
                      icon: const Icon(Icons.skip_next_rounded, size: 42),
                    ),
                    IconButton(
                      onPressed: player.toggleShuffle,
                      tooltip: player.shuffle ? context.s.shuffleOn : context.s.shuffleOff,
                      color: player.shuffle ? onAmbient : muted,
                      icon: const Icon(Icons.shuffle_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 52),
            ],
          ),
          ),
        ),
      ),
    );

    if (embedded) return body;
    return Scaffold(backgroundColor: gallery ? Colors.transparent : ambient, body: body);
  }
}

Color _haloFromArtwork(Color? source, Color fallback) {
  final base = source ?? fallback;
  final hsl = HSLColor.fromColor(base);
  final chroma = (base.r - base.g).abs() + (base.g - base.b).abs() + (base.b - base.r).abs();
  if (hsl.lightness < 0.08 || chroma < 0.12) {
    return const Color(0xFF8A9096);
  }
  return hsl
      .withSaturation((hsl.saturation * 1.08).clamp(0.0, 0.88).toDouble())
      .withLightness((hsl.lightness * 0.42 + 0.4).clamp(0.36, 0.74).toDouble())
      .toColor();
}

class _NowPlayingCover extends StatefulWidget {
  const _NowPlayingCover({
    required this.track,
    required this.onAmbient,
    required this.interactiveCover,
    required this.interactiveMode,
    required this.lyricsButton,
    required this.beatHalo,
    required this.beatHaloAdvanced,
  });

  final Track track;
  final Color onAmbient;
  final bool interactiveCover;
  final InteractiveCoverMode interactiveMode;
  final bool lyricsButton;
  final bool beatHalo;
  final bool beatHaloAdvanced;

  @override
  State<_NowPlayingCover> createState() => _NowPlayingCoverState();
}

class _NowPlayingCoverState extends State<_NowPlayingCover> {
  bool _lyricsOpen = false;

  @override
  void didUpdateWidget(covariant _NowPlayingCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.path != widget.track.path) {
      _lyricsOpen = false;
    }
    if (!widget.lyricsButton && _lyricsOpen) {
      _lyricsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final art = BeatHaloCover(
      child: CoverArt(
        key: ValueKey('art-${track.path}-${track.coverShape.name}'),
        track: track,
        radius: 10,
        expand: true,
        muted: true,
        loadArtwork: true,
        animate: true,
        liveRim: widget.beatHalo && widget.beatHaloAdvanced,
        softEdge: widget.beatHalo && track.isCircleCover,
        heroTag: 'now-art',
      ),
    );

    return InteractiveCover(
      // Volume drag while lyrics are open fights the karaoke layer.
      enabled: widget.interactiveCover && !_lyricsOpen,
      mode: widget.interactiveMode,
      child: Stack(
        fit: StackFit.expand,
        children: [
          art,
          if (_lyricsOpen) CoverLyricsOverlay(track: track),
          if (widget.lyricsButton)
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: context.s.lyricsOnCover,
                  onPressed: () => setState(() => _lyricsOpen = !_lyricsOpen),
                  color: Colors.white,
                  icon: Icon(
                    _lyricsOpen ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArtworkAtmosphere extends StatefulWidget {
  const _ArtworkAtmosphere({
    required this.track,
    required this.tint,
    required this.child,
    this.enabled = true,
  });

  final Track track;
  final Color tint;
  final Widget child;
  final bool enabled;

  @override
  State<_ArtworkAtmosphere> createState() => _ArtworkAtmosphereState();
}

class _ArtworkAtmosphereState extends State<_ArtworkAtmosphere> {
  Future<Uint8List?>? _bytesFuture;
  String? _path;

  @override
  void initState() {
    super.initState();
    _path = widget.track.path;
    _bytesFuture = ArtworkStore.instance.get(_path!);
  }

  @override
  void didUpdateWidget(covariant _ArtworkAtmosphere oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.path != widget.track.path) {
      _path = widget.track.path;
      _bytesFuture = ArtworkStore.instance.get(_path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ColoredBox(color: widget.tint),
            if (bytes != null && bytes.isNotEmpty && !isVideoBytes(bytes) && !isAnimatedCover(bytes))
              Opacity(
                opacity: 0.36,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.decal),
                  child: Transform.scale(
                    scale: 1.25,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      cacheWidth: 48,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),
              ),
            ColoredBox(color: widget.tint.withValues(alpha: 0.58)),
            widget.child,
          ],
        );
      },
    );
  }
}

class _NowSeekBar extends StatelessWidget {
  const _NowSeekBar({required this.active, required this.inactive});

  final Color active;
  final Color inactive;

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    return StreamBuilder<Duration>(
      stream: player.positionClock,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.totalDuration;
        final max = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Column(
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: active,
                  inactiveTrackColor: inactive,
                  thumbColor: active,
                ),
                child: SizedBox(
                  height: 28,
                  child: Slider(
                    max: max,
                    value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                    onChanged: (value) => player.seek(Duration(milliseconds: value.round())),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
                child: Row(
                  children: [
                    Text(formatDuration(position), style: TextStyle(color: inactive.withValues(alpha: 0.9), fontSize: 12)),
                    const Spacer(),
                    Text(formatDuration(duration), style: TextStyle(color: inactive.withValues(alpha: 0.9), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void _showQueue(BuildContext context) {
  final player = contextPlayer(context, listen: false);
  final theme = Theme.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: true,
    backgroundColor: Color.lerp(theme.scaffoldBackgroundColor, player.artworkColor ?? theme.colorScheme.primary, 0.22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ListView.builder(
            itemCount: player.queue.length,
            itemBuilder: (context, i) {
              final track = player.queue[i];
              return SongTile(
                track: track,
                selected: i == player.index,
                openPlayer: false,
                onTap: () => player.playAt(i),
              );
            },
          ),
        ),
      );
    },
  );
}

Future<void> openNowPlaying(BuildContext context) {
  if (context.findAncestorWidgetOfExactType<NowPlayingScreen>() != null) {
    return Future.value();
  }
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const NowPlayingScreen(),
      transitionsBuilder: (_, animation, _, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    ),
  );
}
