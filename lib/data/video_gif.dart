import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _filesChannel = MethodChannel('com.nullmp3.nullmp3/files');
const _gifEvents = EventChannel('com.nullmp3.nullmp3/gifEvents');

class VideoClipInfo {
  const VideoClipInfo({
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final int durationMs;
  final int width;
  final int height;

  bool get hasSize => width > 0 && height > 0;
}

class GifResult {
  const GifResult({
    required this.path,
    required this.file,
    required this.frames,
    required this.sizeBytes,
  });

  /// Where the GIF landed in the gallery. Can be a content uri.
  final String path;

  /// A readable copy in the cache, used for the preview and for sharing.
  final String file;
  final int frames;
  final int sizeBytes;
}

/// One step of the native conversion.
class GifStep {
  const GifStep({required this.stage, required this.done, required this.total});

  /// `scan` while frames are read, `encode` while the GIF is written.
  final String stage;
  final int done;
  final int total;

  double? get value => total > 0 ? (done / total).clamp(0.0, 1.0) : null;
}

bool get videoGifSupported => !kIsWeb && Platform.isAndroid;

Stream<GifStep> watchGifProgress() {
  return _gifEvents.receiveBroadcastStream().map((event) {
    final data = event is Map ? event : const <Object?, Object?>{};
    return GifStep(
      stage: data['stage']?.toString() ?? 'scan',
      done: (data['done'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  });
}

Future<VideoClipInfo> readVideoInfo(String path) async {
  if (videoGifSupported) {
    final data = await _filesChannel.invokeMapMethod<String, dynamic>('videoInfo', {
      'path': path,
    }).timeout(const Duration(seconds: 20));
    if (data != null) {
      return VideoClipInfo(
        durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
        width: (data['width'] as num?)?.toInt() ?? 0,
        height: (data['height'] as num?)?.toInt() ?? 0,
      );
    }
  }
  throw StateError('video_unsupported');
}

/// Decoding, quantising and encoding all happen natively. Doing the encode in
/// Dart took minutes for anything longer than a couple of seconds.
Future<GifResult> convertVideoToGif({
  required String path,
  required int startMs,
  required int endMs,
  required int fps,
  required int width,
  String? name,
}) async {
  if (!videoGifSupported) throw StateError('video_unsupported');
  final stem = (name == null || name.trim().isEmpty)
      ? 'nullmp3-${DateTime.now().millisecondsSinceEpoch}'
      : name.trim();
  final data = await _filesChannel.invokeMapMethod<String, dynamic>('makeGif', {
    'path': path,
    'startMs': startMs,
    'endMs': endMs,
    'fps': fps,
    'maxWidth': width,
    'name': stem,
  }).timeout(const Duration(minutes: 5));
  if (data == null) throw StateError('gif_failed');
  final file = data['file']?.toString() ?? '';
  final saved = data['path']?.toString() ?? '';
  if (file.isEmpty && saved.isEmpty) throw StateError('gif_failed');
  return GifResult(
    path: saved.isEmpty ? file : saved,
    file: file.isEmpty ? saved : file,
    frames: (data['frames'] as num?)?.toInt() ?? 0,
    sizeBytes: (data['size'] as num?)?.toInt() ?? 0,
  );
}
