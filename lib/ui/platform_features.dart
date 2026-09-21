import 'package:flutter/foundation.dart';

/// Features that shipped on Windows first; also on Android for device testing.
bool get pcParityEnabled =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.android);

/// Keyboard shortcuts — desktop only.
bool get desktopHotkeysEnabled =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
