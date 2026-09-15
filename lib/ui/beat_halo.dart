import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/artwork.dart';

class BeatHalo extends StatefulWidget {
  const BeatHalo({
    super.key,
    required this.child,
    required this.enabled,
    required this.playing,
    required this.circle,
    required this.color,
    this.artworkPath,
    this.sessionId,
    this.sessionIds,
  });

  final Widget child;
  final bool enabled;
  final bool playing;
  final bool circle;
  final Color color;
  final String? artworkPath;
  final int? sessionId;
  final Stream<int?>? sessionIds;

  @override
  State<BeatHalo> createState() => _BeatHaloState();
}

class _BeatHaloState extends State<BeatHalo> with SingleTickerProviderStateMixin {
  static const _methods = MethodChannel('com.nullmp3.nullmp3/halo');
  static const _events = EventChannel('com.nullmp3.nullmp3/haloEvents');
  final GlobalKey _coverKey = GlobalKey();
  Rect _coverRect = Rect.zero;
  late final Ticker _ticker;
  StreamSubscription<dynamic>? _sub;
  StreamSubscription<int?>? _sessionSub;
  final List<double> _peaks = List<double>.filled(32, 0);
  double _energy = 0;
  double _bass = 0;
  double _pulse = 0;
  int? _sessionId;
  int? _listeningSession;
  int _syncGen = 0;
  int _rimGen = 0;
  int _artGen = -1;
  bool _live = false;
  List<Color> _rim = const [];

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _ticker = createTicker(_onTick)..start();
    _sessionSub = widget.sessionIds?.listen(_onSession);
    ArtworkStore.instance.addListener(_onArtwork);
    _syncCapture();
    unawaited(_loadRim());
  }

  @override
  void didUpdateWidget(covariant BeatHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionIds != widget.sessionIds) {
      _sessionSub?.cancel();
      _sessionSub = widget.sessionIds?.listen(_onSession);
    }
    if (widget.sessionId != oldWidget.sessionId && widget.sessionId != _sessionId) {
      _sessionId = widget.sessionId;
    }
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.playing != widget.playing ||
        oldWidget.sessionId != widget.sessionId) {
      _syncCapture();
    }
    if (oldWidget.artworkPath != widget.artworkPath ||
        oldWidget.circle != widget.circle ||
        oldWidget.enabled != widget.enabled) {
      unawaited(_loadRim());
    }
  }

  @override
  void dispose() {
    ArtworkStore.instance.removeListener(_onArtwork);
    unawaited(_stopCapture());
    _sub?.cancel();
    _sessionSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onArtwork() {
    final path = widget.artworkPath;
    if (path == null) return;
    if (ArtworkStore.instance.generationOf(path) != _artGen) {
      unawaited(_loadRim());
    }
  }

  Future<void> _loadRim() async {
    final gen = ++_rimGen;
    final path = widget.artworkPath;
    if (!widget.enabled || path == null || path.isEmpty) {
      _artGen = -1;
      if (_rim.isNotEmpty && mounted) setState(() => _rim = const []);
      return;
    }
    _artGen = ArtworkStore.instance.generationOf(path);
    final bytes = await ArtworkStore.instance.get(path);
    if (!mounted || gen != _rimGen) return;
    final rim = await _sampleCoverRim(bytes, circle: widget.circle);
    if (!mounted || gen != _rimGen) return;
    setState(() => _rim = rim);
  }

  void _onSession(int? id) {
    if (_sessionId == id) return;
    _sessionId = id;
    _syncCapture();
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final decayPulse = _pulse > 0.002;
    final idle = !widget.playing && (_energy > 0.002 || _bass > 0.002);
    if (!decayPulse && !idle) return;
    setState(() {
      if (decayPulse) _pulse *= 0.88;
      if (idle) {
        _energy *= 0.88;
        _bass *= 0.88;
        _pulse *= 0.78;
        for (var i = 0; i < _peaks.length; i++) {
          _peaks[i] *= 0.88;
        }
      }
    });
  }

  Future<void> _syncCapture() async {
    final gen = ++_syncGen;
    if (kIsWeb || !widget.enabled || !widget.playing) {
      await _stopCapture();
      return;
    }
    final id = _sessionId ?? widget.sessionId;
    if (id == null || id <= 0) {
      await _stopCapture();
      return;
    }
    if (_listeningSession == id && _live) return;
    final allowed = await _ensureMic();
    if (!mounted || gen != _syncGen) return;
    if (!allowed) {
      await _stopCapture();
      return;
    }
    _listeningSession = id;
    _sub?.cancel();
    _sub = _events.receiveBroadcastStream().listen(_onData, onError: (_) {
      _live = false;
    });
    try {
      final ok = await _methods.invokeMethod<bool>('start', {'sessionId': id}) ?? false;
      if (!mounted || gen != _syncGen) return;
      _live = ok;
      if (!ok) _listeningSession = null;
    } catch (_) {
      _live = false;
      _listeningSession = null;
    }
  }

  Future<bool> _ensureMic() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      var status = await Permission.microphone.status;
      if (status.isGranted) return true;
      status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopCapture() async {
    _listeningSession = null;
    _live = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _methods.invokeMethod<void>('stop');
    } catch (_) {}
  }

  void _onData(dynamic raw) {
    if (raw is! Map) return;
    final peaks = raw['peaks'];
    if (peaks is! List || peaks.isEmpty) return;
    final next = <double>[
      for (final item in peaks) (item as num).toDouble().clamp(0.0, 1.0),
    ];
    final energy = (raw['energy'] as num?)?.toDouble() ?? 0;
    final bass = (raw['bass'] as num?)?.toDouble() ?? energy;
    final beat = raw['beat'] == true;
    final strength = ((raw['strength'] as num?)?.toDouble() ?? (beat ? 1.0 : 0)).clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() {
      _live = true;
      for (var i = 0; i < _peaks.length; i++) {
        final target = next[i % next.length];
        final t = target > _peaks[i] ? 0.55 : 0.32;
        _peaks[i] = lerpDouble(_peaks[i], target, t)!;
      }
      _energy = _follow(_energy, energy.clamp(0.0, 1.0), up: 0.48, down: 0.2);
      _bass = _follow(_bass, bass.clamp(0.0, 1.0), up: 0.5, down: 0.18);
      if (beat) {
        _pulse = math.max(_pulse, 0.55 + 0.45 * strength);
      } else if (strength > _pulse) {
        _pulse = lerpDouble(_pulse, strength, 0.22)!;
      }
    });
  }

  double _follow(double current, double next, {double up = 0.7, double down = 0.22}) {
    return lerpDouble(current, next, next > current ? up : down)!;
  }

  void _measureCover() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.enabled) return;
      final coverBox = _coverKey.currentContext?.findRenderObject() as RenderBox?;
      final hostBox = context.findRenderObject() as RenderBox?;
      if (coverBox == null || hostBox == null || !coverBox.hasSize || !hostBox.hasSize) return;
      final origin = coverBox.localToGlobal(Offset.zero, ancestor: hostBox);
      final rect = origin & coverBox.size;
      if ((rect.left - _coverRect.left).abs() < 0.5 &&
          (rect.top - _coverRect.top).abs() < 0.5 &&
          (rect.width - _coverRect.width).abs() < 0.5 &&
          (rect.height - _coverRect.height).abs() < 0.5) {
        return;
      }
      setState(() => _coverRect = rect);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    _measureCover();
    return _HaloScope(
      coverKey: _coverKey,
      circle: widget.circle,
      color: widget.color,
      rim: _rim,
      bass: _bass,
      pulse: _pulse,
      playing: widget.playing,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _HaloPainter(
                  peaks: List<double>.from(_peaks),
                  energy: _energy,
                  bass: _bass,
                  pulse: _pulse,
                  circle: widget.circle,
                  color: widget.color,
                  rim: _rim,
                  playing: widget.playing,
                  cover: _coverRect,
                ),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class BeatHaloCover extends StatelessWidget {
  const BeatHaloCover({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _HaloScope.maybeOf(context);
    if (scope == null) return child;
    return KeyedSubtree(
      key: scope.coverKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (scope.circle)
            IgnorePointer(
              child: CustomPaint(
                painter: _EdgeBlendPainter(
                  color: scope.color,
                  rim: scope.rim,
                  bass: scope.bass,
                  pulse: scope.pulse,
                  playing: scope.playing,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HaloScope extends InheritedWidget {
  const _HaloScope({
    required this.coverKey,
    required this.circle,
    required this.color,
    required this.rim,
    required this.bass,
    required this.pulse,
    required this.playing,
    required super.child,
  });

  final GlobalKey coverKey;
  final bool circle;
  final Color color;
  final List<Color> rim;
  final double bass;
  final double pulse;
  final bool playing;

  static _HaloScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_HaloScope>();
  }

  @override
  bool updateShouldNotify(_HaloScope old) {
    return circle != old.circle ||
        color != old.color ||
        bass != old.bass ||
        pulse != old.pulse ||
        playing != old.playing ||
        !listEquals(rim, old.rim);
  }
}

class _EdgeBlendPainter extends CustomPainter {
  _EdgeBlendPainter({
    required this.color,
    required this.rim,
    required this.bass,
    required this.pulse,
    required this.playing,
  });

  final Color color;
  final List<Color> rim;
  final double bass;
  final double pulse;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final drive = (0.2 + 0.5 * bass + 0.55 * pulse).clamp(0.0, 1.0).toDouble();
    final rect = Offset.zero & size;
    final a0 = ((playing ? 0.14 : 0.04) + drive * 0.16).clamp(0.0, 1.0).toDouble();
    final a1 = ((playing ? 0.4 : 0.08) + drive * 0.2).clamp(0.0, 1.0).toDouble();
    final sweep = _rimSweep(rim, rect, 1);
    if (sweep == null) {
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0x00000000),
              const Color(0x00000000),
              color.withValues(alpha: a0),
              color.withValues(alpha: a1),
              const Color(0x00000000),
            ],
            stops: const [0.0, 0.7, 0.84, 0.94, 1.0],
          ).createShader(rect),
      );
      return;
    }
    canvas.saveLayer(rect, Paint());
    canvas.drawOval(rect, Paint()..shader = sweep);
    canvas.drawOval(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          colors: [
            const Color(0x00000000),
            const Color(0x00000000),
            Color.fromRGBO(255, 255, 255, a0),
            Color.fromRGBO(255, 255, 255, a1),
            const Color(0x00000000),
          ],
          stops: const [0.0, 0.7, 0.84, 0.94, 1.0],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EdgeBlendPainter old) {
    return old.color != color ||
        old.bass != bass ||
        old.pulse != pulse ||
        old.playing != playing ||
        !listEquals(old.rim, rim);
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.peaks,
    required this.energy,
    required this.bass,
    required this.pulse,
    required this.circle,
    required this.color,
    required this.rim,
    required this.playing,
    required this.cover,
  });

  final List<double> peaks;
  final double energy;
  final double bass;
  final double pulse;
  final bool circle;
  final Color color;
  final List<Color> rim;
  final bool playing;
  final Rect cover;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty || cover.width <= 4 || cover.height <= 4) return;
    final bounds = cover;
    final screen = Offset.zero & size;
    final hole = _outline(bounds, -8);
    final smooth = _smooth(peaks);
    final outer = _plasmaOutline(bounds, smooth);
    final band = Path.combine(PathOperation.difference, outer, hole);
    final drive = (0.2 + 0.5 * bass + 0.55 * pulse).clamp(0.0, 1.0).toDouble();
    final reach = bounds.shortestSide * (2.05 + drive * 0.65);
    final wash = _rimAverage(rim, color);
    final sweepRect = Rect.fromCircle(center: bounds.center, radius: reach);

    canvas.drawRect(
      screen,
      Paint()
        ..shader = RadialGradient(
          colors: [
            wash.withValues(alpha: (playing ? 0.2 : 0.05) + drive * 0.28),
            wash.withValues(alpha: (playing ? 0.1 : 0.03) + drive * 0.16),
            wash.withValues(alpha: (playing ? 0.04 : 0.01) + drive * 0.06),
            wash.withValues(alpha: 0),
          ],
          stops: const [0.18, 0.42, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: bounds.center, radius: reach)),
    );

    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, Path()..addRect(screen), hole),
    );

    final bloom = playing ? 0.1 + drive * 0.42 : 0.04;
    canvas.drawPath(
      band,
      _haloPaint(sweepRect, bloom, const MaskFilter.blur(BlurStyle.normal, 42)),
    );
    canvas.drawPath(
      band,
      _haloPaint(
        sweepRect,
        playing ? 0.14 + drive * 0.5 : 0.06,
        const MaskFilter.blur(BlurStyle.normal, 18),
      ),
    );
    if (circle) {
      canvas.drawRect(
        screen,
        Paint()
          ..shader = RadialGradient(
            colors: [
              wash.withValues(alpha: 0),
              wash.withValues(alpha: 0),
              wash.withValues(alpha: (playing ? 0.5 : 0.12) * drive),
              wash.withValues(alpha: (playing ? 0.22 : 0.08) * drive),
              wash.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.62, 0.84, 0.94, 1.0],
          ).createShader(bounds.inflate(bounds.shortestSide * 0.22)),
      );
    }
    canvas.drawPath(
      outer,
      _haloPaint(
        sweepRect,
        playing ? 0.28 + drive * 0.55 : 0.1,
        const MaskFilter.blur(BlurStyle.normal, 5),
        style: PaintingStyle.stroke,
        strokeWidth: 2.4 + drive * 3.6,
      ),
    );
    canvas.restore();
  }

  Paint _haloPaint(
    Rect sweepRect,
    double alpha,
    MaskFilter blur, {
    PaintingStyle style = PaintingStyle.fill,
    double strokeWidth = 0,
  }) {
    final paint = Paint()
      ..style = style
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = blur;
    final shader = _rimSweep(rim, sweepRect, alpha);
    if (shader != null) {
      paint.shader = shader;
    } else {
      paint.color = color.withValues(alpha: alpha);
    }
    return paint;
  }

  List<double> _smooth(List<double> raw) {
    final n = raw.length;
    var cur = List<double>.from(raw);
    for (var pass = 0; pass < 2; pass++) {
      final next = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        next[i] = (cur[(i - 1 + n) % n] + cur[i] * 2 + cur[(i + 1) % n]) / 4;
      }
      cur = next;
    }
    return cur;
  }

  Path _plasmaOutline(Rect bounds, List<double> smooth) {
    final n = 72;
    final hit = pulse;
    final amp = 11 + bass * 28 + hit * 24 + energy * 12;
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final sample = _sample(bounds, t);
      final band = _sampleBand(smooth, t);
      final neighbor = _sampleBand(smooth, (t + 0.07) % 1);
      final local = 0.16 + 0.84 * (0.72 * band + 0.28 * neighbor);
      final radius = 5 + amp * local;
      points.add(sample.point + sample.normal * radius);
    }
    return _closedSpline(points);
  }

  double _sampleBand(List<double> smooth, double t) {
    final n = smooth.length;
    final x = t * n;
    final i = x.floor();
    final f = x - i;
    return lerpDouble(smooth[i % n], smooth[(i + 1) % n], f)!;
  }

  Path _outline(Rect bounds, double extra) {
    if (circle) {
      return Path()
        ..addOval(Rect.fromCircle(center: bounds.center, radius: bounds.shortestSide / 2 + extra));
    }
    return Path()
      ..addRRect(RRect.fromRectAndRadius(bounds.inflate(extra), const Radius.circular(10)));
  }

  Path _closedSpline(List<Offset> points) {
    final path = Path();
    if (points.length < 3) return path;
    final n = points.length;
    path.moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < n; i++) {
      final p0 = points[(i - 1 + n) % n];
      final p1 = points[i];
      final p2 = points[(i + 1) % n];
      final p3 = points[(i + 2) % n];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  _Edge _sample(Rect bounds, double t) {
    if (circle) {
      final a = t * math.pi * 2 - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      return _Edge(bounds.center + dir * (bounds.shortestSide / 2), dir);
    }
    final r = 10.0;
    final w = bounds.width - 2 * r;
    final h = bounds.height - 2 * r;
    final total = 2 * w + 2 * h + 2 * math.pi * r;
    var d = (t % 1) * total;
    if (d <= w) return _Edge(Offset(bounds.left + r + d, bounds.top), const Offset(0, -1));
    d -= w;
    if (d <= math.pi / 2 * r) {
      final a = -math.pi / 2 + d / r;
      final n = Offset(math.cos(a), math.sin(a));
      return _Edge(Offset(bounds.right - r, bounds.top + r) + n * r, n);
    }
    d -= math.pi / 2 * r;
    if (d <= h) return _Edge(Offset(bounds.right, bounds.top + r + d), const Offset(1, 0));
    d -= h;
    if (d <= math.pi / 2 * r) {
      final a = d / r;
      final n = Offset(math.cos(a), math.sin(a));
      return _Edge(Offset(bounds.right - r, bounds.bottom - r) + n * r, n);
    }
    d -= math.pi / 2 * r;
    if (d <= w) return _Edge(Offset(bounds.right - r - d, bounds.bottom), const Offset(0, 1));
    d -= w;
    if (d <= math.pi / 2 * r) {
      final a = math.pi / 2 + d / r;
      final n = Offset(math.cos(a), math.sin(a));
      return _Edge(Offset(bounds.left + r, bounds.bottom - r) + n * r, n);
    }
    d -= math.pi / 2 * r;
    if (d <= h) return _Edge(Offset(bounds.left, bounds.bottom - r - d), const Offset(-1, 0));
    d -= h;
    final a = math.pi + d / r;
    final n = Offset(math.cos(a), math.sin(a));
    return _Edge(Offset(bounds.left + r, bounds.top + r) + n * r, n);
  }

  @override
  bool shouldRepaint(covariant _HaloPainter old) {
    return old.energy != energy ||
        old.bass != bass ||
        old.pulse != pulse ||
        old.circle != circle ||
        old.color != color ||
        old.playing != playing ||
        old.peaks != peaks ||
        old.cover != cover ||
        !listEquals(old.rim, rim);
  }
}

