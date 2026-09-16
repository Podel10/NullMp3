import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'tag_write.dart';

class Mp3FrameInfo {
  const Mp3FrameInfo({
    required this.length,
    required this.durationMs,
    required this.sampleRate,
    required this.bitrateKbps,
  });

  final int length;
  final double durationMs;
  final int sampleRate;
  final int bitrateKbps;
}

Mp3FrameInfo? mp3FrameInfo(Uint8List h) {
  if (h.length < 4 || h[0] != 0xFF || (h[1] & 0xE0) != 0xE0) return null;
  final versionId = (h[1] >> 3) & 3;
  if (versionId == 1) return null;
  final layerBits = (h[1] >> 1) & 3;
  if (layerBits == 0) return null;
  final bitrateIdx = h[2] >> 4;
  final srIdx = (h[2] >> 2) & 3;
  if (bitrateIdx == 0 || bitrateIdx == 15 || srIdx == 3) return null;
  final padding = (h[2] >> 1) & 1;
  final mpeg1 = versionId == 3;
  final layer3 = layerBits == 1;
  final bitrate = _bitrateKbps(mpeg1, layer3, layerBits, bitrateIdx);
  final sampleRate = _sampleRate(versionId, srIdx);
  if (bitrate == null || sampleRate == null) return null;
  final length = layer3
      ? ((mpeg1 ? 144 : 72) * bitrate * 1000) ~/ sampleRate + padding
      : layerBits == 2
          ? (144 * bitrate * 1000) ~/ sampleRate + padding
          : (12 * bitrate * 1000) ~/ sampleRate * 4 + padding * 4;
  final samples = layer3
      ? (mpeg1 ? 1152 : 576)
      : layerBits == 3
          ? 384
          : 1152;
  return Mp3FrameInfo(
    length: length,
    durationMs: samples * 1000 / sampleRate,
    sampleRate: sampleRate,
    bitrateKbps: bitrate,
  );
}

int skipId3Offset(RandomAccessFile raf, int length) {
  var offset = 0;
  final head = Uint8List(10);
  while (offset + 10 <= length) {
    raf.setPositionSync(offset);
    if (raf.readIntoSync(head) < 10) break;
    if (head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) break;
    if (head[6] & 0x80 != 0 || head[7] & 0x80 != 0 || head[8] & 0x80 != 0 || head[9] & 0x80 != 0) {
      break;
    }
    final size = (head[9] & 0x7F) | ((head[8] & 0x7F) << 7) | ((head[7] & 0x7F) << 14) | ((head[6] & 0x7F) << 21);
    final footer = head[3] == 4 && head[5] & 0x10 != 0 ? 10 : 0;
    final total = 10 + size + footer;
    if (total <= 10 || offset + total > length) break;
    offset += total;
  }
  return offset;
}

Mp3FrameInfo? probeMp3File(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    final pos = skipId3Offset(raf, length);
    raf.setPositionSync(pos);
    final head = raf.readSync(4);
    return mp3FrameInfo(head);
  } catch (_) {
    return null;
  } finally {
    raf.closeSync();
  }
}

bool cutMp3File({
  required String path,
  required String destPath,
  required int startMs,
  required int endMs,
  required String title,
  required String artist,
  required String album,
  int durationMs = 0,
}) {
  final src = File(path);
  if (!src.existsSync()) return false;
  final dest = File(destPath);
  dest.parent.createSync(recursive: true);
  final raf = src.openSync();
  final out = dest.openSync(mode: FileMode.writeOnly);
  var audioBytes = 0;
  try {
    out.writeFromSync(id3v23TextTag(title: title, artist: artist, album: album));
    final length = raf.lengthSync();
    if (length < 256) return false;
    var pos = findFirstFrame(raf, skipId3Offset(raf, length), length);
    var elapsed = 0.0;
    final startAt = startMs.clamp(0, 24 * 60 * 60 * 1000);
    final endAt = math.max(startAt + 200, endMs);
    var guard = 0;
    while (pos + 4 < length && elapsed < startAt && guard++ < 20_000_000) {
      final info = _headerAt(raf, pos);
      if (info == null || info.length < 24 || pos + info.length > length) {
        final next = nextSync(raf, pos + 1, length);
        if (next <= pos) break;
        pos = next;
        continue;
      }
      elapsed += info.durationMs;
      pos += info.length;
    }
    guard = 0;
    while (pos + 4 < length && elapsed < endAt && guard++ < 20_000_000) {
      final info = _headerAt(raf, pos);
      if (info == null || info.length < 24 || pos + info.length > length) {
        final next = nextSync(raf, pos + 1, length);
        if (next <= pos) break;
        pos = next;
        continue;
      }
      raf.setPositionSync(pos);
      final frame = raf.readSync(info.length);
      if (frame.length < info.length) break;
      out.writeFromSync(frame);
      audioBytes += frame.length;
      elapsed += info.durationMs;
      pos += info.length;
    }
  } finally {
    raf.closeSync();
    out.closeSync();
  }
  return dest.existsSync() && audioBytes > 256;
}

