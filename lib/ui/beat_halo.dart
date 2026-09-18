import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/artwork.dart';
import '../data/cover_rim.dart';

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

class _BeatHaloState extends State<BeatHalo>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  int _syncGen = 0;
  int _rimGen = 0;
  int _artGen = -1;
  bool _live = false;
  bool _backgrounded = false;
  DateTime? _lastDataAt;
  DateTime? _restartAt;
  List<Color> _rim = const [];
  CoverRimSequence _rimLoop = CoverRimSequence.empty;
  bool _rimLive = false;
  bool _rimFromCover = false;
  int? _coverFrame;
  Duration _rimFrozen = Duration.zero;
  Stopwatch? _rimClock;
  StreamSubscription<CoverRimLiveFrame>? _rimLiveSub;

  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionId = widget.sessionId;
    _ticker = createTicker(_onTick)..start();
    _sessionSub = widget.sessionIds?.listen(_onSession);
    ArtworkStore.instance.addListener(_onArtwork);
    _rimLiveSub = CoverRimLive.instance.stream.listen(_onLiveRim);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _sub = _events.receiveBroadcastStream().listen(_onData, onError: (_) {
        _live = false;
        if (widget.playing && widget.enabled) _scheduleCapture();
      });
    }
    _scheduleCapture();
    unawaited(_loadRim());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` also fires for the mic privacy chip and focus flickers.
    // Treating that as background left the halo paused with no resumed event.
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      _live = false;
      if (widget.playing && widget.enabled) _scheduleCapture(force: true);
      return;
    }
    if (state != AppLifecycleState.paused && state != AppLifecycleState.hidden) {
      return;
    }
    _backgrounded = true;
    _startTimer?.cancel();
    _live = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_methods.invokeMethod<void>('pause'));
    }
  }

  @override
  void didUpdateWidget(covariant BeatHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionIds != widget.sessionIds) {
      _sessionSub?.cancel();
      _sessionSub = widget.sessionIds?.listen(_onSession);
    }
    if (widget.sessionId != oldWidget.sessionId &&
        widget.sessionId != null &&
        widget.sessionId! > 0 &&
        widget.sessionId != _sessionId) {
      _sessionId = widget.sessionId;
      _live = false;
      if (widget.playing && widget.enabled) _scheduleCapture();
    }
    if (oldWidget.enabled != widget.enabled || oldWidget.playing != widget.playing) {
      if (!widget.enabled || !widget.playing) {
        _live = false;
      }
      _scheduleCapture();
    }
    if (oldWidget.playing != widget.playing) _syncRimClock();
    if (oldWidget.artworkPath != widget.artworkPath) {
      _coverFrame = null;
      _rimFromCover = false;
    }
    if (oldWidget.artworkPath != widget.artworkPath ||
        oldWidget.circle != widget.circle ||
        oldWidget.enabled != widget.enabled) {
      unawaited(_loadRim());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startTimer?.cancel();
    ArtworkStore.instance.removeListener(_onArtwork);
    _sub?.cancel();
    _sessionSub?.cancel();
    _rimLiveSub?.cancel();
    _rimClock?.stop();
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
      _rimLoop = CoverRimSequence.empty;
      _rimLive = false;
      _rimFromCover = false;
      _coverFrame = null;
      _resetRimClock();
      if (_rim.isNotEmpty && mounted) setState(() => _rim = const []);
      return;
    }
    _artGen = ArtworkStore.instance.generationOf(path);
    final bytes = await ArtworkStore.instance.get(path);
    if (!mounted || gen != _rimGen) return;
    final sequence = await sampleCoverRimSequence(bytes, circle: widget.circle);
    if (!mounted || gen != _rimGen) return;
    _rimLoop = sequence;
    _rimLive = false;
    _rimFromCover = false;
    _resetRimClock();
    setState(() => _rim = sequence.first);
    if (_coverFrame != null) _applyCoverFrame(_coverFrame!);
    _syncRimClock();
  }

  void _onCoverMotion(CoverMotionNotification note) {
    if (!widget.enabled) return;
    _coverFrame = note.index;
    _rimFromCover = true;
    _syncRimClock();
    _applyCoverFrame(note.index);
  }

  void _applyCoverFrame(int index) {
    final frames = _rimLoop.frames;
    if (frames.isEmpty) return;
    final colors = frames[index % frames.length].colors;
    if (sameRim(_rim, colors)) return;
    setState(() => _rim = colors);
  }

  void _onLiveRim(CoverRimLiveFrame frame) {
    if (!widget.enabled) return;
    if (frame.path != widget.artworkPath) return;
    if (sameRim(_rim, frame.colors)) return;
    _rimLive = true;
    setState(() => _rim = frame.colors);
  }

  Duration get _rimElapsed => _rimFrozen + (_rimClock?.elapsed ?? Duration.zero);

  void _resetRimClock() {
    _rimClock?.stop();
    _rimClock = null;
    _rimFrozen = Duration.zero;
  }

  void _syncRimClock() {
    final run = widget.enabled && widget.playing && _rimLoop.isAnimated && !_rimLive && !_rimFromCover;
    if (run) {
      _rimClock ??= Stopwatch()..start();
      return;
    }
    final clock = _rimClock;
    if (clock == null) return;
    _rimFrozen += clock.elapsed;
    clock.stop();
    _rimClock = null;
  }

  void _onSession(int? id) {
    if (id == null || id <= 0) return;
    if (_sessionId == id) return;
    _sessionId = id;
    _live = false;
    if (widget.playing && widget.enabled) _scheduleCapture();
  }

  void _scheduleCapture({bool force = false}) {
    _startTimer?.cancel();
    if (_backgrounded || !widget.enabled || !widget.playing) {
      _live = false;
      return;
    }
    if (!force && _live) return;
    _startTimer = Timer(Duration(milliseconds: force ? 80 : 120), () {
      if (!mounted || _backgrounded || !widget.playing || !widget.enabled) return;
      if (!force && _live) return;
      unawaited(_syncCapture(force: force));
    });
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    _maybeRestartCapture();
    _syncRimClock();
    var rimChanged = false;
    if (_rimLoop.isAnimated && !_rimLive && !_rimFromCover) {
      final next = _rimLoop.at(_rimElapsed);
      if (!sameRim(next, _rim)) {
        _rim = next;
        rimChanged = true;
      }
    }
    final decayPulse = _pulse > 0.002;
    final idle = !widget.playing && (_energy > 0.002 || _bass > 0.002);
    if (!rimChanged && !decayPulse && !idle) return;
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

  void _maybeRestartCapture() {
    if (_backgrounded) return;
    if (!widget.playing || !widget.enabled) return;
    if (_startTimer?.isActive == true) return;
    final now = DateTime.now();
    if (_restartAt == null) return;
    if (now.difference(_restartAt!) < const Duration(milliseconds: 1200)) return;
    final last = _lastDataAt;
    final fresh = last != null && now.difference(last) < const Duration(seconds: 2);
    if (fresh) return;
    _live = false;
    final hard = last == null
        ? now.difference(_restartAt!) > const Duration(seconds: 3)
        : now.difference(last) > const Duration(seconds: 4);
    _scheduleCapture(force: hard);
  }

  Future<void> _syncCapture({bool force = false}) async {
    final gen = ++_syncGen;
    if (kIsWeb || _backgrounded || !widget.enabled || !widget.playing) {
      return;
    }
    if (!force && _live) return;
    final id = _sessionId ?? widget.sessionId;
    if (id == null || id <= 0) return;
    final allowed = await _ensureMic();
    if (!mounted || gen != _syncGen) return;
    if (!allowed) return;
    try {
      final ok = await _methods.invokeMethod<bool>('start', {
            'sessionId': id,
            'force': force,
          }) ??
          false;
      if (!mounted || gen != _syncGen) return;
      _restartAt = DateTime.now();
      if (!ok) {
        _live = false;
      } else if (force) {
        _live = false;
        _lastDataAt = null;
      }
    } catch (_) {
      _live = false;
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

  void _onData(dynamic raw) {
    if (!widget.playing) return;
    if (raw is! Map) return;
    final peaks = raw['peaks'];
    if (peaks is! List || peaks.isEmpty) return;
    _lastDataAt = DateTime.now();
    _live = true;
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
        final t = target > _peaks[i] ? 0.68 : 0.26;
        _peaks[i] = lerpDouble(_peaks[i], target, t)!;
      }
      _energy = _follow(_energy, _gain(energy, 0.72), up: 0.6, down: 0.16);
      _bass = _follow(_bass, _gain(bass, 0.5), up: 0.72, down: 0.12);
      if (beat) {
        _pulse = math.max(_pulse, 0.62 + 0.38 * strength);
      } else if (strength > _pulse) {
        _pulse = lerpDouble(_pulse, strength, 0.3)!;
      }
    });
  }

  double _follow(double current, double next, {double up = 0.7, double down = 0.22}) {
    return lerpDouble(current, next, next > current ? up : down)!;
  }

  /// Lifts quiet and mid levels so the halo reacts to more than just peaks.
  double _gain(double value, double curve) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return math.pow(clamped, curve).toDouble();
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
      child: NotificationListener<CoverMotionNotification>(
        onNotification: (note) {
          _onCoverMotion(note);
          return false;
        },
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
    final drive = (0.1 + 0.46 * bass + 0.36 * pulse).clamp(0.0, 1.0).toDouble();
    final rect = Offset.zero & size;
    final a0 = ((playing ? 0.08 : 0.03) + drive * 0.1).clamp(0.0, 1.0).toDouble();
    final a1 = ((playing ? 0.22 : 0.05) + drive * 0.14).clamp(0.0, 1.0).toDouble();
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
    if (cover.width <= 4 || cover.height <= 4) return;
    final bounds = cover;
    final screen = Offset.zero & size;
    final drive = (0.1 + 0.46 * bass + 0.36 * pulse).clamp(0.0, 1.0).toDouble();
    final expand = 9 + bass * 16 + pulse * 10 + energy * 5;
    final hole = _outline(bounds, -1);
    final smooth = _smooth(peaks);
    final outer = _haloRing(bounds, expand, smooth);
    final band = Path.combine(PathOperation.difference, outer, _outline(bounds, 1.5));
    final wash = _rimAverage(rim, color);
    final sweepRect = bounds.inflate(expand + 18);

    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, Path()..addRect(screen), hole),
    );

    canvas.drawPath(
      _outline(bounds, expand * 1.05),
      Paint()
        ..color = wash.withValues(alpha: (playing ? 0.07 : 0.025) + drive * 0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      band,
      _haloPaint(sweepRect, playing ? 0.08 + drive * 0.18 : 0.04, const MaskFilter.blur(BlurStyle.normal, 12)),
    );
    canvas.drawPath(
      band,
      _haloPaint(sweepRect, playing ? 0.16 + drive * 0.26 : 0.06, const MaskFilter.blur(BlurStyle.normal, 5.5)),
    );
    canvas.drawPath(
      outer,
      _haloPaint(
        sweepRect,
        playing ? 0.3 + drive * 0.34 : 0.1,
        const MaskFilter.blur(BlurStyle.normal, 2.2),
        style: PaintingStyle.stroke,
        strokeWidth: 1.5 + drive * 1.6,
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
    if (raw.isEmpty) return raw;
    final n = raw.length;
    var cur = List<double>.from(raw);
    for (var pass = 0; pass < 4; pass++) {
      final next = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        next[i] = (cur[(i - 2 + n) % n] + cur[(i - 1 + n) % n] * 2 + cur[i] * 3 + cur[(i + 1) % n] * 2 + cur[(i + 2) % n]) / 9;
      }
      cur = next;
    }
    return cur;
  }

  Path _haloRing(Rect bounds, double extra, List<double> smooth) {
    final n = 80;
    final ripple = 2.0 + energy * 3.2 + pulse * 2.4;
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final sample = _sample(bounds, t, extra: extra);
      final band = smooth.isEmpty ? 0.45 : _sampleBand(smooth, t);
      final neighbor = smooth.isEmpty ? 0.45 : _sampleBand(smooth, t + 0.1);
      final local = 0.55 + 0.45 * (0.72 * band + 0.28 * neighbor);
      points.add(sample.point + sample.normal * (ripple * local));
    }
    return _closedSpline(points);
  }

  double _sampleBand(List<double> smooth, double t) {
    final n = smooth.length;
    final wrapped = t - t.floorToDouble();
    // Mirror left/right and put bass at the bottom so kicks don't pile on the right.
    final side = wrapped <= 0.5 ? wrapped : 1 - wrapped;
    final x = ((1 - side * 2).clamp(0.0, 0.999).toDouble()) * n;
    final i = x.floor();
    final f = x - i;
    return lerpDouble(smooth[i % n], smooth[(i + 1) % n], f)!;
  }

  double _cornerRadius(Rect bounds, double extra) {
    final box = bounds.inflate(extra);
    return (10.0 + extra.abs() * 0.78).clamp(8.0, box.shortestSide / 2).toDouble();
  }

  Path _outline(Rect bounds, double extra) {
    if (circle) {
      return Path()
        ..addOval(Rect.fromCircle(center: bounds.center, radius: bounds.shortestSide / 2 + extra));
    }
    final box = bounds.inflate(extra);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(box, Radius.circular(_cornerRadius(bounds, extra))));
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

  _Edge _sample(Rect bounds, double t, {double extra = 0}) {
    if (circle) {
      final a = t * math.pi * 2 - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      return _Edge(bounds.center + dir * (bounds.shortestSide / 2 + extra), dir);
    }
    final box = bounds.inflate(extra);
    final r = _cornerRadius(bounds, extra);
    final w = math.max(0.0, box.width - 2 * r);
    final h = math.max(0.0, box.height - 2 * r);
    final total = 2 * w + 2 * h + 2 * math.pi * r;
    var d = (t % 1) * total;
    if (d <= w) return _Edge(Offset(box.left + r + d, box.top), const Offset(0, -1));
    d -= w;
    if (d <= math.pi / 2 * r) {
      final a = -math.pi / 2 + d / r;
      final n = Offset(math.cos(a), math.sin(a));
      return _Edge(Offset(box.right - r, box.top + r) + n * r, n);
    }
    d -= math.pi / 2 * r;
    if (d <= h) return _Edge(Offset(box.right, box.top + r + d), const Offset(1, 0));
    d -= h;
    if (d <= math.pi / 2 * r) {
      final a = d / r;
      final n = Offset(math.cos(a), math.sin(a));
      return _Edge(Offset(box.right - r, box.bottom - r) + n * r, n);
    }
    d -= math.pi / 2 * r;
    if (d <= w) return _Edge(Offset(box.right - r - d, box.bottom), const Offset(0, 1));
    d -= w;
    if (d <= math.pi / 2 * r) {
      final a = math.pi / 2 + d / r;
      final n = Offset(math.cos(a), math.sin(a));
      return _Edge(Offset(box.left + r, box.bottom - r) + n * r, n);
    }
    d -= math.pi / 2 * r;
    if (d <= h) return _Edge(Offset(box.left, box.bottom - r - d), const Offset(-1, 0));
    d -= h;
    final a = math.pi + d / r;
    final n = Offset(math.cos(a), math.sin(a));
    return _Edge(Offset(box.left + r, box.top + r) + n * r, n);
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
