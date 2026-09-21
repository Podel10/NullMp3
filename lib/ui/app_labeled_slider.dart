import 'package:flutter/material.dart';

/// Discrete setting slider with an in-tree value chip above the thumb.
/// Avoids Material's Overlay value indicator, which breaks under UI zoom on Windows.
class AppLabeledSlider extends StatefulWidget {
  const AppLabeledSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.labelOf,
    required this.onChanged,
    this.divisions,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double value) labelOf;
  final ValueChanged<double> onChanged;

  @override
  State<AppLabeledSlider> createState() => _AppLabeledSliderState();
}

class _AppLabeledSliderState extends State<AppLabeledSlider> {
  bool _dragging = false;

  double get _t {
    final span = widget.max - widget.min;
    if (span <= 0) return 0;
    return ((widget.value - widget.min) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final onAccent = accent.computeLuminance() > 0.55 ? Colors.black : Colors.white;
    final showChip = _dragging || widget.value > widget.min;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const chipH = 28.0;
          const gap = 6.0;
          const thumbR = 8.0;
          final trackW = constraints.maxWidth;
          final thumbCenter = thumbR + _t * (trackW - thumbR * 2);
          final label = widget.labelOf(widget.value);
          final chipW = (label.length * 9.0 + 20).clamp(36.0, 72.0);
          final chipLeft = (thumbCenter - chipW / 2).clamp(0.0, trackW - chipW);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: chipH + gap,
                child: showChip
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: chipLeft,
                            top: 0,
                            child: Column(
                              children: [
                                Container(
                                  width: chipW,
                                  height: chipH - 6,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: onAccent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                CustomPaint(
                                  size: const Size(12, 6),
                                  painter: _CaretPainter(accent),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  showValueIndicator: ShowValueIndicator.never,
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: thumbR),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTickMarkColor: onAccent.withValues(alpha: 0.35),
                  inactiveTickMarkColor: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                ),
                child: Slider(
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  value: widget.value.clamp(widget.min, widget.max),
                  onChangeStart: (_) => setState(() => _dragging = true),
                  onChangeEnd: (_) => setState(() => _dragging = false),
                  onChanged: widget.onChanged,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CaretPainter oldDelegate) => oldDelegate.color != color;
}
