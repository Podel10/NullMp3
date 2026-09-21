import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/player.dart';
import '../state/settings.dart';
import 'platform_features.dart';

/// Windows media shortcuts: Space, arrows, M, and hardware media keys.
class DesktopHotkeys extends StatefulWidget {
  const DesktopHotkeys({super.key, required this.child});

  final Widget child;

  static bool get enabled => desktopHotkeysEnabled;

  @override
  State<DesktopHotkeys> createState() => _DesktopHotkeysState();
}

class _DesktopHotkeysState extends State<DesktopHotkeys> {
  double _preMuteVolume = 1;

  @override
  void initState() {
    super.initState();
    if (DesktopHotkeys.enabled) {
      HardwareKeyboard.instance.addHandler(_onKey);
    }
  }

  @override
  void dispose() {
    if (DesktopHotkeys.enabled) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  bool get _typingInField {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus.context == null) return false;
    return focus.context!.findAncestorWidgetOfExactType<EditableText>() != null ||
        focus.context!.widget is EditableText;
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || !DesktopHotkeys.enabled) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_typingInField) return false;
    // Let Ctrl+/−/0 stay with zoom.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    final player = context.read<PlayerController>();
    final settings = context.read<SettingsController>();
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyRepeatEvent) return true;
      player.playPause();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (event is KeyRepeatEvent) return true;
      player.previous();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaTrackNext) {
      if (event is KeyRepeatEvent) return true;
      player.next();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.audioVolumeUp) {
      player.setVolume((settings.volume + 0.05).clamp(0.0, 1.0));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.audioVolumeDown) {
      player.setVolume((settings.volume - 0.05).clamp(0.0, 1.0));
      return true;
    }
    if (key == LogicalKeyboardKey.keyM || key == LogicalKeyboardKey.audioVolumeMute) {
      if (event is KeyRepeatEvent) return true;
      if (settings.volume > 0.001) {
        _preMuteVolume = settings.volume;
        player.setVolume(0);
      } else {
        player.setVolume(_preMuteVolume <= 0.001 ? 1.0 : _preMuteVolume);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      if (event is KeyRepeatEvent) return true;
      if (!player.playing) player.playPause();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      if (event is KeyRepeatEvent) return true;
      if (player.playing) player.playPause();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
