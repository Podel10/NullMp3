import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/cover_image.dart';
import '../l10n/strings.dart';

Future<Uint8List?> showCoverCrop(BuildContext context, Uint8List bytes) {
  if (isAnimatedCover(bytes)) return Future.value(bytes);
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => CoverCropScreen(bytes: bytes)),
  );
}

class CoverCropScreen extends StatefulWidget {
  const CoverCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  CoverCropSource? _source;
  Rect? _crop;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final source = await inspectCoverForCrop(widget.bytes);
    if (!mounted) return;
    if (source == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _source = source;
      _crop = source.suggested;
    });
  }

  Future<void> _save() async {
    final crop = _crop;
    if (crop == null || _saving) return;
    setState(() => _saving = true);
    final cut = await cropCoverSquare(widget.bytes, crop);
    if (!mounted) return;
    if (cut == null || cut.isEmpty) {
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }
    Navigator.pop(context, cut);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final source = _source;
    final crop = _crop;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.cropCover),
        actions: [
          TextButton(
            onPressed: crop == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(s.save),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: source == null || crop == null
                ? Center(
                    child: _failed
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(s.coverSearchApplyFailed, textAlign: TextAlign.center),
                          )
                        : const CircularProgressIndicator(),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _CoverCropStage(
                      bytes: widget.bytes,
                      imageSize: source.size,
                      crop: crop,
                      onChanged: (next) => setState(() => _crop = next),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                s.cropCoverHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CropDrag { none, move, draw, nw, ne, sw, se }

class _CoverCropStage extends StatefulWidget {
  const _CoverCropStage({
    required this.bytes,
    required this.imageSize,
    required this.crop,
    required this.onChanged,
  });

  final Uint8List bytes;
  final Size imageSize;
  final Rect crop;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CoverCropStage> createState() => _CoverCropStageState();
}

class _CoverCropStageState extends State<_CoverCropStage> {
  _CropDrag _drag = _CropDrag.none;
  Offset? _drawOrigin;
  Rect? _moveStart;
  Offset? _movePoint;

  double get _minSide => math.min(32, math.min(widget.imageSize.width, widget.imageSize.height));

  Rect _fitted(Size box) {
    final image = widget.imageSize;
    if (box.width <= 0 || box.height <= 0 || image.width <= 0 || image.height <= 0) {
      return Rect.zero;
    }
    final scale = math.min(box.width / image.width, box.height / image.height);
    final width = image.width * scale;
    final height = image.height * scale;
    return Rect.fromLTWH((box.width - width) / 2, (box.height - height) / 2, width, height);
  }

  Offset _toImage(Offset local, Rect fitted) {
    final x = ((local.dx - fitted.left) / fitted.width) * widget.imageSize.width;
    final y = ((local.dy - fitted.top) / fitted.height) * widget.imageSize.height;
    return Offset(
      x.clamp(0, widget.imageSize.width).toDouble(),
      y.clamp(0, widget.imageSize.height).toDouble(),
    );
  }

  Rect _clamp(double left, double top, double side) {
    final maxSide = math.min(widget.imageSize.width, widget.imageSize.height);
    side = side.clamp(_minSide, maxSide).toDouble();
    left = left.clamp(0, widget.imageSize.width - side).toDouble();
    top = top.clamp(0, widget.imageSize.height - side).toDouble();
    return Rect.fromLTWH(left, top, side, side);
  }

  _CropDrag _hit(Offset local, Rect fitted) {
    final crop = _mapRect(widget.crop, fitted);
    const slop = 22.0;
    bool near(Offset point) => (local - point).distance <= slop;
    if (near(crop.topLeft)) return _CropDrag.nw;
    if (near(crop.topRight)) return _CropDrag.ne;
    if (near(crop.bottomLeft)) return _CropDrag.sw;
    if (near(crop.bottomRight)) return _CropDrag.se;
    if (crop.inflate(8).contains(local)) return _CropDrag.move;
    return _CropDrag.draw;
  }

  Rect _mapRect(Rect crop, Rect fitted) {
    final sx = fitted.width / widget.imageSize.width;
    final sy = fitted.height / widget.imageSize.height;
    return Rect.fromLTWH(
      fitted.left + crop.left * sx,
      fitted.top + crop.top * sy,
      crop.width * sx,
      crop.height * sy,
    );
  }

  void _resize(Offset imagePoint, _CropDrag corner) {
    final crop = widget.crop;
    final fixed = switch (corner) {
      _CropDrag.nw => crop.bottomRight,
      _CropDrag.ne => Offset(crop.left, crop.bottom),
      _CropDrag.sw => Offset(crop.right, crop.top),
      _CropDrag.se => crop.topLeft,
      _ => crop.topLeft,
    };
    var side = math.max((imagePoint.dx - fixed.dx).abs(), (imagePoint.dy - fixed.dy).abs());
    var left = imagePoint.dx < fixed.dx ? fixed.dx - side : fixed.dx;
    var top = imagePoint.dy < fixed.dy ? fixed.dy - side : fixed.dy;
    widget.onChanged(_clamp(left, top, side));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final fitted = _fitted(box);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            final local = details.localPosition;
            final kind = _hit(local, fitted);
            _drag = kind;
            final imagePoint = _toImage(local, fitted);
            if (kind == _CropDrag.move) {
              _moveStart = widget.crop;
              _movePoint = imagePoint;
            } else if (kind == _CropDrag.draw) {
              _drawOrigin = imagePoint;
              widget.onChanged(_clamp(imagePoint.dx, imagePoint.dy, _minSide));
            }
          },
          onPanUpdate: (details) {
            final imagePoint = _toImage(details.localPosition, fitted);
            switch (_drag) {
              case _CropDrag.move:
                final start = _moveStart;
                final origin = _movePoint;
                if (start == null || origin == null) return;
                widget.onChanged(
                  _clamp(
                    start.left + (imagePoint.dx - origin.dx),
                    start.top + (imagePoint.dy - origin.dy),
                    start.width,
                  ),
                );
              case _CropDrag.draw:
                final origin = _drawOrigin;
                if (origin == null) return;
                final dx = imagePoint.dx - origin.dx;
                final dy = imagePoint.dy - origin.dy;
                final side = math.max(dx.abs(), dy.abs());
                widget.onChanged(
                  _clamp(
                    dx >= 0 ? origin.dx : origin.dx - side,
                    dy >= 0 ? origin.dy : origin.dy - side,
                    side,
                  ),
                );
              case _CropDrag.nw:
              case _CropDrag.ne:
              case _CropDrag.sw:
              case _CropDrag.se:
                _resize(imagePoint, _drag);
              case _CropDrag.none:
                break;
            }
          },
          onPanEnd: (_) {
            _drag = _CropDrag.none;
            _drawOrigin = null;
            _moveStart = null;
            _movePoint = null;
          },
          onPanCancel: () {
            _drag = _CropDrag.none;
            _drawOrigin = null;
            _moveStart = null;
            _movePoint = null;
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fromRect(
                rect: fitted,
                child: Image.memory(
                  widget.bytes,
                  key: ValueKey<int>(identityHashCode(widget.bytes)),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              CustomPaint(
                painter: _CropOverlayPainter(
                  fitted: fitted,
                  crop: _mapRect(widget.crop, fitted),
                  accent: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.fitted,
    required this.crop,
    required this.accent,
  });

  final Rect fitted;
  final Rect crop;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (fitted.isEmpty || crop.isEmpty) return;
    final dim = Path()
      ..addRect(fitted)
      ..addRect(crop)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.55));
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(crop, border);
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(crop.left + crop.width / 3, crop.top), Offset(crop.left + crop.width / 3, crop.bottom), grid);
    canvas.drawLine(Offset(crop.left + crop.width * 2 / 3, crop.top), Offset(crop.left + crop.width * 2 / 3, crop.bottom), grid);
    canvas.drawLine(Offset(crop.left, crop.top + crop.height / 3), Offset(crop.right, crop.top + crop.height / 3), grid);
    canvas.drawLine(Offset(crop.left, crop.top + crop.height * 2 / 3), Offset(crop.right, crop.top + crop.height * 2 / 3), grid);
    final handle = Paint()..color = accent;
    const r = 7.0;
    for (final point in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
      canvas.drawCircle(point, r, handle);
      canvas.drawCircle(point, r, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.fitted != fitted || oldDelegate.crop != crop || oldDelegate.accent != accent;
  }
}
