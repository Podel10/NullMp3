import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import 'cover_image.dart';

const _motionOwner = 'com.nullmp3.cover';
const _maxMotionBytes = 8 * 1024 * 1024;

void writeAudioTags(Map<String, Object?> args) {
  final path = args['path'] as String;
  var cover = args['cover'] as Uint8List?;
  if (cover != null && isAnimatedCover(cover)) cover = null;
  var motion = args['motion'] as Uint8List?;
  if (motion != null && (motion.length < 32 || motion.length > _maxMotionBytes || !isAnimatedCover(motion))) {
    motion = null;
  }
  final file = File(path);
  if (_isMp3Path(path) || _mpegAudioOffset(file) >= 0) {
    _rewriteMp3(
      file,
      title: args['title'] as String,
      artist: args['artist'] as String,
      album: args['album'] as String,
      albumArtist: args['albumArtist'] as String? ?? '',
      composer: args['composer'] as String? ?? '',
      cover: cover,
      motion: motion,
    );
    return;
  }
  final metadata = readAllMetadata(file, getImage: cover == null);
  metadata.setTitle(args['title'] as String);
  metadata.setArtist(args['artist'] as String);
  metadata.setAlbum(args['album'] as String);
  final albumArtist = args['albumArtist'] as String? ?? '';
  final composer = args['composer'] as String? ?? '';
  switch (metadata) {
    case Mp3Metadata m:
      m.bandOrOrchestra = albumArtist;
      m.composer = composer;
    case VorbisMetadata m:
      m.composer = [composer];
    case ApeMetadata m:
      m.albumArtist = albumArtist;
      m.composer = composer;
    default:
      break;
  }
  if (cover != null) {
    metadata.setPictures([
      Picture(cover, args['coverMime'] as String? ?? 'image/jpeg', PictureType.coverFront),
    ]);
  }
  writeMetadata(file, metadata);
}

/// Rebuilds a silent/unplayable tagged MP3 around its MPEG frames.
/// Safe to call on every load; no-ops when the file is already healthy.
void repairMp3ForPlayback(String path) {
  if (!_isMp3Path(path)) return;
  final file = File(path);
  if (!file.existsSync()) return;
  final major = _id3MajorVersion(file);
  final mpeg = _mpegAudioOffset(file);
  if (mpeg < 0) return;
  final claimed = _id3SkipBytes(file);
  final broken = major == 4 || (mpeg < claimed);
  if (!broken) return;
  _replaceFile(file, prefix: Uint8List(0), audioOffset: mpeg);
}

bool _isMp3Path(String path) => p.extension(path).toLowerCase() == '.mp3';

void _rewriteMp3(
  File file, {
  required String title,
  required String artist,
  required String album,
  required String albumArtist,
  required String composer,
  Uint8List? cover,
  Uint8List? motion,
}) {
  final mpeg = _mpegAudioOffset(file);
  if (mpeg < 0) {
    throw StateError('No MP3 audio in file');
  }
  final tag = _id3v23Tag(
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    composer: composer,
    cover: cover,
    motion: motion,
  );
  _replaceFile(file, prefix: tag, audioOffset: mpeg);
}

void _replaceFile(File file, {required Uint8List prefix, required int audioOffset}) {
  final out = File('${file.path}.nullmp3out');
  final input = file.openSync();
  final output = out.openSync(mode: FileMode.writeOnly);
  try {
    if (prefix.isNotEmpty) output.writeFromSync(prefix);
    input.setPositionSync(audioOffset);
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
  try {
    out.renameSync(file.path);
  } catch (_) {
    file.deleteSync();
    out.renameSync(file.path);
  }
}

int? _id3MajorVersion(File file) {
  final raf = file.openSync();
  try {
    if (raf.lengthSync() < 10) return null;
    final header = raf.readSync(10);
    if (header.length < 10 || header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
      return null;
    }
    return header[3];
  } finally {
    raf.closeSync();
  }
}

int _id3SkipBytes(File file) {
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    var offset = 0;
    while (offset + 10 <= length) {
      raf.setPositionSync(offset);
      final header = raf.readSync(10);
      if (header.length < 10 || header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
        break;
      }
      if (header[6] & 0x80 != 0 ||
          header[7] & 0x80 != 0 ||
          header[8] & 0x80 != 0 ||
          header[9] & 0x80 != 0) {
        break;
      }
      final size = (header[9] & 0x7F) |
          ((header[8] & 0x7F) << 7) |
          ((header[7] & 0x7F) << 14) |
          ((header[6] & 0x7F) << 21);
      final footer = header[3] == 4 && header[5] & 0x10 != 0 ? 10 : 0;
      final total = 10 + size + footer;
      if (total <= 10 || offset + total > length) break;
      offset += total;
    }
    return offset;
  } finally {
    raf.closeSync();
  }
}

