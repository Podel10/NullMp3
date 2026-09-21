import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/artwork.dart';
import '../data/cover_image.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../theme/app_theme.dart';
import 'cover_media.dart';
import 'now_playing.dart';
import 'player_options.dart';

LibraryController contextLibrary(BuildContext context, {bool listen = true}) =>
    Provider.of<LibraryController>(context, listen: listen);

PlayerController contextPlayer(BuildContext context, {bool listen = true}) =>
    Provider.of<PlayerController>(context, listen: listen);

class CoverArt extends StatefulWidget {
  const CoverArt({
    super.key,
    required this.track,
    this.size = 56,
    this.radius = 10,
    this.heroTag,
    this.expand = false,
    this.muted = false,
    this.loadArtwork,
    this.animate = false,
    this.liveRim = false,
    this.softEdge = false,
  });

  final Track? track;
  final double size;
  final double radius;
  final Object? heroTag;
  final bool expand;
  final bool muted;
  final bool? loadArtwork;
  final bool animate;
  final bool liveRim;
  final bool softEdge;

  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  Uint8List? _bytes;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ArtworkStore.instance.addListener(_onArtwork);
    _generation = ArtworkStore.instance.generationOf(widget.track?.path ?? '');
    if (_shouldLoadArtwork) _load();
  }

  @override
  void dispose() {
    ArtworkStore.instance.removeListener(_onArtwork);
    super.dispose();
  }

  void _onArtwork() {
    final gen = ArtworkStore.instance.generationOf(widget.track?.path ?? '');
    if (gen == _generation) return;
    _generation = gen;
    if (_shouldLoadArtwork) _load();
  }

  bool get _shouldLoadArtwork => widget.loadArtwork ?? (widget.expand || !widget.muted);

  @override
  void didUpdateWidget(covariant CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    final gen = ArtworkStore.instance.generationOf(widget.track?.path ?? '');
    if (oldWidget.track?.path != widget.track?.path || gen != _generation) {
      _generation = gen;
      _bytes = null;
      if (_shouldLoadArtwork) _load();
    }
  }

  Future<void> _load() async {
    final path = widget.track?.path;
    if (path == null) return;
    var bytes = await ArtworkStore.instance.get(path);
    if (!mounted) return;
    if (widget.track?.path != path) return;
    // Still covers must show the video's first frame, not an empty box while
    // the header stub waits on a poster that never paints.
    if (bytes != null && isVideoBytes(bytes) && !widget.animate) {
      final shot = await ArtworkStore.instance.poster(path);
      if (!mounted || widget.track?.path != path) return;
      if (shot != null) bytes = shot;
    }
    setState(() {
      _bytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seed = widget.track?.albumKey ?? widget.track?.title ?? '?';
    final iconSize = widget.expand ? 80.0 : widget.size * 0.42;
    final circle = widget.track?.isCircleCover ?? false;
    final playing = widget.animate && context.select<PlayerController, bool>((player) => player.playing);
    Widget child = SizedBox(
      width: widget.expand ? double.infinity : widget.size,
      height: widget.expand ? double.infinity : widget.size,
      child: _bytes == null
          ? _Placeholder(seed: seed, iconSize: iconSize, muted: widget.muted)
          : CoverBytesView(
              bytes: _bytes!,
              fit: BoxFit.cover,
              animate: widget.animate,
              playing: playing,
              live: widget.animate,
              liveRim: widget.liveRim,
              artworkPath: widget.track?.path,
              filterQuality: widget.expand ? FilterQuality.medium : FilterQuality.low,
              // Decode for *display* only — saved art can be larger (kCoverMaxSide).
              // Cap harder while animating on Android: GIF decode + beat-halo rim
              // scan used to pile on at play start.
              cacheWidth: ((widget.expand ? 720 : widget.size) *
                      (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2))
                  .round()
                  .clamp(
                    48,
                    widget.expand
                        ? (widget.animate &&
                                !kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.android
                            ? 960
                            : 1440)
                        : 720,
                  ),
              errorBuilder: (_, _, _) => _Placeholder(seed: seed, iconSize: iconSize, muted: widget.muted),
            ),
    );
    child = circle
        ? ClipOval(child: child)
        : ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: child,
          );
    if (widget.softEdge && circle) {
      child = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          return const RadialGradient(
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0xB3FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0.0, 0.76, 0.88, 1.0],
          ).createShader(bounds);
        },
        child: child,
      );
    }
    if (widget.expand && circle) {
      child = Center(child: AspectRatio(aspectRatio: 1, child: child));
    }
    final animated = _bytes != null && isAnimatedCover(_bytes!);
    if (widget.heroTag == null || animated) {
      return RepaintBoundary(child: child);
    }
    return Hero(tag: widget.heroTag!, child: RepaintBoundary(child: child));
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seed, required this.iconSize, this.muted = false});
  final String seed;
  final double iconSize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (muted) {
      return ColoredBox(
        color: const Color(0xFF3A4A56),
        child: Icon(Icons.music_note, color: Colors.white54, size: iconSize),
      );
    }
    final color = colorFor(seed);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
        ),
      ),
      child: Icon(Icons.music_note_rounded, color: Colors.white70, size: iconSize),
    );
  }
}

