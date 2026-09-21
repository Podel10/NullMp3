import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'platform_features.dart';
import '../state/settings.dart';

/// UI zoom: Ctrl+/Ctrl−/Ctrl+0 on desktop; Zoom settings on Windows and Android.
class UiZoom extends StatefulWidget {
  const UiZoom({super.key, required this.child});

  final Widget child;

  static bool get enabled => pcParityEnabled;

  @override
  State<UiZoom> createState() => _UiZoomState();
}

class _UiZoomState extends State<UiZoom> {
  @override
  void initState() {
    super.initState();
    if (UiZoom.enabled) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (UiZoom.enabled) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;

    final settings = context.read<SettingsController>();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      settings.zoomIn();
      return true;
    }
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      settings.zoomOut();
      return true;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      settings.resetUiScale();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!UiZoom.enabled) return widget.child;

    final scale = context.watch<SettingsController>().uiScale;
    if ((scale - 1.0).abs() < 0.001) return widget.child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;
        if (!viewW.isFinite || !viewH.isFinite || viewW <= 0 || viewH <= 0) {
          return widget.child;
        }
        final logical = Size(viewW / scale, viewH / scale);
        final mq = MediaQuery.of(context);
        // OverflowBox lets the logical layout be larger/smaller than the
        // window; Transform then scales it so the painted UI always fills.
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: logical.width,
            maxWidth: logical.width,
            minHeight: logical.height,
            maxHeight: logical.height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: MediaQuery(
                data: mq.copyWith(size: logical),
                child: SizedBox(
                  width: logical.width,
                  height: logical.height,
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
