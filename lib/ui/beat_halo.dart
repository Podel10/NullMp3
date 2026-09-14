import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class BeatHalo extends StatefulWidget {
  const BeatHalo({
    super.key,
    required this.child,
    required this.enabled,
    required this.playing,
    required this.circle,
    required this.color,
    this.sessionId,
    this.sessionIds,
  });

  final Widget child;
  final bool enabled;
  final bool playing;
  final bool circle;
  final Color color;
  final int? sessionId;
  final Stream<int?>? sessionIds;

  @override
  State<BeatHalo> createState() => _BeatHaloState();
}

class _BeatHaloState extends State<BeatHalo> with SingleTickerProviderStateMixin {
  static const _methods = MethodChannel('com.nullmp3.nullmp3/halo');
  static const _events = EventChannel('com.nullmp3.nullmp3/haloEvents');
  static const _pad = 48.0;

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
  bool _live = false;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _ticker = createTicker(_onTick)..start();
    _sessionSub = widget.sessionIds?.listen(_onSession);
    _syncCapture();
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
  }

  @override
  void dispose() {
    unawaited(_stopCapture());
    _sub?.cancel();
    _sessionSub?.cancel();
    _ticker.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -_pad,
          top: -_pad,
          right: -_pad,
          bottom: -_pad,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HaloPainter(
                peaks: List<double>.from(_peaks),
                energy: _energy,
                bass: _bass,
                pulse: _pulse,
                circle: widget.circle,
                color: widget.color,
                playing: widget.playing,
                pad: _pad,
              ),
            ),
          ),
        ),
        widget.child,
        IgnorePointer(
          child: CustomPaint(
            painter: _EdgeBlendPainter(
              circle: widget.circle,
              color: widget.color,
              bass: _bass,
              pulse: _pulse,
              playing: widget.playing,
            ),
          ),
        ),
      ],
    );
  }
}

class _EdgeBlendPainter extends CustomPainter {
  _EdgeBlendPainter({
    required this.circle,
    required this.color,
    required this.bass,
    required this.pulse,
    required this.playing,
  });

  final bool circle;
  final Color color;
  final double bass;
  final double pulse;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final drive = (0.2 + 0.5 * bass + 0.55 * pulse).clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0x00000000),
          const Color(0x00000000),
          color.withValues(alpha: (playing ? 0.14 : 0.04) + drive * 0.16),
          color.withValues(alpha: (playing ? 0.4 : 0.08) + drive * 0.2),
          const Color(0x00000000),
        ],
        stops: const [0.0, 0.7, 0.84, 0.94, 1.0],
      ).createShader(rect);
    if (circle) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeBlendPainter old) {
    return old.color != color ||
        old.circle != circle ||
        old.bass != bass ||
        old.pulse != pulse ||
        old.playing != playing;
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
    required this.playing,
    required this.pad,
  });

  final List<double> peaks;
  final double energy;
  final double bass;
  final double pulse;
  final bool circle;
  final Color color;
  final bool playing;
  final double pad;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final bounds = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);
    if (bounds.width <= 4 || bounds.height <= 4) return;

    final hole = _outline(bounds, -32);
    final smooth = _smooth(peaks);
    final outer = _plasmaOutline(bounds, smooth);
    final band = Path.combine(PathOperation.difference, outer, hole);

    canvas.save();
    final ring = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      hole,
    );
    canvas.clipPath(ring);

    final drive = (0.2 + 0.5 * bass + 0.55 * pulse).clamp(0.0, 1.0);
    final bloom = playing ? 0.1 + drive * 0.42 : 0.04;
    canvas.drawPath(
      band,
      Paint()
        ..color = color.withValues(alpha: bloom)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
    canvas.drawPath(
      band,
      Paint()
        ..color = color.withValues(alpha: playing ? 0.14 + drive * 0.5 : 0.06)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRect(
      bounds.inflate(pad),
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: (playing ? 0.5 : 0.12) * drive),
            color.withValues(alpha: (playing ? 0.28 : 0.08) * drive),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.7, 0.86, 0.94, 1.0],
        ).createShader(bounds),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..color = color.withValues(alpha: playing ? 0.28 + drive * 0.55 : 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 + drive * 3.6
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
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
        old.peaks != peaks;
  }
}

class _Edge {
  const _Edge(this.point, this.normal);
  final Offset point;
  final Offset normal;
}
