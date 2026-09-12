import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

const _filesChannel = MethodChannel('com.nullmp3.nullmp3/files');

/// Deletes [path] from disk. Returns null on success, otherwise an error message.
Future<String?> deleteAudioFile(String path) async {
  if (!kIsWeb && Platform.isAndroid) {
    final first = await _androidDelete(path);
    if (first == 'ok') return null;
    if (first == 'cancelled') return 'cancelled';

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      final retry = await _androidDelete(path);
      if (retry == 'ok') return null;
      if (retry == 'cancelled') return 'cancelled';
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        return null;
      } on PathNotFoundException {
        return null;
      } catch (error) {
        return error.toString();
      }
    }

    return 'needPermission';
  }

  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
    return null;
  } on PathNotFoundException {
    return null;
  } catch (error) {
    return error.toString();
  }
}

Future<String> _androidDelete(String path) async {
  try {
    return await _filesChannel.invokeMethod<String>('deleteFile', {'path': path}) ?? 'failed';
  } catch (_) {
    return 'failed';
  }
}

String safeAudioFileName(String title) {
  var name = title.trim();
  name = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  name = name.replaceAll(RegExp(r'[\. ]+$'), '');
  if (name.length > 120) name = name.substring(0, 120).trim();
  return name;
}

Future<String?> renameAudioFile(String path, String newTitle) async {
  if (path.startsWith('content:')) return null;
  final title = safeAudioFileName(newTitle);
  if (title.isEmpty) return null;
  final dir = p.dirname(path);
  final ext = p.extension(path);
  final current = p.basenameWithoutExtension(path);
  if (title.toLowerCase() == current.toLowerCase()) return path;

  var dest = p.join(dir, '$title$ext');
  var n = 1;
  while (!_samePath(dest, path) && _fileExists(dest)) {
    dest = p.join(dir, '$title ($n)$ext');
    n++;
  }
  if (_samePath(dest, path)) return path;

  try {
    await File(path).rename(dest);
    return dest;
  } catch (_) {}

  if (!kIsWeb && Platform.isAndroid) {
    try {
      final moved = await _filesChannel.invokeMethod<String>('renameFile', {
        'path': path,
        'newName': p.basename(dest),
      });
      if (moved != null && moved != 'failed' && moved.isNotEmpty) return moved;
    } catch (_) {}
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      try {
        await File(path).rename(dest);
        return dest;
      } catch (_) {}
      try {
        final moved = await _filesChannel.invokeMethod<String>('renameFile', {
          'path': path,
          'newName': p.basename(dest),
        });
        if (moved != null && moved != 'failed' && moved.isNotEmpty) return moved;
      } catch (_) {}
    }
  }
  return null;
}

bool _samePath(String a, String b) {
  return p.normalize(a).toLowerCase() == p.normalize(b).toLowerCase();
}

bool _fileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}