int _mpegAudioOffset(File file) {
  final claimed = _id3SkipBytes(file);
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    if (length < 4) return -1;
    if (claimed > 0 && claimed + 4 <= length) {
      raf.setPositionSync(claimed);
      final header = raf.readSync(4);
      if (_mp3FrameLength(header) != null) return claimed;
      final nearby = _scanMpeg(raf, claimed, (claimed + 512 * 1024).clamp(0, length), length);
      if (nearby >= 0) return nearby;
    }
    final limit = length < 8 * 1024 * 1024 ? length : 8 * 1024 * 1024;
    return _scanMpeg(raf, 0, limit, length);
  } finally {
    raf.closeSync();
  }
}

int _scanMpeg(RandomAccessFile raf, int start, int limit, int length) {
  var i = start;
  while (i + 4 <= limit) {
    raf.setPositionSync(i);
    final bytes = raf.readSync(4);
    if (bytes.length < 4) return -1;
    final frameLen = _mp3FrameLength(bytes);
    if (frameLen != null && frameLen >= 21 && i + frameLen + 4 <= length) {
      raf.setPositionSync(i + frameLen);
      final next = raf.readSync(4);
      if (next.length == 4 && _mp3FrameLength(next) != null) {
        return i;
      }
    }
    i++;
  }
  return -1;
}

int? _mp3FrameLength(Uint8List h) {
  if (h.length < 4 || h[0] != 0xFF || (h[1] & 0xE0) != 0xE0) return null;
  final versionId = (h[1] >> 3) & 3;
  if (versionId == 1) return null;
  final layerBits = (h[1] >> 1) & 3;
  if (layerBits == 0) return null;
  final bitrateIdx = h[2] >> 4;
  final srIdx = (h[2] >> 2) & 3;
  if (bitrateIdx == 0 || bitrateIdx == 15 || srIdx == 3) return null;
  if ((h[3] & 3) == 2) return null;
  final padding = (h[2] >> 1) & 1;
  final mpeg1 = versionId == 3;
  final layer3 = layerBits == 1;
  final bitrate = _bitrateKbps(mpeg1, layer3, bitrateIdx);
  final sampleRate = _sampleRate(versionId, srIdx);
  if (bitrate == null || sampleRate == null) return null;
  if (layer3) {
    final scale = mpeg1 ? 144 : 72;
    return (scale * bitrate * 1000) ~/ sampleRate + padding;
  }
  if (layerBits == 2) {
    return (144 * bitrate * 1000) ~/ sampleRate + padding;
  }
  return (12 * bitrate * 1000) ~/ sampleRate * 4 + padding * 4;
}

int? _bitrateKbps(bool mpeg1, bool layer3, int index) {
  if (mpeg1 && layer3) {
    const table = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320];
    return table[index];
  }
  if (mpeg1 && !layer3) {
    const table = [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384];
    return table[index];
  }
  if (!mpeg1 && layer3) {
    const table = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160];
    return table[index];
  }
  return null;
}

int? _sampleRate(int versionId, int index) {
  if (versionId == 3) return const [44100, 48000, 32000][index];
  if (versionId == 2) return const [22050, 24000, 16000][index];
  if (versionId == 0) return const [11025, 12000, 8000][index];
  return null;
}

Uint8List id3v23TextTag({
  required String title,
  required String artist,
  required String album,
}) {
  return _id3v23Tag(
    title: title,
    artist: artist,
    album: album,
    albumArtist: '',
    composer: '',
    cover: null,
  );
}