Color colorFor(String seed) {
  final hash = seed.hashCode;
  final hue = (hash % 360).abs().toDouble();
  return HSLColor.fromAHSL(1, hue, 0.48, 0.32).toColor();
}

class MarqueeText extends StatelessWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.left,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: style,
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({
    super.key,
    required this.onScan,
    required this.onAddFiles,
    required this.onAddFolder,
    this.message,
  });

  final VoidCallback onScan;
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music_rounded, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(context.s.noMusicYet, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                message ?? context.s.emptyLibraryHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.s.updateLibrary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onAddFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(context.s.addFolder),
                  ),
                  TextButton.icon(
                    onPressed: onAddFiles,
                    icon: const Icon(Icons.audio_file_rounded),
                    label: Text(context.s.addFiles),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.onOpen,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
  });

  final VoidCallback onOpen;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlayerController, Track?>((p) => p.current);
    if (track == null) return const SizedBox.shrink();
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final artworkColor = context.select<PlayerController, Color?>((p) => p.artworkColor);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: Color.lerp(
              theme.scaffoldBackgroundColor,
              AppTheme.ambientFromArtwork(
                artworkColor,
                dark: theme.brightness == Brightness.dark,
              ),
              0.72,
            ),
            border: Border(
              top: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Column(
            children: [
              StreamBuilder<Duration>(
                stream: context.read<PlayerController>().positionClock,
                builder: (context, snapshot) {
                  final player = context.read<PlayerController>();
                  final pos = snapshot.data ?? Duration.zero;
                  final dur = player.totalDuration;
                  final value = dur.inMilliseconds == 0
                      ? 0.0
                      : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                    color: accent,
                  );
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      CoverArt(track: track, size: 40, radius: 8, muted: true, loadArtwork: true, heroTag: 'now-art'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarqueeText(
                              track.title,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            MarqueeText(
                              context.s.displayArtist(track.artist),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onPrevious,
                        tooltip: context.s.previousTrack,
                        icon: const Icon(Icons.skip_previous_rounded, size: 28),
                      ),
                      IconButton(
                        onPressed: onPlayPause,
                        icon: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 30,
                        ),
                      ),
                      IconButton(
                        onPressed: onNext,
                        tooltip: context.s.nextTrack,
                        icon: const Icon(Icons.skip_next_rounded, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SeekBar extends StatelessWidget {
  const SeekBar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = contextPlayer(context);
    return StreamBuilder<Duration>(
      stream: player.positionClock,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.totalDuration;
        return Column(
          children: [
            Slider(
              max: duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds.toDouble(),
              value: position.inMilliseconds.clamp(0, duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds).toDouble(),
              onChanged: (value) => player.seek(Duration(milliseconds: value.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                children: [
                  Text(formatDuration(position), style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  Text(formatDuration(duration), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

void showSleepTimerSheet(BuildContext context) {
  final player = contextPlayer(context, listen: false);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF0E2A38),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.s.sleepTimer,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              for (final minutes in [5, 15, 30, 45, 60, 90])
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.alarm_outlined),
                  title: Text(context.s.minutesLabel(minutes)),
                  onTap: () {
                    player.setSleepTimer(Duration(minutes: minutes));
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.skip_next_outlined),
                title: Text(context.s.endOfTrack),
                onTap: () {
                  player.setSleepEndOfTrack();
                  Navigator.pop(context);
                },
              ),
              if (player.sleepKind != SleepKind.off)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.timer_off_outlined),
                  title: Text(context.s.turnOff),
                  onTap: () {
                    player.clearSleep();
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

void showSongMenu(BuildContext context, Track track, {Playlist? playlist}) {
  showPlayerOptionsSheet(context, track, playlist: playlist);
}

Future<void> showAddToPlaylistSheet(BuildContext context, Track track) async {
  final library = contextLibrary(context, listen: false);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
            ListTile(
              title: Text(context.s.addToPlaylist, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: Text(context.s.newPlaylist),
              onTap: () async {
                Navigator.pop(context);
                final name = await promptName(context, title: context.s.newPlaylist);
                if (name == null || name.trim().isEmpty) return;
                await library.createPlaylist(name.trim());
                await library.addToPlaylist(library.playlists.last.id, track);
              },
            ),
            for (final playlist in library.playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                subtitle: Text(context.s.songsCount(playlist.trackPaths.length)),
                onTap: () {
                  library.addToPlaylist(playlist.id, track);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> promptName(BuildContext context, {required String title, String? initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: context.s.nameHint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.s.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(context.s.save)),
      ],
    ),
  );
}

void showTrackInfo(BuildContext context, Track track) {
  final s = context.s;
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.trackDetails),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(s.fieldTitle, track.title),
          _InfoRow(s.fieldArtist, s.displayArtist(track.artist)),
          _InfoRow(s.fieldAlbum, s.displayAlbum(track.album)),
          _InfoRow(s.fieldGenre, track.genre),
          if (track.year != null) _InfoRow(s.fieldYear, '${track.year}'),
          _InfoRow(s.fieldDuration, formatDuration(track.duration)),
          _InfoRow(s.fieldPath, track.path),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.close))],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label\n', style: Theme.of(context).textTheme.labelSmall),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.track,
    required this.onTap,
    this.playlist,
    this.trailing,
    this.selected = false,
    this.openPlayer = true,
    this.detail,
  });

  final Track track;
  final Future<void> Function() onTap;
  final Playlist? playlist;
  final Widget? trailing;
  final bool selected;
  final bool openPlayer;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.colorScheme.primary : null;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      contentPadding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      minLeadingWidth: 48,
      horizontalTitleGap: 12,
      onTap: () {
        unawaited(onTap());
        if (openPlayer && context.mounted) {
          unawaited(openNowPlaying(context));
        }
      },
      onLongPress: () => showSongMenu(context, track, playlist: playlist),
      leading: CoverArt(track: track, size: 48, radius: 8, muted: true, loadArtwork: true),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        detail == null
            ? '${context.s.displayArtist(track.artist)} • ${formatDuration(track.duration)}'
            : '$detail • ${context.s.displayArtist(track.artist)} • ${formatDuration(track.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          fontSize: 12,
        ),
      ),
      trailing: trailing ??
          IconButton(
            icon: Icon(
              Icons.more_vert_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => showSongMenu(context, track, playlist: playlist),
          ),
    );
  }
}

class PlayHeader extends StatelessWidget {
  const PlayHeader({
    super.key,
    required this.countLabel,
    required this.onPlay,
    required this.onShuffle,
  });

  final String countLabel;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactFill = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final compactOut = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: onPlay,
                    style: compactFill,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(context.s.playAll),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onShuffle,
                    style: compactOut,
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    label: Text(context.s.shuffle),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            countLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
