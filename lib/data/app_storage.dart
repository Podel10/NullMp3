import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Fixed on-disk home for themes, customization, covers, and wallpaper.
/// Survives app updates on Windows and Android (unlike VERSIONINFO-tied
/// Flutter support folders that can move when CompanyName/ProductName change).
class AppStorage {
  AppStorage._();

  static Directory? _root;
  static bool _migrated = false;

  static Future<Directory> root() async {
    if (_root != null) return _root!;
    late final Directory dir;
    if (!kIsWeb && Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        dir = Directory(p.join(appData, 'NullMP3'));
      } else {
        dir = await getApplicationSupportDirectory();
      }
    } else {
      // Android package data survives APK updates with the same applicationId.
      dir = await getApplicationSupportDirectory();
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    await _migrateLegacyOnce(dir);
    return dir;
  }

  static Future<Directory> subdir(String name) async {
    final dir = Directory(p.join((await root()).path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> settingsFile() async =>
      File(p.join((await root()).path, 'user_settings.json'));

  /// Older Flutter support roots (CompanyName\\ProductName) plus prior fixed names.
  static Future<List<Directory>> legacyRoots() async {
    final out = <Directory>[];
    try {
      final current = await getApplicationSupportDirectory();
      out.add(current);
    } catch (_) {}
    if (kIsWeb || !Platform.isWindows) return out;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return out;
    for (final relative in const [
      r'com.nullmp3\Null MP3',
      r'nullmp3\Null MP3',
      r'Null MP3',
      r'com.example.nullmp3\Null MP3',
      r'com.nullmp3\nullmp3',
    ]) {
      out.add(Directory(p.join(appData, relative)));
    }
    return out;
  }

  static Future<void> _migrateLegacyOnce(Directory dest) async {
    if (_migrated) return;
    _migrated = true;
    final destNorm = p.normalize(dest.path).toLowerCase();
    final names = [
      'artwork',
      'lyrics',
      'theme_wallpaper.jpg',
      'theme_wallpaper.jpeg',
      'theme_wallpaper.png',
      'theme_wallpaper.webp',
      'theme_wallpaper.gif',
      'library_cache_v3.json',
      'user_settings.json',
      'shared_preferences.json',
    ];
    for (final legacy in await legacyRoots()) {
      final legacyNorm = p.normalize(legacy.path).toLowerCase();
      if (legacyNorm == destNorm) continue;
      if (!await legacy.exists()) continue;
      try {
        await for (final entity in legacy.list(followLinks: false)) {
          final name = p.basename(entity.path);
          if (name.startsWith('theme_wallpaper')) {
            final target = File(p.join(dest.path, name));
            if (entity is File && !await target.exists()) {
              await entity.copy(target.path);
            }
            continue;
          }
          if (!names.contains(name) && name != 'artwork' && name != 'lyrics') {
            continue;
          }
          if (entity is Directory && (name == 'artwork' || name == 'lyrics')) {
            final targetDir = Directory(p.join(dest.path, name));
            if (!await targetDir.exists()) await targetDir.create(recursive: true);
            await for (final file in entity.list(recursive: false, followLinks: false)) {
              if (file is! File) continue;
              final destFile = File(p.join(targetDir.path, p.basename(file.path)));
              if (!await destFile.exists()) await file.copy(destFile.path);
            }
          } else if (entity is File) {
            final target = File(p.join(dest.path, name));
            if (!await target.exists()) await entity.copy(target.path);
          }
        }
      } catch (_) {}
    }
  }

  /// Import SharedPreferences keys from a legacy Windows prefs JSON if missing.
  static Future<Map<String, Object>> readLegacyPrefs() async {
    final merged = <String, Object>{};
    for (final root in await legacyRoots()) {
      final file = File(p.join(root.path, 'shared_preferences.json'));
      if (!await file.exists()) continue;
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is! Map) continue;
        raw.forEach((key, value) {
          if (key is! String || value == null) return;
          // Flutter Windows stores keys as flutter.prefix
          final clean = key.startsWith('flutter.') ? key.substring(8) : key;
          if (!merged.containsKey(clean) && value is Object) {
            merged[clean] = value;
          }
        });
      } catch (_) {}
    }
    final durablePrefs = File(p.join((await root()).path, 'shared_preferences.json'));
    if (await durablePrefs.exists()) {
      try {
        final raw = jsonDecode(await durablePrefs.readAsString());
        if (raw is Map) {
          raw.forEach((key, value) {
            if (key is! String || value == null) return;
            final clean = key.startsWith('flutter.') ? key.substring(8) : key;
            if (!merged.containsKey(clean) && value is Object) {
              merged[clean] = value;
            }
          });
        }
      } catch (_) {}
    }
    return merged;
  }
}
