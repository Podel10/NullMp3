import 'package:flutter/foundation.dart';

/// Lightweight breadcrumbs for the next play-time crash on device.
/// Shows up in logcat as `I/flutter: NullMP3 ...`.
class CrashLog {
  CrashLog._();

  static String? lastMark;
  static DateTime? lastAt;

  static void mark(String where, [Object? detail]) {
    final text = detail == null ? where : '$where $detail';
    lastMark = text;
    lastAt = DateTime.now();
    // ignore: avoid_print
    print('NullMP3 mark: $text');
  }

  static void installHooks() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      // ignore: avoid_print
      print(
        'NullMP3 FlutterError last=${lastMark ?? '-'} '
        'at=${lastAt?.toIso8601String() ?? '-'} '
        'err=${details.exceptionAsString()}',
      );
      // ignore: avoid_print
      print('NullMP3 FlutterError stack:\n${details.stack}');
      previous?.call(details);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      // ignore: avoid_print
      print(
        'NullMP3 ZoneError last=${lastMark ?? '-'} '
        'at=${lastAt?.toIso8601String() ?? '-'} err=$error',
      );
      // ignore: avoid_print
      print('NullMP3 ZoneError stack:\n$stack');
      return false;
    };
  }
}
