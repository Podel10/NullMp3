import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PlaybackCache {
  PlaybackCache._();
  static String? dir;

  static Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory(p.join(support.path, 'playcache_v2'));
    if (!await folder.exists()) await folder.create(recursive: true);
    dir = folder.path;
  }
}

/// Strips stacked/huge ID3 (GIF covers we used to write into the file)
/// so other players can see the real audio. Never writes a cover back.
bool repairDamagedAudioFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return false;
  final sniff = _sniff(file);
  if (sniff == null || sniff.offset <= 0) return false;
  if (sniff.id3Count < 2 && sniff.offset < 24 * 1024) return false;
  final expected = file.lengthSync() - sniff.offset;
  if (expected < 1024) return false;
  final tmp = File('${file.path}.nullmp3fix');
  try {
    _copyFrom(file, sniff.offset, tmp);
    if (tmp.lengthSync() != expected) {
      tmp.deleteSync();
      return false;
    }
    try {
      tmp.renameSync(file.path);
    } catch (_) {
      file.deleteSync();
      tmp.renameSync(file.path);
    }
    return true;
  } catch (_) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    return false;
  }
}

/// Maps a library file to a path ExoPlayer can actually decode.
/// Copies to cache only when the container doesn't match the filename.
String preparePlaybackPath(Map<String, String> args) {
  final path = args['path']!;
  final cacheDir = args['cache']!;
  if (cacheDir.isEmpty) return path;
  final file = File(path);
  if (!file.existsSync()) return path;
  final sniff = _sniff(file);
  if (sniff == null) return path;
  final ext = p.extension(path).toLowerCase();
  final needsRename = switch (sniff.kind) {
    _Kind.mp4 => ext != '.m4a' && ext != '.mp4' && ext != '.aac',
    _Kind.aac => ext != '.aac' && ext != '.m4a',
    _Kind.mp3 => false,
  };
  final needsStrip = sniff.offset > 0;
  if (!needsRename && !needsStrip) return path;
  final outExt = switch (sniff.kind) {
    _Kind.mp4 => '.m4a',
    _Kind.aac => '.aac',
    _Kind.mp3 => '.mp3',
  };
  final length = file.lengthSync();
  final expected = length - sniff.offset;
  if (expected < 16) return path;
  final key = '${path.hashCode.toUnsigned(32).toRadixString(16)}_${length}_${sniff.offset}$outExt';
  final dest = File(p.join(cacheDir, key));
  if (dest.existsSync() && dest.lengthSync() == expected) return dest.path;
  _copyFrom(file, sniff.offset, dest);
  if (dest.lengthSync() != expected) {
    try {
      dest.deleteSync();
    } catch (_) {}
    return path;
  }
  return dest.path;
}

enum _Kind { mp3, mp4, aac }

class _Sniff {
  const _Sniff(this.kind, this.offset, this.id3Count);
  final _Kind kind;
  final int offset;
  final int id3Count;
}

_Sniff? _sniff(File file) {
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    if (length < 12) return null;
    final skipped = _skipId3(raf, length);
    if (skipped.offset + 12 > length) return null;
    raf.setPositionSync(skipped.offset);
    final head = raf.readSync(12);
    if (_isFtyp(head, 0)) return _Sniff(_Kind.mp4, skipped.offset, skipped.count);
    if (_isAdts(head)) return _Sniff(_Kind.aac, skipped.offset, skipped.count);
    if (_isMpeg(head)) return _Sniff(_Kind.mp3, skipped.offset, skipped.count);
    return null;
  } finally {
    raf.closeSync();
  }
}

class _Id3Skip {
  const _Id3Skip(this.offset, this.count);
  final int offset;
  final int count;
}

_Id3Skip _skipId3(RandomAccessFile raf, int length) {
  var offset = 0;
  var count = 0;
  final head = Uint8List(10);
  while (offset + 10 <= length) {
    raf.setPositionSync(offset);
    if (raf.readIntoSync(head) < 10) break;
    final size = _id3TagLength(head, length - offset);
    if (size == null) break;
    offset += size;
    count++;
  }
  return _Id3Skip(offset, count);
}

int? _id3TagLength(Uint8List head, int remaining) {
  if (head.length < 10 || head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) {
    return null;
  }
  if (head[6] & 0x80 != 0 || head[7] & 0x80 != 0 || head[8] & 0x80 != 0 || head[9] & 0x80 != 0) {
    return null;
  }
  final size = (head[9] & 0x7F) | ((head[8] & 0x7F) << 7) | ((head[7] & 0x7F) << 14) | ((head[6] & 0x7F) << 21);
  final footer = head[3] == 4 && head[5] & 0x10 != 0 ? 10 : 0;
  final total = 10 + size + footer;
  if (total <= 10 || total >= remaining) return null;
  return total;
}

bool _isFtyp(Uint8List bytes, int offset) {
  if (offset + 8 > bytes.length) return false;
  return bytes[offset + 4] == 0x66 &&
      bytes[offset + 5] == 0x74 &&
      bytes[offset + 6] == 0x79 &&
      bytes[offset + 7] == 0x70;
}

bool _isMpeg(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0xFF || (bytes[1] & 0xE0) != 0xE0) return false;
  final version = (bytes[1] >> 3) & 3;
  final layer = (bytes[1] >> 1) & 3;
  return version != 1 && layer != 0;
}

bool _isAdts(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0xFF) return false;
  return (bytes[1] & 0xF6) == 0xF0;
}

void _copyFrom(File source, int offset, File dest) {
  final parent = dest.parent;
  if (!parent.existsSync()) parent.createSync(recursive: true);
  final input = source.openSync();
  final output = dest.openSync(mode: FileMode.writeOnly);
  try {
    input.setPositionSync(offset);
    final buffer = Uint8List(256 * 1024);
    while (true) {
      final read = input.readIntoSync(buffer);
      if (read <= 0) break;
      output.writeFromSync(buffer, 0, read);
    }
  } finally {
    input.closeSync();
    output.closeSync();
  }
}
