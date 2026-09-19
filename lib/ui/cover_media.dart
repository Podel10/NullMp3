import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../data/artwork.dart';
import '../data/cover_image.dart';
import '../data/cover_rim.dart';

class CoverBytesView extends StatelessWidget {
  const CoverBytesView({
    super.key,
    required this.bytes,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
    this.animate = false,
    this.playing = true,
    this.live,
    this.liveRim = false,
    this.artworkPath,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final bool animate;
  final bool playing;
  final bool? live;
  final bool liveRim;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    if (isVideoBytes(bytes)) {
      final playVideo = live ?? animate;
      if (!playVideo || kIsWeb) {
        return _VideoPosterCover(
          bytes: bytes,
          fit: fit,
          cacheWidth: cacheWidth,
          filterQuality: filterQuality,
          artworkPath: artworkPath,
          errorBuilder: errorBuilder,
        );
      }
      return _VideoCover(
        bytes: bytes,
        fit: fit,
        playing: playing,
        animate: animate,
        liveRim: liveRim,
        artworkPath: artworkPath,
        cacheWidth: cacheWidth,
        filterQuality: filterQuality,
        errorBuilder: errorBuilder,
      );
    }
    if (isGifBytes(bytes) || isWebpBytes(bytes)) {
      if (animate) {
        return _AnimatedRasterCover(
          bytes: bytes,
          fit: fit,
          playing: playing,
          cacheWidth: cacheWidth,
          errorBuilder: errorBuilder,
        );
      }
      return _StillRasterCover(
        bytes: bytes,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: errorBuilder,
      );
    }
    return memoryCoverImage(
      bytes,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: filterQuality,
      errorBuilder: errorBuilder,
    );
  }
}

class _StillRasterCover extends StatefulWidget {
  const _StillRasterCover({
    required this.bytes,
    required this.fit,
    this.cacheWidth,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_StillRasterCover> createState() => _StillRasterCoverState();
}

class _StillRasterCoverState extends State<_StillRasterCover> {
  ui.Image? _image;
  Object? _token;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(covariant _StillRasterCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) || oldWidget.cacheWidth != widget.cacheWidth) {
      unawaited(_decode());
    }
  }

