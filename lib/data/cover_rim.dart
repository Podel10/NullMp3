import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'cover_image.dart';

const rimBandCount = 16;

class CoverRimFrame {
  const CoverRimFrame({required this.colors, required this.duration});

  final List<Color> colors;
  final Duration duration;
}

/// Timed rim palettes for GIF/WebP. Video will not pre-scan the whole file;
/// it should [CoverRimLive.push] the current frame instead.
class CoverRimSequence {
  const CoverRimSequence(this.frames);

  static const empty = CoverRimSequence([]);

  final List<CoverRimFrame> frames;

  bool get isAnimated => frames.length > 1;

  List<Color> get first => frames.isEmpty ? const [] : frames.first.colors;

  List<Color> at(Duration elapsed) {
    if (frames.isEmpty) return const [];
    if (frames.length == 1) return frames.first.colors;
    var ms = elapsed.inMilliseconds;
    if (ms < 0) ms = 0;
    var total = 0;
    for (final frame in frames) {
      total += _holdMs(frame.duration);
    }
    if (total <= 0) return frames.first.colors;
    ms %= total;
    for (final frame in frames) {
      final hold = _holdMs(frame.duration);
      if (ms < hold) return frame.colors;
      ms -= hold;
    }
    return frames.last.colors;
  }
}

class CoverRimLiveFrame {
  const CoverRimLiveFrame(this.path, this.colors);

  final String path;
  final List<Color> colors;
}

/// Fired by the on-screen cover when it advances a GIF/WebP frame so the halo
/// can use the matching rim instead of a second clock.
class CoverMotionNotification extends Notification {
  const CoverMotionNotification({required this.index, required this.count});

  final int index;
  final int count;
}

/// Sink for covers that only exist as a live picture (video). GIF/WebP stay
/// on [CoverRimSequence]; a future video widget posts frames here.
class CoverRimLive {
  CoverRimLive._();

  static final CoverRimLive instance = CoverRimLive._();

  final StreamController<CoverRimLiveFrame> _controller =
      StreamController<CoverRimLiveFrame>.broadcast();
  String? _lastPath;
  List<Color> _lastColors = const [];

  Stream<CoverRimLiveFrame> get stream => _controller.stream;

  void push(String path, List<Color> colors) {
    if (path.isEmpty || colors.length < 2) return;
    if (path == _lastPath && sameRim(_lastColors, colors)) return;
    _lastPath = path;
    _lastColors = colors;
    _controller.add(CoverRimLiveFrame(path, colors));
  }
}

bool sameRim(List<Color> a, List<Color> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<CoverRimSequence> sampleCoverRimSequence(
  Uint8List? bytes, {
  required bool circle,
}) async {
  if (bytes == null || bytes.length < 32) return CoverRimSequence.empty;
  if (isVideoBytes(bytes)) return CoverRimSequence.empty;
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
    final count = math.max(1, codec.frameCount);
    // Cap aggressively — full GIF scan while the cover is also animating has
    // spiked memory enough to kill the process on mid-range phones.
    final limit = math.min(count, 48);
    final frames = <CoverRimFrame>[];
    for (var i = 0; i < limit; i++) {
      final frame = await codec.getNextFrame();
      try {
        var colors = await sampleRimFromImage(frame.image, circle: circle);
        if (colors.isEmpty && frames.isNotEmpty) colors = frames.last.colors;
        if (colors.isEmpty) continue;
        var hold = frame.duration;
        if (hold.inMilliseconds < 20) hold = const Duration(milliseconds: 100);
        frames.add(CoverRimFrame(colors: colors, duration: hold));
      } finally {
        frame.image.dispose();
      }
      if (i % 4 == 3) await Future<void>.delayed(Duration.zero);
    }
    codec.dispose();
    if (frames.isEmpty) return CoverRimSequence.empty;
    return CoverRimSequence(frames);
  } catch (_) {
    return CoverRimSequence.empty;
  }
}

