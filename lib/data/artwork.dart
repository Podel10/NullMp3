import 'dart:async';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cover_image.dart';
import 'tag_write.dart';

const _artworkExts = ['bin', 'gif', 'webp', 'mp4', 'webm'];

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
    final bytes = _memory[trackPath] ?? await get(trackPath);
    if (bytes == null || bytes.isEmpty || !isVideoBytes(bytes)) return null;
    final dir = _cacheDir;
    if (dir == null) return null;
    final key = _key(trackPath);
    final ext = artworkExtension(bytes);
    final file = _file(key, ext);
    if (!await file.exists()) {
      try {
        await file.writeAsBytes(bytes, flush: false);
      } catch (_) {
        return null;
      }
    }
    return file;
  }

  Future<Uint8List?> _load(String trackPath) async {
    final gen = generationOf(trackPath);
    final key = _key(trackPath);
    final cached = await _existingFile(key);
    if (cached != null) {
      final bytes = await cached.readAsBytes();
      final value = bytes.isEmpty ? null : bytes;
      return _finishLoad(trackPath, gen, value);
    }

    await _acquire();
    Uint8List? bytes;
    try {
      bytes = await compute(extractArtworkBytes, trackPath);
    } finally {
      _release();
    }

    final kept = _finishLoad(trackPath, gen, bytes);
    if (kept != bytes) return kept;
    if (_cacheDir != null) {
      try {
        await _file(key, 'bin').writeAsBytes(bytes ?? Uint8List(0), flush: false);
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
    while (_memory.length > 80) {
      _memory.remove(_memory.keys.first);
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
    _remember(trackPath, bytes);
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