int findFirstFrame(RandomAccessFile raf, int start, int length) {
  final limit = math.min(length, start + 64 * 1024);
  var pos = start;
  while (pos + 4 < limit) {
    final info = _headerAt(raf, pos);
    if (info != null && info.length >= 24 && pos + info.length <= length) return pos;
    pos++;
  }
  return start;
}

int nextSync(RandomAccessFile raf, int start, int length) {
  final limit = math.min(length, start + 16 * 1024);
  var pos = start.clamp(0, length);
  while (pos + 4 < limit) {
    final info = _headerAt(raf, pos);
    if (info != null && info.length >= 24) return pos;
    pos++;
  }
  return start.clamp(0, length);
}

Mp3FrameInfo? _headerAt(RandomAccessFile raf, int pos) {
  raf.setPositionSync(pos);
  final head = raf.readSync(4);
  return mp3FrameInfo(head);
}

bool cutAudioJob(Map<dynamic, dynamic> args) {
  final path = args['path'] as String;
  final destPath = args['destPath'] as String;
  final startMs = args['startMs'] as int;
  final endMs = args['endMs'] as int;
  final durationMs = args['durationMs'] as int? ?? 0;
  final title = args['title'] as String? ?? '';
  final artist = args['artist'] as String? ?? '';
  final album = args['album'] as String? ?? '';
  final ext = (args['ext'] as String? ?? '').toLowerCase();
  if (ext == '.wav' || ext == '.wave') {
    return cutWavFile(path: path, destPath: destPath, startMs: startMs, endMs: endMs);
  }
  if (ext == '.mp3' || ext == '.mp2' || ext.isEmpty) {
    return cutMp3File(
      path: path,
      destPath: destPath,
      startMs: startMs,
      endMs: endMs,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
    );
  }
  return false;
}