Uint8List _id3v23Tag({
  required String title,
  required String artist,
  required String album,
  required String albumArtist,
  required String composer,
  Uint8List? cover,
  Uint8List? motion,
}) {
  final frames = BytesBuilder();
  _textFrame(frames, 'TIT2', title);
  _textFrame(frames, 'TPE1', artist);
  _textFrame(frames, 'TALB', album);
  _textFrame(frames, 'TPE2', albumArtist);
  _textFrame(frames, 'TCOM', composer);
  if (motion != null && motion.length >= 32 && motion.length <= _maxMotionBytes && isAnimatedCover(motion)) {
    _privFrame(frames, motion);
  }
  if (cover != null && cover.length >= 32 && !isAnimatedCover(cover)) {
    _apicFrame(frames, cover);
  }
  final body = frames.toBytes();
  final header = BytesBuilder();
  header.add([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]);
  header.add(_synchsafe(body.length));
  header.add(body);
  return header.toBytes();
}

void _textFrame(BytesBuilder frames, String id, String value) {
  final text = value.trim();
  if (text.isEmpty) return;
  final payload = BytesBuilder();
  payload.addByte(1);
  payload.add([0xFF, 0xFE]);
  for (final unit in text.codeUnits) {
    payload.addByte(unit & 0xFF);
    payload.addByte((unit >> 8) & 0xFF);
  }
  payload.add([0x00, 0x00]);
  final bytes = payload.toBytes();
  frames.add(id.codeUnits);
  frames.add(_u32be(bytes.length));
  frames.add([0, 0]);
  frames.add(bytes);
}

void _apicFrame(BytesBuilder frames, Uint8List cover) {
  final mime = mimeOfImage(cover);
  final payload = BytesBuilder();
  payload.addByte(0);
  payload.add([...mime.codeUnits, 0]);
  payload.addByte(3);
  payload.addByte(0);
  payload.add(cover);
  final bytes = payload.toBytes();
  frames.add('APIC'.codeUnits);
  frames.add(_u32be(bytes.length));
  frames.add([0, 0]);
  frames.add(bytes);
}

void _privFrame(BytesBuilder frames, Uint8List motion) {
  final payload = BytesBuilder();
  payload.add([..._motionOwner.codeUnits, 0]);
  payload.add(motion);
  final bytes = payload.toBytes();
  frames.add('PRIV'.codeUnits);
  frames.add(_u32be(bytes.length));
  frames.add([0, 0]);
  frames.add(bytes);
}

Uint8List? readNullmp3MotionCover(File file) {
  if (!file.existsSync()) return null;
  final raf = file.openSync();
  try {
    final length = raf.lengthSync();
    if (length < 20) return null;
    final header = raf.readSync(10);
    if (header.length < 10 || header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
      return null;
    }
    if (header[6] & 0x80 != 0 ||
        header[7] & 0x80 != 0 ||
        header[8] & 0x80 != 0 ||
        header[9] & 0x80 != 0) {
      return null;
    }
    final tagSize = (header[9] & 0x7F) |
        ((header[8] & 0x7F) << 7) |
        ((header[7] & 0x7F) << 14) |
        ((header[6] & 0x7F) << 21);
    final end = (10 + tagSize).clamp(10, length);
    var offset = 10;
    while (offset + 10 <= end) {
      raf.setPositionSync(offset);
      final frame = raf.readSync(10);
      if (frame.length < 10 || frame[0] == 0) break;
      final id = String.fromCharCodes(frame.sublist(0, 4));
      final size = (frame[4] << 24) | (frame[5] << 16) | (frame[6] << 8) | frame[7];
      if (size <= 0 || offset + 10 + size > end) break;
      if (id == 'PRIV' && size > _motionOwner.length + 32 && size <= _maxMotionBytes + 64) {
        raf.setPositionSync(offset + 10);
        final payload = raf.readSync(size);
        final ownerEnd = payload.indexOf(0);
        if (ownerEnd > 0) {
          final owner = String.fromCharCodes(payload.sublist(0, ownerEnd));
          if (owner == _motionOwner) {
            final data = payload.sublist(ownerEnd + 1);
            if (data.length >= 32 && isAnimatedCover(data)) return data;
          }
        }
      }
      offset += 10 + size;
    }
    return null;
  } finally {
    raf.closeSync();
  }
}

Uint8List _synchsafe(int value) {
  return Uint8List.fromList([
    (value >> 21) & 0x7F,
    (value >> 14) & 0x7F,
    (value >> 7) & 0x7F,
    value & 0x7F,
  ]);
}

Uint8List _u32be(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}
