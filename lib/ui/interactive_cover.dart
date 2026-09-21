import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/player.dart';
import '../state/settings.dart';

/// Hold and drag on the cover to change volume.
/// Horizontal mode: drag left/right. Vertical mode: drag up/down.
class InteractiveCover extends StatefulWidget {
  const InteractiveCover({
    super.key,
    required this.child,
    required this.enabled,
    required this.mode,
  });

  final Widget child;
  final bool enabled;
  final InteractiveCoverMode mode;

  @override
  State<InteractiveCover> createState() => _InteractiveCoverState();
}

class _InteractiveCoverState extends State<InteractiveCover> {
  bool _active = false;
  double _volume = 1;
  double _startX = 0;
  double _startY = 0;
  double _startVolume = 1;

  void _setVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    setState(() => _volume = next);
    context.read<PlayerController>().setVolume(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final accent = Theme.of(context).colorScheme.primary;
    final horizontal = widget.mode == InteractiveCoverMode.horizontal;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        final settings = context.read<SettingsController>();
        setState(() {
          _active = true;
          _startX = event.localPosition.dx;
          _startY = event.localPosition.dy;
          _startVolume = settings.volume;
          _volume = settings.volume;
        });
      },
      onPointerMove: (event) {
        if (!_active) return;
        final box = context.findRenderObject() as RenderBox?;
        if (horizontal) {
          final width = (box?.size.width ?? 1).clamp(1.0, double.infinity);
          // Drag right = louder.
          final delta = (event.localPosition.dx - _startX) / width;
          _setVolume(_startVolume + delta);
        } else {
          final height = (box?.size.height ?? 1).clamp(1.0, double.infinity);
          // Drag up = louder.
          final delta = (_startY - event.localPosition.dy) / height;
          _setVolume(_startVolume + delta);
        }
      },
      onPointerUp: (_) => setState(() => _active = false),
      onPointerCancel: (_) => setState(() => _active = false),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_active)
            IgnorePointer(
              child: horizontal
                  ? _HorizontalVolumeBar(volume: _volume, color: accent)
                  : _VerticalVolumePanel(volume: _volume, color: accent),
            ),
        ],
      ),
    );
  }
}

class _HorizontalVolumeBar extends StatelessWidget {
  const _HorizontalVolumeBar({required this.volume, required this.color});

  final double volume;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: Colors.white.withValues(alpha: 0.22)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: volume.clamp(0.0, 1.0),
                      child: ColoredBox(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalVolumePanel extends StatelessWidget {
  const _VerticalVolumePanel({required this.volume, required this.color});

  final double volume;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 56,
        margin: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fill = constraints.maxHeight * volume.clamp(0.0, 1.0);
                    return Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        ColoredBox(
                          color: Colors.white.withValues(alpha: 0.22),
                          child: const SizedBox.expand(),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: ColoredBox(
                            color: color,
                            child: SizedBox(width: double.infinity, height: fill),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Icon(Icons.volume_up_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}
