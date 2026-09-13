import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/cover_image.dart';

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
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final bool animate;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    if (isVideoBytes(bytes)) {
      return errorBuilder?.call(context, 'video', StackTrace.empty) ??
          const ColoredBox(color: Color(0xFF3A4A56));
    }
    if (animate && (isGifBytes(bytes) || isWebpBytes(bytes))) {
      return _AnimatedRasterCover(
        bytes: bytes,
        fit: fit,
        playing: playing,
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

class _AnimatedRasterCover extends StatefulWidget {
  const _AnimatedRasterCover({
    required this.bytes,
    required this.fit,
    required this.playing,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final bool playing;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_AnimatedRasterCover> createState() => _AnimatedRasterCoverState();
}

class _AnimatedRasterCoverState extends State<_AnimatedRasterCover> {
  ui.Codec? _codec;
  ui.Image? _image;
  Object? _token;
  Completer<void>? _resume;
  var _failed = false;

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
    if (widget.playing) _wake();
  }

  @override
  void dispose() {
    _token = null;
    _wake();
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

  Future<void> _waitWhilePaused() async {
    if (widget.playing) return;
    final waiter = _resume ??= Completer<void>();
    await waiter.future;
  }

  Future<void> _start() async {
    final token = Object();
    _token = token;
    _wake();
    _codec?.dispose();
    _codec = null;
    _image?.dispose();
    _image = null;
    _failed = false;
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      if (!mounted || !identical(_token, token)) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _showNext(token);
      if (codec.frameCount > 1) unawaited(_loop(token));
    } catch (_) {
      if (mounted && identical(_token, token)) setState(() => _failed = true);
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
    final previous = _image;
    _image = next.image;
    setState(() {});
    previous?.dispose();
  }

  Future<void> _loop(Object token) async {
    while (mounted && identical(_token, token)) {
      await _waitWhilePaused();
      if (!mounted || !identical(_token, token)) return;
      if (!widget.playing) continue;
      final codec = _codec;
      if (codec == null) return;
      final next = await codec.getNextFrame();
      var wait = next.duration;
      if (wait.inMilliseconds < 20) wait = const Duration(milliseconds: 80);
      if (!mounted || !identical(_token, token) || !widget.playing) {
        next.image.dispose();
        continue;
      }
      final previous = _image;
      _image = next.image;
      setState(() {});
      previous?.dispose();
      await Future<void>.delayed(wait);
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