bool cutWavFile({
  required String path,
  required String destPath,
  required int startMs,
  required int endMs,
}) {
  final src = File(path);
  if (!src.existsSync()) return false;
  final raf = src.openSync();
  try {
    final length = raf.lengthSync();
    if (length < 44) return false;
    var offset = 12;
    var channels = 2;
    var sampleRate = 44100;
    var bits = 16;
    var dataStart = -1;
    var dataSize = 0;
    while (offset + 8 <= length) {
      raf.setPositionSync(offset);
      final head = raf.readSync(8);
      if (head.length < 8) break;
      final id = String.fromCharCodes(head.sublist(0, 4));
      final size = _u32(head, 4);
      if (size < 0 || offset + 8 + size > length) break;
      if (id == 'fmt ') {
        final fmtLen = math.min(size, 40);
        final fmt = raf.readSync(fmtLen);
        if (fmt.length >= 16) {
          channels = math.max(1, _u16(fmt, 2));
          sampleRate = math.max(1, _u32(fmt, 4));
          bits = math.max(8, _u16(fmt, 14));
        }
      } else if (id == 'data') {
        dataStart = offset + 8;
        dataSize = math.min(size, length - dataStart);
        break;
      }
      offset += 8 + size + (size & 1);
    }
    if (dataStart < 0) return false;
    final bytesPerSec = sampleRate * channels * (bits ~/ 8);
    if (bytesPerSec <= 0) return false;
    final align = channels * (bits ~/ 8);
    if (align <= 0) return false;
    var from = (startMs * bytesPerSec) ~/ 1000;
    var to = (endMs * bytesPerSec) ~/ 1000;
    from -= from % align;
    to -= to % align;
    from = from.clamp(0, dataSize);
    to = to.clamp(from, dataSize);
    final sliceLen = to - from;
    if (sliceLen < align) return false;
    final dest = File(destPath);
    dest.parent.createSync(recursive: true);
    final out = dest.openSync(mode: FileMode.writeOnly);
    try {
      final header = Uint8List(44);
      header.setAll(0, 'RIFF'.codeUnits);
      _putU32(header, 4, 36 + sliceLen);
      header.setAll(8, 'WAVEfmt '.codeUnits);
      _putU32(header, 16, 16);
      _putU16(header, 20, 1);
      _putU16(header, 22, channels);
      _putU32(header, 24, sampleRate);
      _putU32(header, 28, bytesPerSec);
      _putU16(header, 32, align);
      _putU16(header, 34, bits);
      header.setAll(36, 'data'.codeUnits);
      _putU32(header, 40, sliceLen);
      out.writeFromSync(header);
      raf.setPositionSync(dataStart + from);
      var left = sliceLen;
      final buf = Uint8List(64 * 1024);
      while (left > 0) {
        final n = raf.readIntoSync(buf, 0, math.min(left, buf.length));
        if (n <= 0) break;
        out.writeFromSync(buf, 0, n);
        left -= n;
      }
    } finally {
      out.closeSync();
    }
    return dest.existsSync() && dest.lengthSync() > 44;
  } catch (_) {
    return false;
  } finally {
    raf.closeSync();
  }
}

List<double> envelopePeaksJob(Map<dynamic, dynamic> args) {
  return envelopePeaks(args['path'] as String, args['bars'] as int);
}

List<double> envelopePeaks(String path, int bars) {
  final file = File(path);
  if (!file.existsSync()) return List<double>.filled(bars, 0.08);
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    if (length < 64) return List<double>.filled(bars, 0.08);
    final start = skipId3Offset(raf, length);
    final audioLen = math.max(1, length - start);
    final chunk = math.max(1, audioLen ~/ bars);
    final buf = Uint8List(2048);
    final peaks = List<double>.filled(bars, 0);
    for (var i = 0; i < bars; i++) {
      raf.setPositionSync(start + i * chunk);
      final n = raf.readIntoSync(buf);
      if (n <= 0) break;
      var maxAbs = 1;
      for (var j = 0; j < n; j++) {
        final v = (buf[j] - 128).abs();
        if (v > maxAbs) maxAbs = v;
      }
      peaks[i] = (maxAbs / 128).clamp(0.04, 1);
    }
    return peaks;
  } catch (_) {
    return List<double>.filled(bars, 0.12);
  } finally {
    raf.closeSync();
  }
}

int _u16(Uint8List data, int i) => data[i] | (data[i + 1] << 8);

int _u32(Uint8List data, int i) =>
    data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24);

void _putU16(Uint8List data, int i, int value) {
  data[i] = value & 0xFF;
  data[i + 1] = (value >> 8) & 0xFF;
}

void _putU32(Uint8List data, int i, int value) {
  data[i] = value & 0xFF;
  data[i + 1] = (value >> 8) & 0xFF;
  data[i + 2] = (value >> 16) & 0xFF;
  data[i + 3] = (value >> 24) & 0xFF;
}

int? _bitrateKbps(bool mpeg1, bool layer3, int layerBits, int index) {
  final table = mpeg1 && layer3
      ? const [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
      : mpeg1 && layerBits == 2
          ? const [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384]
          : mpeg1
              ? const [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448]
              : layer3
                  ? const [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
                  : null;
  if (table == null || index < 0 || index >= table.length) return null;
  final value = table[index];
  return value == 0 ? null : value;
}

int? _sampleRate(int versionId, int index) {
  if (versionId == 3) return const [44100, 48000, 32000][index];
  if (versionId == 2) return const [22050, 24000, 16000][index];
  if (versionId == 0) return const [11025, 12000, 8000][index];
  return null;
}