  @override
  void dispose() {
    _token = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _decode() async {
    final token = Object();
    _token = token;
    _failed = false;
    try {
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: widget.cacheWidth,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || !identical(_token, token)) {
        frame.image.dispose();
        return;
      }
      final previous = _image;
      setState(() => _image = frame.image);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
    } catch (_) {
      if (mounted && identical(_token, token)) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorBuilder?.call(context, 'gif', StackTrace.empty) ??
          const ColoredBox(color: Color(0xFF3A4A56));
    }
    final image = _image;
    if (image == null) return const ColoredBox(color: Color(0xFF3A4A56));
    return RawImage(
      image: image,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.low,
    );
  }
}

class _AnimatedRasterCover extends StatefulWidget {
  const _AnimatedRasterCover({
    required this.bytes,
    required this.fit,
    required this.playing,
    this.cacheWidth,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final bool playing;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_AnimatedRasterCover> createState() => _AnimatedRasterCoverState();
}

class _AnimatedRasterCoverState extends State<_AnimatedRasterCover> {
  ui.Codec? _codec;
  ui.Image? _image;
  Object? _token;
  Completer<void>? _resume;
  Completer<void>? _delayAbort;
  var _failed = false;
  var _index = -1;
  Duration _hold = const Duration(milliseconds: 33);

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void didUpdateWidget(covariant _AnimatedRasterCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      unawaited(_start());
      return;
    }
    if (widget.playing) {
      _wake();
    } else {
      _abortDelay();
    }
  }

  @override
  void dispose() {
    _token = null;
    _wake();
    _abortDelay();
    _codec?.dispose();
    _codec = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  void _wake() {
    _resume?.complete();
    _resume = null;
  }

  void _abortDelay() {
    final abort = _delayAbort;
    _delayAbort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  Future<void> _waitWhilePaused() async {
    if (widget.playing) return;
    final waiter = _resume ??= Completer<void>();
    await waiter.future;
  }

  Future<void> _start() async {
    final token = Object();
    _token = token;
    _wake();
    _abortDelay();
    _codec?.dispose();
    _codec = null;
    _failed = false;
    _index = -1;
    try {
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: (widget.cacheWidth ?? 720).clamp(64, 720),
      );
      if (!mounted || !identical(_token, token)) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _showNext(token);
      if (math.max(1, codec.frameCount) > 1) unawaited(_loop(token));
    } catch (_) {
      if (mounted && identical(_token, token)) {
        final previous = _image;
        _image = null;
        setState(() => _failed = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
      }
    }
  }

  Future<void> _showNext(Object token) async {
    final codec = _codec;
    if (codec == null) return;
    final next = await codec.getNextFrame();
    if (!mounted || !identical(_token, token)) {
      next.image.dispose();
      return;
    }
    _applyFrame(next, token);
  }

  void _applyFrame(ui.FrameInfo next, Object token) {
    // GIF delay 0–1 cs is "as fast as possible"; keep 2 cs (50 fps) and 3 cs (30 fps).
    var hold = next.duration;
    if (hold.inMilliseconds < 20) hold = const Duration(milliseconds: 100);
    _hold = hold;
    final count = math.max(1, _codec?.frameCount ?? 1);
    _index = (_index + 1) % count;
    final previous = _image;
    _image = next.image;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previous?.dispose();
      if (!mounted || !identical(_token, token)) return;
      CoverMotionNotification(index: _index, count: count).dispatch(context);
    });
  }

  Future<void> _loop(Object token) async {
    while (mounted && identical(_token, token)) {
      await _waitWhilePaused();
      if (!mounted || !identical(_token, token)) return;
      final codec = _codec;
      if (codec == null) return;
      final pending = codec.getNextFrame();
      await _delayWhilePlaying(_hold);
      final ui.FrameInfo next;
      try {
        next = await pending;
      } catch (_) {
        return;
      }
      if (!mounted || !identical(_token, token)) {
        next.image.dispose();
        return;
      }
      _applyFrame(next, token);
    }
  }

  Future<void> _delayWhilePlaying(Duration wait) async {
    if (wait <= Duration.zero) return;
    if (!widget.playing) return;
    final abort = Completer<void>();
    _delayAbort = abort;
    try {
      await Future.any<void>([Future<void>.delayed(wait), abort.future]);
    } finally {
      if (identical(_delayAbort, abort)) _delayAbort = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorBuilder?.call(context, 'gif', StackTrace.empty) ??
          const ColoredBox(color: Color(0xFF3A4A56));
    }
    final image = _image;
    if (image == null) return const ColoredBox(color: Color(0xFF3A4A56));
    return RawImage(
      image: image,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _VideoPosterCover extends StatefulWidget {
  const _VideoPosterCover({
    required this.bytes,
    required this.fit,
    this.cacheWidth,
    this.filterQuality = FilterQuality.low,
    this.artworkPath,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final String? artworkPath;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_VideoPosterCover> createState() => _VideoPosterCoverState();
}

class _VideoPosterCoverState extends State<_VideoPosterCover> {
  Uint8List? _poster;
  Object? _token;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _VideoPosterCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) || oldWidget.artworkPath != widget.artworkPath) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _token = null;
    super.dispose();
  }

  Future<void> _load() async {
    final token = Object();
    _token = token;
    _failed = false;
    try {
      final poster = await ArtworkStore.instance.posterFor(widget.bytes, widget.artworkPath);
      if (!mounted || !identical(_token, token)) return;
      setState(() {
        _poster = poster;
        _failed = poster == null;
      });
    } catch (_) {
      if (mounted && identical(_token, token)) {
        setState(() {
          _poster = null;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poster = _poster;
    if (poster != null) {
      return Image.memory(
        poster,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: widget.filterQuality,
        cacheWidth: widget.cacheWidth,
        errorBuilder: widget.errorBuilder ??
            (_, _, _) => const ColoredBox(
              color: Color(0xFF3A4A56),
              child: Icon(Icons.movie_outlined, color: Colors.white54),
            ),
      );
    }
    if (_failed) {
      return widget.errorBuilder?.call(context, 'video', StackTrace.empty) ??
          const ColoredBox(
            color: Color(0xFF3A4A56),
            child: Icon(Icons.movie_outlined, color: Colors.white54),
          );
    }
    return const ColoredBox(color: Color(0xFF3A4A56));
  }
}

class _VideoCover extends StatefulWidget {
  const _VideoCover({
    required this.bytes,
    required this.fit,
    required this.playing,
    required this.animate,
    this.liveRim = false,
    this.artworkPath,
    this.cacheWidth,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final bool playing;
  final bool animate;
  final bool liveRim;
  final String? artworkPath;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_VideoCover> createState() => _VideoCoverState();
}

class _VideoCoverState extends State<_VideoCover> {
  final GlobalKey _bound = GlobalKey();
  VideoPlayerController? _player;
  Object? _token;
  Timer? _rimTimer;
  Uint8List? _poster;
  var _failed = false;
  var _rimBusy = false;
  var _primed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant _VideoCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) || oldWidget.artworkPath != widget.artworkPath) {
      unawaited(_open());
      return;
    }
    if (oldWidget.playing != widget.playing ||
        oldWidget.animate != widget.animate ||
        oldWidget.liveRim != widget.liveRim) {
      unawaited(_syncPlayback());
      _tuneRimTimer();
    }
  }

  @override
  void dispose() {
    _token = null;
    _rimTimer?.cancel();
    _rimTimer = null;
    final player = _player;
    _player = null;
    player?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final token = Object();
    _token = token;
    _rimTimer?.cancel();
    _rimTimer = null;
    final old = _player;
    _player = null;
    if (mounted) setState(() {});
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
      });
    }
    _failed = false;
    _primed = false;
    _poster = null;
    unawaited(_loadPoster(token));
    try {
      final file = await _videoFile(widget.bytes, widget.artworkPath);
      if (!mounted || !identical(_token, token)) return;
      if (file == null) {
        setState(() => _failed = true);
        return;
      }
      final player = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await player.initialize();
      if (!mounted || !identical(_token, token)) {
        await player.dispose();
        return;
      }
      await player.setVolume(0);
      await player.setLooping(true);
      _player = player;
      setState(() {});
      await _syncPlayback();
      _tuneRimTimer();
    } catch (_) {
      if (mounted && identical(_token, token)) setState(() => _failed = true);
    }
  }

  Future<void> _loadPoster(Object token) async {
    try {
      final poster = await ArtworkStore.instance.posterFor(widget.bytes, widget.artworkPath);
      if (!mounted || !identical(_token, token) || poster == null) return;
      setState(() => _poster = poster);
    } catch (_) {}
  }

  Future<void> _syncPlayback() async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    try {
      if (widget.animate && widget.playing) {
        await player.play();
        _primed = true;
        return;
      }
      if (!_primed) {
        await player.play();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        _primed = true;
      }
      await player.pause();
    } catch (_) {}
  }

  void _tuneRimTimer() {
    _rimTimer?.cancel();
    _rimTimer = null;
    if (!widget.liveRim || !widget.animate || !widget.playing) return;
    final path = widget.artworkPath;
    if (path == null || path.isEmpty) return;
    _rimTimer = Timer.periodic(const Duration(milliseconds: 220), (_) => unawaited(_pushRim()));
    unawaited(_pushRim());
  }

  Future<void> _pushRim() async {
    if (_rimBusy || !mounted || !widget.liveRim || !widget.playing) return;
    final path = widget.artworkPath;
    if (path == null || path.isEmpty) return;
    final box = _bound.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    _rimBusy = true;
    try {
      final image = await box.toImage(pixelRatio: 0.12);
      try {
        final colors = await sampleRimFromImage(image, circle: false);
        if (colors.length >= 2) CoverRimLive.instance.push(path, colors);
      } finally {
        image.dispose();
      }
    } catch (_) {
    } finally {
      _rimBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorBuilder?.call(context, 'video', StackTrace.empty) ??
          const ColoredBox(
            color: Color(0xFF3A4A56),
            child: Icon(Icons.movie_outlined, color: Colors.white54),
          );
    }
    final player = _player;
    if (player == null || !player.value.isInitialized) {
      final poster = _poster;
      if (poster != null) {
        return Image.memory(
          poster,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          filterQuality: widget.filterQuality,
          cacheWidth: widget.cacheWidth,
        );
      }
      return const ColoredBox(color: Color(0xFF3A4A56));
    }
    final size = player.value.size;
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;
    return RepaintBoundary(
      key: _bound,
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(player),
        ),
      ),
    );
  }
}

Future<File?> _videoFile(Uint8List bytes, String? trackPath) async {
  if (trackPath != null && trackPath.isNotEmpty) {
    try {
      final cached = await ArtworkStore.instance.mediaFile(trackPath);
      if (cached != null) return cached;
    } catch (_) {}
  }
  try {
    final dir = await getTemporaryDirectory();
    final ext = artworkExtension(bytes);
    final stamp = '${bytes.length}_${bytes[0]}_${bytes[bytes.length >> 1]}_${bytes[bytes.length - 1]}';
    final file = File(p.join(dir.path, 'cover_$stamp.$ext'));
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: false);
    }
    return file;
  } catch (_) {
    return null;
  }
}
