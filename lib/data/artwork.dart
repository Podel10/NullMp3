import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cover_image.dart';
import 'tag_write.dart';

const _artworkExts = ['gif', 'webp', 'mp4', 'webm', 'bin'];
const _videoHeader = 256;
const _maxMemoryItems = 40;
const _maxMemoryBytes = 10 * 1024 * 1024;

Uint8List? extractArtworkBytes(String trackPath) {
  try {
    final motion = readNullmp3MotionCover(File(trackPath));
    if (motion != null && motion.length >= 32) return motion;
  } catch (_) {}
  try {
    final meta = readMetadata(File(trackPath), getImage: true);
    if (meta.pictures.isEmpty) return null;
    Picture? cover;
    for (final picture in meta.pictures) {
      if (picture.pictureType == PictureType.coverFront) {
        cover = picture;
        break;
      }
    }
    final bytes = (cover ?? meta.pictures.first).bytes;
    if (bytes.length < 32) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

class ArtworkStore extends ChangeNotifier {
  ArtworkStore._();
  static final ArtworkStore instance = ArtworkStore._();

  Directory? _cacheDir;
  final _memory = <String, Uint8List?>{};
  final _generation = <String, int>{};
  final _inflight = <String, Future<Uint8List?>>{};
  int _running = 0;
  final _waiters = <Completer<void>>[];

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(support.path, 'artwork'));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
  }

  String _key(String trackPath) => trackPath.hashCode.toRadixString(16);

  File _file(String key, String ext) => File(p.join(_cacheDir?.path ?? '', '$key.$ext'));

  Future<File?> _existingFile(String key) async {
    final dir = _cacheDir;
    if (dir == null) return null;
    for (final ext in _artworkExts) {
      final file = _file(key, ext);
      if (await file.exists()) return file;
    }
    return null;
  }

  Future<void> _deleteSiblings(String key, String keepExt) async {
    for (final ext in _artworkExts) {
      if (ext == keepExt) continue;
      try {
        final file = _file(key, ext);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<Uint8List?> get(String trackPath) {
    if (_memory.containsKey(trackPath)) {
      final value = _memory.remove(trackPath);
      _memory[trackPath] = value;
      return Future<Uint8List?>.value(value);
    }
    return _inflight.putIfAbsent(trackPath, () async {
      try {
        return await _load(trackPath);
      } finally {
        _inflight.remove(trackPath);
      }
    });
  }

  Future<File?> mediaFile(String trackPath) async {
    final key = _key(trackPath);
    for (final ext in const ['mp4', 'webm', 'bin']) {
      final file = _file(key, ext);
      try {
        if (!await file.exists()) continue;
        final length = await file.length();
        if (length < 32) continue;
        if (ext == 'bin') {
          final header = await _readPrefix(file, 32);
          if (header == null || !isVideoBytes(header)) continue;
        }
        return file;
      } catch (_) {}
    }
    return null;
  }

  Future<Uint8List?> _load(String trackPath) async {
    final gen = generationOf(trackPath);
    final key = _key(trackPath);
    final cached = await _existingFile(key);
    if (cached != null) {
      try {
        if (_isVideoPath(cached.path)) {
          final header = await _readPrefix(cached, _videoHeader);
          return _finishLoad(trackPath, gen, header);
        }
        final bytes = await cached.readAsBytes();
        final value = bytes.isEmpty ? null : bytes;
        if (value != null && isVideoBytes(value)) {
          unawaited(_storeVideoFile(key, value));
          return _finishLoad(trackPath, gen, _headerOf(value));
        }
        return _finishLoad(trackPath, gen, value);
      } catch (_) {}
    }

    await _acquire();
    Uint8List? bytes;
    try {
      bytes = await compute(extractArtworkBytes, trackPath);
    } finally {
      _release();
    }

    if (generationOf(trackPath) != gen) return _memory[trackPath];
    if (bytes != null && isVideoBytes(bytes)) {
      await _storeVideoFile(key, bytes);
      return _finishLoad(trackPath, gen, _headerOf(bytes));
    }
    final kept = _finishLoad(trackPath, gen, bytes);
    if (kept != bytes) return kept;
    if (_cacheDir != null) {
      try {
        final ext = bytes == null || bytes.isEmpty ? 'bin' : artworkExtension(bytes);
        await _file(key, ext).writeAsBytes(bytes ?? Uint8List(0), flush: false);
        await _deleteSiblings(key, ext);
      } catch (_) {}
    }
    return bytes;
  }

  Uint8List? _finishLoad(String trackPath, int gen, Uint8List? bytes) {
    if (generationOf(trackPath) != gen) return _memory[trackPath];
    _remember(trackPath, bytes);
    return bytes;
  }

  void _remember(String trackPath, Uint8List? bytes) {
    _memory[trackPath] = bytes;
    var total = 0;
    for (final item in _memory.values) {
      total += item?.lengthInBytes ?? 0;
    }
    while (_memory.length > _maxMemoryItems || total > _maxMemoryBytes) {
      if (_memory.length <= 4) break;
      final first = _memory.keys.first;
      total -= _memory.remove(first)?.lengthInBytes ?? 0;
    }
  }

  Future<void> _storeVideoFile(String key, Uint8List bytes) async {
    if (_cacheDir == null) return;
    final ext = artworkExtension(bytes);
    try {
      await _file(key, ext).writeAsBytes(bytes, flush: false);
      await _deleteSiblings(key, ext);
    } catch (_) {}
  }

  static bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.webm');
  }

  static Uint8List _headerOf(Uint8List bytes) {
    if (bytes.length <= _videoHeader) return Uint8List.fromList(bytes);
    return Uint8List.fromList(bytes.sublist(0, _videoHeader));
  }

  static Future<Uint8List?> _readPrefix(File file, int max) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final length = await raf.length();
      if (length <= 0) return null;
      final n = length < max ? length : max;
      final out = Uint8List(n);
      var filled = 0;
      while (filled < n) {
        final read = await raf.readInto(out, filled, n);
        if (read <= 0) break;
        filled += read;
      }
      if (filled == n) return out;
      return Uint8List.fromList(out.sublist(0, filled));
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<void> _acquire() async {
    if (_running >= 2) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _running++;
  }

  void _release() {
    _running--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  int generationOf(String path) => _generation[path] ?? 0;

  Future<void> put(String trackPath, Uint8List bytes) async {
    _generation[trackPath] = generationOf(trackPath) + 1;
    final video = isVideoBytes(bytes);
    _remember(trackPath, video ? _headerOf(bytes) : bytes);
    final key = _key(trackPath);
    final ext = artworkExtension(bytes);
    if (_cacheDir != null) {
      try {
        await _file(key, ext).writeAsBytes(bytes, flush: false);
        await _deleteSiblings(key, ext);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> rekey(String fromPath, String toPath) async {
    if (fromPath == toPath) return;
    final bytes = _memory.remove(fromPath);
    if (bytes != null) _memory[toPath] = bytes;
    _generation[toPath] = generationOf(toPath) + 1;
    final fromKey = _key(fromPath);
    final toKey = _key(toPath);
    for (final ext in _artworkExts) {
      try {
        final fromFile = _file(fromKey, ext);
        if (await fromFile.exists()) {
          await fromFile.copy(_file(toKey, ext).path);
        }
      } catch (_) {}
    }
  }

  Future<void> invalidate(String trackPath) async {
    _memory.remove(trackPath);
    _generation[trackPath] = generationOf(trackPath) + 1;
    await _deleteSiblings(_key(trackPath), '');
  }
}