class _Edge {
  const _Edge(this.point, this.normal);
  final Offset point;
  final Offset normal;
}

const _rimBands = 16;

/// Reads the colours around the edge of the cover once per artwork, so the
/// halo can be tinted per direction without touching pixels while painting.
Future<List<Color>> _sampleCoverRim(Uint8List? bytes, {required bool circle}) async {
  if (bytes == null || bytes.length < 32) return const [];
  try {
    final codec = await instantiateImageCodec(bytes, targetWidth: 48);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final width = image.width;
      final height = image.height;
      if (width < 8 || height < 8) return const [];
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (data == null) return const [];
      final pixels = data.buffer.asUint8List();
      final rim = <Color>[];
      for (var i = 0; i < _rimBands; i++) {
        final point = _rimPoint(i / _rimBands, width.toDouble(), height.toDouble(), circle);
        rim.add(_rimColorAt(pixels, width, height, point));
      }
      return rim;
    } finally {
      image.dispose();
    }
  } catch (_) {
    return const [];
  }
}

/// Angle `t` runs clockwise from the top, matching [_HaloPainter._sample].
Offset _rimPoint(double t, double width, double height, bool circle) {
  final center = Offset(width / 2, height / 2);
  final angle = t * math.pi * 2 - math.pi / 2;
  final dir = Offset(math.cos(angle), math.sin(angle));
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
  return center + dir * reach * 0.88;
}