Future<List<Color>> sampleRimFromBytes(
  Uint8List bytes, {
  required bool circle,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
    final frame = await codec.getNextFrame();
    codec.dispose();
    try {
      return await sampleRimFromImage(frame.image, circle: circle);
    } finally {
      frame.image.dispose();
    }
  } catch (_) {
    return const [];
  }
}

Future<List<Color>> sampleRimFromImage(ui.Image image, {required bool circle}) async {
  final width = image.width;
  final height = image.height;
  if (width < 8 || height < 8) return const [];
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return const [];
  return sampleRimFromRgba(data.buffer.asUint8List(), width, height, circle: circle);
}

List<Color> sampleRimFromRgba(
  Uint8List rgba,
  int width,
  int height, {
  required bool circle,
}) {
  if (width < 8 || height < 8 || rgba.length < width * height * 4) return const [];
  return [
    for (var i = 0; i < rimBandCount; i++)
      _rimColorAlongRay(rgba, width, height, i / rimBandCount, circle),
  ];
}

int _holdMs(Duration duration) => duration.inMilliseconds.clamp(20, 5000);

ui.Offset _rimPoint(double t, double width, double height, bool circle, [double inset = 0.82]) {
  final center = ui.Offset(width / 2, height / 2);
  final angle = t * math.pi * 2 - math.pi / 2;
  final dir = ui.Offset(math.cos(angle), math.sin(angle));
  final halfW = width / 2;
  final halfH = height / 2;
  final double reach;
  if (circle) {
    reach = math.min(halfW, halfH);
  } else {
    final byX = dir.dx.abs() < 1e-4 ? double.infinity : halfW / dir.dx.abs();
    final byY = dir.dy.abs() < 1e-4 ? double.infinity : halfH / dir.dy.abs();
    reach = math.min(byX, byY);
  }
  return center + dir * reach * inset;
}

Color _rimColorAlongRay(Uint8List rgba, int width, int height, double t, bool circle) {
  Color? best;
  var bestScore = -1.0;
  for (final inset in const [0.9, 0.76, 0.6, 0.44, 0.28]) {
    final sample = _rimColorAt(rgba, width, height, _rimPoint(t, width.toDouble(), height.toDouble(), circle, inset));
    final score = _coverColorScore(sample);
    if (score > bestScore) {
      bestScore = score;
      best = sample;
    }
    if (score >= 0.2) break;
  }
  return _haloTint(best ?? const Color(0xFF7A8086));
}

Color _rimColorAt(Uint8List rgba, int width, int height, ui.Offset point) {
  var r = 0;
  var g = 0;
  var b = 0;
  var count = 0;
  final cx = point.dx.round();
  final cy = point.dy.round();
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final x = (cx + dx).clamp(0, width - 1).toInt();
      final y = (cy + dy).clamp(0, height - 1).toInt();
      final i = (y * width + x) * 4;
      if (rgba[i + 3] < 8) continue;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      count++;
    }
  }
  if (count == 0) return const Color(0xFF7A8086);
  return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
}

double _coverChroma(Color color) {
  final maxC = math.max(color.r, math.max(color.g, color.b));
  final minC = math.min(color.r, math.min(color.g, color.b));
  return maxC - minC;
}

double _coverColorScore(Color color) {
  final chroma = _coverChroma(color);
  final maxC = math.max(color.r, math.max(color.g, color.b));
  final minC = math.min(color.r, math.min(color.g, color.b));
  final light = (maxC + minC) / 2;
  if (light < 0.06 || light > 0.94 || chroma < 0.05) return chroma * 0.15;
  return chroma * (1.0 - (light - 0.45).abs());
}

Color _haloTint(Color base) {
  final hsl = HSLColor.fromColor(base);
  if (hsl.lightness < 0.07 || _coverChroma(base) < 0.06) {
    return const Color(0xFF7A8086);
  }
  return hsl
      .withSaturation((hsl.saturation * 1.06).clamp(0.0, 0.86).toDouble())
      .withLightness((hsl.lightness * 0.5 + 0.34).clamp(0.3, 0.76).toDouble())
      .toColor();
}
