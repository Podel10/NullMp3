import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_actions.dart';
import 'tag_write.dart';

const _filesChannel = MethodChannel('com.nullmp3.nullmp3/files');

class AudioWaveform {
  const AudioWaveform({
    required this.peaks,
    required this.durationMs,
    required this.sampleRate,
    required this.bitrate,
    required this.mime,
  });

  final List<double> peaks;
  final int durationMs;
  final int sampleRate;
  final int bitrate;
  final String mime;

  String get formatLabel {
    final type = mime.toLowerCase();
    if (type.contains('mpeg') || type.contains('mp3')) return 'MP3';
    if (type.contains('mp4') || type.contains('aac') || type.contains('m4a')) return 'M4A';
    if (type.contains('wav')) return 'WAV';
    if (type.contains('flac')) return 'FLAC';
    if (type.contains('ogg') || type.contains('opus')) return 'OGG';
    return 'AUDIO';
  }

  int get bitrateKbps => bitrate >= 1000 ? (bitrate / 1000).round() : bitrate;
}

Future<AudioWaveform> loadAudioWaveform(String path, {int bars = 400, int durationMs = 0}) async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      final data = await _filesChannel.invokeMapMethod<String, dynamic>('waveform', {
        'path': path,
        'bars': bars,
      }).timeout(const Duration(seconds: 25));
      final raw = data?['peaks'];
      if (raw is List && raw.isNotEmpty) {
        return AudioWaveform(
          peaks: [for (final value in raw) (value as num).toDouble()],
          durationMs: (data?['durationMs'] as num?)?.toInt() ?? durationMs,
          sampleRate: (data?['sampleRate'] as num?)?.toInt() ?? 44100,
          bitrate: (data?['bitrate'] as num?)?.toInt() ?? 128000,
          mime: data?['mime'] as String? ?? 'audio/*',
        );
      }
    } catch (_) {}
  }
  return AudioWaveform(
    peaks: List<double>.filled(bars, 0.12),
    durationMs: durationMs,
    sampleRate: 44100,
    bitrate: 128000,
    mime: p.extension(path).toLowerCase() == '.mp3' ? 'audio/mpeg' : 'audio/*',
  );
}

/// Duration of a file as the decoder sees it, which is how the result of a cut
/// gets verified instead of trusting the requested selection.
Future<int> probeAudioDurationMs(String path) async {
  final wave = await loadAudioWaveform(path, bars: 64);
  return wave.durationMs;
}

Future<String> materializeAudioFile(String path) async {
  if (kIsWeb || !Platform.isAndroid) return path;
  final saved = await _filesChannel.invokeMethod<String>('materializeAudio', {
    'path': path,
  }).timeout(const Duration(seconds: 12));
  if (saved == null || saved.isEmpty) throw StateError('missing');
  return saved;
}

Future<String> cutAudioFile({
  required String path,
  required String sourceExt,
  required int startMs,
  required int endMs,
  required int durationMs,
  required String title,
  required String artist,
  required String album,
}) async {
  if (!kIsWeb && Platform.isAndroid) {
    final saved = await _filesChannel.invokeMethod<String>('cutAudio', {
      'path': path,
      'destPath': '',
      // [path] is normally a cache copy with no real extension, so the native
      // side needs the original format to pick a trimming strategy.
      'ext': sourceExt,
      'startMs': startMs,
      'endMs': endMs,
      'durationMs': durationMs,
      'title': title,
      'artist': artist,
      'album': album,
    }).timeout(const Duration(seconds: 50));
    if (saved == null || saved.isEmpty) throw StateError('cut_failed');
    return saved;
  }

  final ext = sourceExt.isEmpty ? '.mp3' : sourceExt;
  final dir = await _writableCutDir();
  final destPath = p.join(dir, _cutFileName(title, ext));
  await Directory(dir).create(recursive: true);
  return _cutAudioFileDart(
    path: path,
    destPath: destPath,
    startMs: startMs,
    endMs: endMs,
    durationMs: durationMs,
    title: title,
    artist: artist,
    album: album,
  );
}

Future<String> _cutAudioFileDart({
  required String path,
  required String destPath,
  required int startMs,
  required int endMs,
  required int durationMs,
  required String title,
  required String artist,
  required String album,
}) async {
  final source = File(path);
  final dest = File(destPath);
  final length = await source.length().timeout(const Duration(seconds: 2));
  if (length < 256) throw StateError('too_small');
  final audioStart = await _id3Skip(source, length);
  final audioLen = math.max(1, length - audioStart);
  final dur = math.max(1, durationMs);
  var from = audioStart + audioLen * startMs.clamp(0, dur) ~/ dur;
  var to = audioStart + audioLen * endMs.clamp(startMs + 200, dur) ~/ dur;
  from = from.clamp(audioStart, length - 256);
  to = to.clamp(from + 256, length);

  final out = dest.openWrite();
  try {
    out.add(id3v23TextTag(title: title, artist: artist, album: album));
    await out.addStream(source.openRead(from, to)).timeout(const Duration(seconds: 8));
    await out.flush();
  } finally {
    try {
      await out.close();
    } catch (_) {}
  }
  return dest.path;
}

Future<int> _id3Skip(File file, int length) async {
  try {
    final bytes = await file.openRead(0, math.min(10, length)).fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (builder, chunk) => builder..add(chunk),
    ).timeout(const Duration(milliseconds: 800));
    final head = bytes.takeBytes();
    if (head.length < 10 || head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) {
      return 0;
    }
    if (head[6] & 0x80 != 0 || head[7] & 0x80 != 0 || head[8] & 0x80 != 0 || head[9] & 0x80 != 0) {
      return 0;
    }
    final size = (head[9] & 0x7F) | ((head[8] & 0x7F) << 7) | ((head[7] & 0x7F) << 14) | ((head[6] & 0x7F) << 21);
    final total = 10 + size;
    if (total <= 10 || total > length - 256) return 0;
    return total;
  } catch (_) {
    return 0;
  }
}

String _cutFileName(String title, String ext) {
  var stem = safeAudioFileName(title);
  if (stem.isEmpty) stem = 'cut';
  if (!RegExp(r'\(cut\)(\s*\(\d+\))?$', caseSensitive: false).hasMatch(stem)) {
    stem = '$stem (cut)';
  }
  return '$stem$ext';
}

Future<String> _writableCutDir() async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory(p.join(ext.path, 'cuts'));
        await dir.create(recursive: true);
        return dir.path;
      }
    } catch (_) {}
  }
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'cuts'));
  await dir.create(recursive: true);
  return dir.path;
}

String cutDisplayTitle(String title) {
  final trimmed = title.trim();
  if (RegExp(r'\(cut\)(\s*\(\d+\))?$', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  return '$trimmed (cut)';
}