Color _rimColorAt(Uint8List rgba, int width, int height, Offset point) {
  var r = 0;
  var g = 0;
  var b = 0;
  var count = 0;
  final cx = point.dx.round();
  final cy = point.dy.round();
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final x = (cx + dx).clamp(0, width - 1);
      final y = (cy + dy).clamp(0, height - 1);
      final i = (y * width + x) * 4;
      if (rgba[i + 3] < 8) continue;
      r += rgba[i];
      g += rgba[i + 1];
      b += rgba[i + 2];
      count++;
    }
  }
  if (count == 0) return const Color(0xFF1C3A48);
  final base = Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation((hsl.saturation * 1.25).clamp(0.0, 0.95).toDouble())
      .withLightness(hsl.lightness.clamp(0.4, 0.74).toDouble())
      .toColor();
}

/// Ring of cover colours as an angular shader, first colour at the top.
Shader? _rimSweep(List<Color> rim, Rect rect, double alpha) {
  if (rim.length < 2 || rect.isEmpty) return null;
  final a = alpha.clamp(0.0, 1.0).toDouble();
  return SweepGradient(
    colors: [
      for (final color in rim) color.withValues(alpha: a),
      rim.first.withValues(alpha: a),
    ],
    transform: const GradientRotation(-math.pi / 2),
  ).createShader(rect);
}

Color _rimAverage(List<Color> rim, Color fallback) {
  if (rim.isEmpty) return fallback;
  var r = 0;
  var g = 0;
  var b = 0;
  for (final color in rim) {
    r += (color.r * 255).round();
    g += (color.g * 255).round();
    b += (color.b * 255).round();
  }
  return Color.fromARGB(255, r ~/ rim.length, g ~/ rim.length, b ~/ rim.length);
}
