import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_actions.dart';
import 'mp3_cut.dart';

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
  var duration = durationMs;
  var sampleRate = 44100;
  var bitrate = 128000;
  try {
    final meta = readMetadata(File(path), getImage: false);
    duration = meta.duration?.inMilliseconds ?? duration;
  } catch (_) {}
  final ext = p.extension(path).toLowerCase();
  return AudioWaveform(
    peaks: envelopePeaks(path, bars),
    durationMs: duration,
    sampleRate: sampleRate,
    bitrate: bitrate,
    mime: ext == '.mp3' ? 'audio/mpeg' : ext == '.wav' || ext == '.wave' ? 'audio/wav' : 'audio/*',
  );
}

/// Duration of a file as the decoder sees it, which is how the result of a cut
/// gets verified instead of trusting the requested selection.
Future<int> probeAudioDurationMs(String path) async {
  final wave = await loadAudioWaveform(path, bars: 64);
  return wave.durationMs;
}

/// True when [path] looks like a fragmented MP4/CMAF dump (HLS concat).
bool fileLooksFragmentedMp4(String path) {
  try {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 64) return false;
    final raf = file.openSync();
    try {
      final length = raf.lengthSync().clamp(0, 2 * 1024 * 1024);
      final buf = raf.readSync(length);
      if (_bufHasDrmMarkers(buf)) return false;
      var hasFtyp = false;
      var hasMoof = false;
      for (var i = 0; i + 8 <= buf.length; i++) {
        if (buf[i + 4] == 0x66 && buf[i + 5] == 0x74 && buf[i + 6] == 0x79 && buf[i + 7] == 0x70) {
          hasFtyp = true;
        }
        if (buf[i + 4] == 0x6D && buf[i + 5] == 0x6F && buf[i + 6] == 0x6F && buf[i + 7] == 0x66) {
          hasMoof = true;
        }
        if (hasFtyp && hasMoof) return true;
      }
    } finally {
      raf.closeSync();
    }
  } catch (_) {}
  return false;
}

bool fileLooksDrmProtected(String path) {
  try {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 64) return false;
    final raf = file.openSync();
    try {
      final n = file.lengthSync().clamp(0, 512 * 1024);
      return _bufHasDrmMarkers(raf.readSync(n));
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
}

bool _bufHasDrmMarkers(List<int> buf) {
  const markers = [
    [0x65, 0x6e, 0x63, 0x61], // enca
    [0x74, 0x65, 0x6e, 0x63], // tenc
    [0x70, 0x73, 0x73, 0x68], // pssh
    [0x73, 0x63, 0x68, 0x6d], // schm
  ];
  for (final marker in markers) {
    for (var i = 0; i <= buf.length - 4; i++) {
      if (buf[i] == marker[0] &&
          buf[i + 1] == marker[1] &&
          buf[i + 2] == marker[2] &&
          buf[i + 3] == marker[3]) {
        return true;
      }
    }
  }
  return false;
}

/// Remux fragmented M4A/MP4 into a progressive file ExoPlayer can play.
/// Android-only (MediaMuxer). Returns the playable path (may equal [path]).
Future<String> remuxAudioIfNeeded(String path, {String? cacheDir}) async {
  if (kIsWeb || !Platform.isAndroid) return path;
  if (!fileLooksFragmentedMp4(path)) return path;
  try {
    Directory dir;
    if (cacheDir != null && cacheDir.isNotEmpty) {
      dir = Directory(cacheDir);
    } else {
      final support = await getApplicationSupportDirectory();
      dir = Directory(p.join(support.path, 'remux'));
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = p.join(
      dir.path,
      '${path.hashCode.toUnsigned(32).toRadixString(16)}_${File(path).lengthSync()}.m4a',
    );
    if (File(dest).existsSync() && File(dest).lengthSync() > 256) return dest;
    final saved = await _filesChannel.invokeMethod<String>('remuxAudio', {
      'path': path,
      'destPath': dest,
    }).timeout(const Duration(seconds: 45));
    if (saved != null && saved.isNotEmpty && File(saved).existsSync()) return saved;
  } catch (_) {}
  return path;
}

/// After a SoundCloud/HLS save: remux in place on Android when needed.
Future<String> finalizeDownloadedAudio(String path) async {
  if (kIsWeb || !Platform.isAndroid) return path;
  if (!fileLooksFragmentedMp4(path)) return path;
  final dir = File(path).parent.path;
  final tmp = p.join(dir, '${p.basenameWithoutExtension(path)}.nullmp3remux.m4a');
  try {
    final saved = await _filesChannel.invokeMethod<String>('remuxAudio', {
      'path': path,
      'destPath': tmp,
    }).timeout(const Duration(seconds: 60));
    if (saved == null || saved.isEmpty || !File(saved).existsSync()) return path;
    final finalPath = p.setExtension(path, '.m4a');
    try {
      await File(path).delete();
    } catch (_) {}
    if (File(finalPath).existsSync() && finalPath != saved) {
      try {
        await File(finalPath).delete();
      } catch (_) {}
    }
    await File(saved).rename(finalPath);
    return finalPath;
  } catch (_) {
    try {
      if (File(tmp).existsSync()) await File(tmp).delete();
    } catch (_) {}
    return path;
  }
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
  final ok = await compute(cutAudioJob, {
    'path': path,
    'destPath': destPath,
    'startMs': startMs,
    'endMs': endMs,
    'durationMs': durationMs,
    'title': title,
    'artist': artist,
    'album': album,
    'ext': ext.toLowerCase(),
  }).timeout(const Duration(seconds: 50));
  if (ok != true) throw StateError('cut_failed');
  return destPath;
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
