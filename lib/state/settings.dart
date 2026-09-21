import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_storage.dart';
import '../data/network.dart';
import '../data/scanner.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

enum BeatHaloMode {
  simple,
  advanced;

  static BeatHaloMode fromName(String? name) {
    return BeatHaloMode.values.firstWhere(
      (value) => value.name == name,
      orElse: () => BeatHaloMode.advanced,
    );
  }
}

/// How volume is shown while dragging on the now-playing cover (Windows).
enum InteractiveCoverMode {
  /// Volume fill runs left → right across the cover.
  horizontal,
  /// Vertical volume panel on the cover.
  vertical;

  static InteractiveCoverMode fromName(String? name) {
    return InteractiveCoverMode.values.firstWhere(
      (value) => value.name == name,
      orElse: () => InteractiveCoverMode.horizontal,
    );
  }
}

class SettingsController extends ChangeNotifier {
  static const _kTheme = 'themeMode';
  static const _kThemeId = 'themeId';
  static const _kCustomBg = 'customBackground';
  static const _kCustomAccent = 'customAccent';
  static const _kUseCustomAccent = 'useCustomAccent';
  static const _kWallpaper = 'wallpaperPath';
  static const _kWallpaperBlur = 'wallpaperBlur';
  static const _kAccent = 'accentIndex';
  static const _kMinDuration = 'minDurationSec';
  static const _kFolders = 'extraFolders';
  static const _kLibraryFolders = 'libraryFolders';
  static const _kTelegramMusicMigrated = 'telegramMusicFolderMigrated';
  static const _kExtraFiles = 'extraFiles';
  static const _kVolume = 'volume';
  static const _kEq = 'eqBands';
  static const _kEqOn = 'eqEnabled';
  static const _kEqPreset = 'eqPreset';
  static const _kSpeed = 'playbackSpeed';
  static const _kPitch = 'playbackPitch';
  static const _kPauseFade = 'pauseFade';
  static const _kCrossfade = 'crossfade';
  static const _kContinuous = 'continuousPlayback';
  static const _kLanguage = 'language';
  static const _kStatsEnabled = 'statsEnabled';
  static const _kBeatHalo = 'beatHalo';
  static const _kBeatHaloMode = 'beatHaloMode';
  static const _kOffline = 'offlineMode';
  static const _kAskedAllFiles = 'askedAllFiles';
  static const _kUiScale = 'uiScale';
  static const _kInteractiveCover = 'interactiveCover';
  static const _kInteractiveCoverMode = 'interactiveCoverMode';
  static const _kShowLyricsOnCover = 'showLyricsOnCover';

  static const double minUiScale = 0.75;
  static const double maxUiScale = 1.75;
  static const double uiScaleStep = 0.1;

  late SharedPreferences _prefs;

  ThemeMode themeMode = ThemeMode.dark;
  AppThemeId themeId = AppThemeId.dark;
  int accentIndex = 0;
  Color customBackground = const Color(0xFF1B1428);
  Color customAccent = const Color(0xFFFFC933);
  bool useCustomAccent = false;
  String? wallpaperPath;
  double wallpaperBlur = 0.45;
  /// Bumps when gallery wallpaper bytes change so Image.file reloads.
  int wallpaperRevision = 0;
  /// Desktop UI zoom (1.0 = 100%). Windows Ctrl+/−/0.
  double uiScale = 1.0;
  int minDurationSec = 0;
  List<String> libraryFolders = [];
  List<String> extraFiles = [];
  double volume = 1;
  List<double> eqBands = List<double>.filled(5, 0);
  bool eqEnabled = true;
  String eqPreset = 'Normal';
  double speed = 1;
  double pitch = 1;
  bool pauseFade = false;
  bool crossfade = false;
  bool continuous = true;
  bool statsEnabled = true;
  bool beatHalo = false;
  BeatHaloMode beatHaloMode = BeatHaloMode.advanced;
  /// Drag on now-playing cover to change volume (Windows / Android).
  bool interactiveCover = false;
  InteractiveCoverMode interactiveCoverMode = InteractiveCoverMode.horizontal;
  /// Lyrics toggle on now-playing cover (karaoke-style).
  bool showLyricsOnCover = false;
  bool offlineMode = false;
  AppLanguage language = AppLanguage.english;

  bool _loaded = false;

  Color get accent =>
      useCustomAccent ? customAccent : Accents.colors[accentIndex.clamp(0, Accents.colors.length - 1)];

  bool get hasWallpaper => wallpaperPath != null && File(wallpaperPath!).existsSync();

  ThemeMode _modeFor(AppThemeId id) => switch (id) {
        AppThemeId.system => ThemeMode.system,
        AppThemeId.light || AppThemeId.sand => ThemeMode.light,
        AppThemeId.custom => customBackground.computeLuminance() < 0.45 ? ThemeMode.dark : ThemeMode.light,
        AppThemeId.gallery => ThemeMode.dark,
        _ => ThemeMode.dark,
      };

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await AppStorage.root();
    _prefs = await SharedPreferences.getInstance();
    await _restoreMissingFromDurable();
    final storedTheme = _prefs.getString(_kThemeId);
    if (storedTheme != null) {
      themeId = AppThemeId.values.firstWhere(
        (id) => id.name == storedTheme,
        orElse: () => AppThemeId.dark,
      );
    } else {
      themeMode = ThemeMode.values[_prefs.getInt(_kTheme) ?? ThemeMode.dark.index];
      themeId = switch (themeMode) {
        ThemeMode.light => AppThemeId.light,
        ThemeMode.system => AppThemeId.system,
        ThemeMode.dark => AppThemeId.dark,
      };
    }
    themeMode = _modeFor(themeId);
    accentIndex = _prefs.getInt(_kAccent) ?? 0;
    customBackground = Color(_prefs.getInt(_kCustomBg) ?? const Color(0xFF1B1428).toARGB32());
    customAccent = Color(_prefs.getInt(_kCustomAccent) ?? const Color(0xFFFFC933).toARGB32());
    useCustomAccent = _prefs.getBool(_kUseCustomAccent) ?? false;
    wallpaperPath = _prefs.getString(_kWallpaper);
    wallpaperBlur = _prefs.getDouble(_kWallpaperBlur) ?? 0.45;
    await _ensureWallpaperResolved();
    uiScale = (_prefs.getDouble(_kUiScale) ?? 1.0).clamp(minUiScale, maxUiScale);
    minDurationSec = _prefs.getInt(_kMinDuration) ?? 0;
    extraFiles = List<String>.from(jsonDecode(_prefs.getString(_kExtraFiles) ?? '[]'));
    final storedLibrary = _prefs.getString(_kLibraryFolders);
    if (storedLibrary != null) {
      libraryFolders = _uniqueFolders(List<String>.from(jsonDecode(storedLibrary)));
    } else {
      final extras = List<String>.from(jsonDecode(_prefs.getString(_kFolders) ?? '[]'));
      libraryFolders = _uniqueFolders([...defaultMusicRoots(), ...extras]);
      await _prefs.setString(_kLibraryFolders, jsonEncode(libraryFolders));
    }
    if (!(_prefs.getBool(_kTelegramMusicMigrated) ?? false)) {
      const telegramMusic = '/storage/emulated/0/Music/Telegram';
      final already = libraryFolders.any(
        (folder) => pathIsUnderRoots(telegramMusic, [folder]) || pathIsUnderRoots(folder, [telegramMusic]),
      );
      if (!already) {
        libraryFolders = _uniqueFolders([...libraryFolders, telegramMusic]);
        await _saveLibraryFolders();
      }
      await _prefs.setBool(_kTelegramMusicMigrated, true);
    }
    volume = _prefs.getDouble(_kVolume) ?? 1;
    speed = (_prefs.getDouble(_kSpeed) ?? 1).clamp(0.5, 1.5);
    pitch = (_prefs.getDouble(_kPitch) ?? 1).clamp(0.5, 1.5);
    pauseFade = _prefs.getBool(_kPauseFade) ?? false;
    crossfade = _prefs.getBool(_kCrossfade) ?? false;
    continuous = _prefs.getBool(_kContinuous) ?? true;
    statsEnabled = _prefs.getBool(_kStatsEnabled) ?? true;
    beatHalo = _prefs.getBool(_kBeatHalo) ?? false;
    beatHaloMode = BeatHaloMode.fromName(_prefs.getString(_kBeatHaloMode));
    interactiveCover = _prefs.getBool(_kInteractiveCover) ?? false;
    interactiveCoverMode =
        InteractiveCoverMode.fromName(_prefs.getString(_kInteractiveCoverMode));
    showLyricsOnCover = _prefs.getBool(_kShowLyricsOnCover) ?? false;
    offlineMode = _prefs.getBool(_kOffline) ?? false;
    _askedAllFiles = _prefs.getBool(_kAskedAllFiles) ?? false;
    NetworkGate.offline = offlineMode;
    eqEnabled = _prefs.getBool(_kEqOn) ?? true;
    eqPreset = _prefs.getString(_kEqPreset) ?? 'Normal';
    language = AppLanguage.fromName(_prefs.getString(_kLanguage));
    await L10n.ensure(language);
    final storedEq = _prefs.getString(_kEq);
    if (storedEq != null) {
      eqBands = List<double>.from((jsonDecode(storedEq) as List).map((e) => (e as num).toDouble()));
      if (eqBands.length < 5) {
        eqBands = [...eqBands, ...List<double>.filled(5 - eqBands.length, 0)];
      }
    }
    await _persistDurable();
    notifyListeners();
  }

  /// Fill empty SharedPreferences from durable JSON / older Windows prefs folders.
  Future<void> _restoreMissingFromDurable() async {
    try {
      final sources = <Map<String, Object>>[];
      final file = await AppStorage.settingsFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map) {
          sources.add({
            for (final e in raw.entries)
              if (e.key is String && e.value != null) e.key as String: e.value as Object,
          });
        }
      }
      sources.add(await AppStorage.readLegacyPrefs());

      Future<void> putString(String key, Object? value) async {
        if (_prefs.containsKey(key) || value == null) return;
        if (value is String) await _prefs.setString(key, value);
      }

      Future<void> putInt(String key, Object? value) async {
        if (_prefs.containsKey(key) || value == null) return;
        if (value is int) {
          await _prefs.setInt(key, value);
        } else if (value is num) {
          await _prefs.setInt(key, value.toInt());
        }
      }

      Future<void> putDouble(String key, Object? value) async {
        if (_prefs.containsKey(key) || value == null) return;
        if (value is double) {
          await _prefs.setDouble(key, value);
        } else if (value is num) {
          await _prefs.setDouble(key, value.toDouble());
        }
      }

      Future<void> putBool(String key, Object? value) async {
        if (_prefs.containsKey(key) || value == null) return;
        if (value is bool) await _prefs.setBool(key, value);
      }

      Object? lookup(String key) {
        for (final map in sources) {
          if (map.containsKey(key)) return map[key];
        }
        return null;
      }

      await putString(_kThemeId, lookup(_kThemeId) ?? lookup('themeId'));
      await putInt(_kTheme, lookup(_kTheme) ?? lookup('themeMode'));
      await putInt(_kAccent, lookup(_kAccent) ?? lookup('accentIndex'));
      await putInt(_kCustomBg, lookup(_kCustomBg) ?? lookup('customBackground'));
      await putInt(_kCustomAccent, lookup(_kCustomAccent) ?? lookup('customAccent'));
      await putBool(_kUseCustomAccent, lookup(_kUseCustomAccent) ?? lookup('useCustomAccent'));
      await putString(_kWallpaper, lookup(_kWallpaper) ?? lookup('wallpaper'));
      await putDouble(_kWallpaperBlur, lookup(_kWallpaperBlur) ?? lookup('wallpaperBlur'));
      await putDouble(_kUiScale, lookup(_kUiScale) ?? lookup('uiScale'));
      await putBool(_kInteractiveCover, lookup(_kInteractiveCover) ?? lookup('interactiveCover'));
      await putString(
        _kInteractiveCoverMode,
        lookup(_kInteractiveCoverMode) ?? lookup('interactiveCoverMode'),
      );
      await putBool(_kShowLyricsOnCover, lookup(_kShowLyricsOnCover) ?? lookup('showLyricsOnCover'));
      await putBool(_kBeatHalo, lookup(_kBeatHalo) ?? lookup('beatHalo'));
      await putString(_kBeatHaloMode, lookup(_kBeatHaloMode) ?? lookup('beatHaloMode'));
      await putString(_kLanguage, lookup(_kLanguage) ?? lookup('language'));
      await putInt(_kMinDuration, lookup(_kMinDuration) ?? lookup('minDurationSec'));
      await putBool(_kOffline, lookup(_kOffline) ?? lookup('offlineMode'));
      await putBool(_kEqOn, lookup(_kEqOn) ?? lookup('eqEnabled'));
      await putString(_kEqPreset, lookup(_kEqPreset) ?? lookup('eqPreset'));
      final eq = lookup(_kEq) ?? lookup('eqBands');
      if (!_prefs.containsKey(_kEq) && eq != null) {
        if (eq is String) {
          await _prefs.setString(_kEq, eq);
        } else if (eq is List) {
          await _prefs.setString(_kEq, jsonEncode(eq));
        }
      }
      await putDouble(_kVolume, lookup(_kVolume) ?? lookup('volume'));
      await putDouble(_kSpeed, lookup(_kSpeed) ?? lookup('playbackSpeed') ?? lookup('speed'));
      await putDouble(_kPitch, lookup(_kPitch) ?? lookup('playbackPitch') ?? lookup('pitch'));
      await putBool(_kPauseFade, lookup(_kPauseFade) ?? lookup('pauseFade'));
      await putBool(_kCrossfade, lookup(_kCrossfade) ?? lookup('crossfade'));
      await putBool(_kContinuous, lookup(_kContinuous) ?? lookup('continuous'));
      await putBool(_kStatsEnabled, lookup(_kStatsEnabled) ?? lookup('statsEnabled'));
      final folders = lookup(_kLibraryFolders) ?? lookup('libraryFolders');
      if (!_prefs.containsKey(_kLibraryFolders) && folders != null) {
        if (folders is String) {
          await _prefs.setString(_kLibraryFolders, folders);
        } else if (folders is List) {
          await _prefs.setString(_kLibraryFolders, jsonEncode(folders));
        }
      }
    } catch (_) {}
  }

  Future<void> _persistDurable() async {
    try {
      final wallpaperName = wallpaperPath == null ? null : p.basename(wallpaperPath!);
      final payload = <String, Object?>{
        _kThemeId: themeId.name,
        _kTheme: themeMode.index,
        _kAccent: accentIndex,
        _kCustomBg: customBackground.toARGB32(),
        _kCustomAccent: customAccent.toARGB32(),
        _kUseCustomAccent: useCustomAccent,
        _kWallpaper: wallpaperName,
        _kWallpaperBlur: wallpaperBlur,
        _kUiScale: uiScale,
        _kInteractiveCover: interactiveCover,
        _kInteractiveCoverMode: interactiveCoverMode.name,
        _kShowLyricsOnCover: showLyricsOnCover,
        _kBeatHalo: beatHalo,
        _kBeatHaloMode: beatHaloMode.name,
        _kLanguage: language.code,
        _kMinDuration: minDurationSec,
        _kOffline: offlineMode,
        _kEqOn: eqEnabled,
        _kEqPreset: eqPreset,
        _kEq: eqBands,
        _kVolume: volume,
        _kSpeed: speed,
        _kPitch: pitch,
        _kPauseFade: pauseFade,
        _kCrossfade: crossfade,
        _kContinuous: continuous,
        _kStatsEnabled: statsEnabled,
        _kLibraryFolders: libraryFolders,
        'wallpaper': wallpaperName,
      };
      final file = await AppStorage.settingsFile();
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage value) async {
    language = value;
    await L10n.ensure(value);
    await _prefs.setString(_kLanguage, value.code);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setThemeId(AppThemeId id) async {
    themeId = id;
    themeMode = _modeFor(id);
    await _prefs.setString(_kThemeId, id.name);
    await _prefs.setInt(_kTheme, themeMode.index);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setCustomBackground(Color color) async {
    customBackground = color;
    if (themeId == AppThemeId.custom) {
      themeMode = _modeFor(AppThemeId.custom);
      await _prefs.setInt(_kTheme, themeMode.index);
    }
    await _prefs.setInt(_kCustomBg, color.toARGB32());
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setCustomAccent(Color color) async {
    customAccent = color;
    useCustomAccent = true;
    await _prefs.setInt(_kCustomAccent, color.toARGB32());
    await _prefs.setBool(_kUseCustomAccent, true);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setAccent(int index) async {
    accentIndex = index;
    useCustomAccent = false;
    await _prefs.setInt(_kAccent, index);
    await _prefs.setBool(_kUseCustomAccent, false);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setWallpaperBlur(double value) async {
    wallpaperBlur = value.clamp(0, 1);
    await _prefs.setDouble(_kWallpaperBlur, wallpaperBlur);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setUiScale(double value) async {
    final next = (value * 100).round() / 100;
    final clamped = next.clamp(minUiScale, maxUiScale);
    if ((clamped - uiScale).abs() < 0.001) return;
    uiScale = clamped;
    await _prefs.setDouble(_kUiScale, uiScale);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> zoomIn() => setUiScale(uiScale + uiScaleStep);

  Future<void> zoomOut() => setUiScale(uiScale - uiScaleStep);

  Future<void> resetUiScale() => setUiScale(1.0);

  Future<void> pickWallpaper() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Permission.photos.request();
      } catch (_) {}
    }

    Uint8List? bytes;
    String ext = '.jpg';

    if (!kIsWeb && Platform.isAndroid) {
      try {
        const channel = MethodChannel('com.nullmp3.nullmp3/files');
        final data = await channel.invokeMethod<dynamic>('pickImage');
        if (data is Uint8List && data.isNotEmpty) {
          bytes = data;
        } else if (data is List<int> && data.isNotEmpty) {
          bytes = Uint8List.fromList(data);
        }
      } catch (_) {
        return;
      }
      if (bytes == null || bytes.isEmpty) return;
      if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) {
        ext = '.png';
      } else if (bytes.length >= 6 &&
          bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46) {
        ext = '.gif';
      } else if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[8] == 0x57) {
        ext = '.webp';
      } else {
        ext = '.jpg';
      }
    } else {
      final file = await FilePicker.pickFile(
        dialogTitle: S(language).chooseWallpaper,
        type: FileType.image,
        windowsOptions: const WindowsOptions(lockParentWindow: true),
      );
      if (file == null) return;
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return;
      bytes = Uint8List.fromList(raw);
      final name = file.name;
      final fromName = p.extension(name).toLowerCase();
      if (fromName.isNotEmpty) {
        ext = fromName;
      } else if (file.path != null && file.path!.isNotEmpty) {
        final fromPath = p.extension(file.path!).toLowerCase();
        if (fromPath.isNotEmpty) ext = fromPath;
      }
    }

    final root = await AppStorage.root();
    final fileName = 'theme_wallpaper$ext';
    final dest = File(p.join(root.path, fileName));
    await dest.writeAsBytes(bytes, flush: true);

    final previous = wallpaperPath;
    wallpaperPath = dest.path;
    wallpaperRevision++;
    await _prefs.setString(_kWallpaper, fileName);
    await setThemeId(AppThemeId.gallery);
    unawaited(_persistDurable());
    notifyListeners();

    if (previous != null && p.normalize(previous) != p.normalize(dest.path)) {
      try {
        final old = File(previous);
        final oldName = p.basename(old.path);
        if (await old.exists() && oldName != fileName) await old.delete();
      } catch (_) {}
    }
  }

  /// Resolve wallpaper in the durable root (Windows + Android).
  Future<void> _ensureWallpaperResolved() async {
    try {
      final root = await AppStorage.root();
      final stored = wallpaperPath;

      Future<bool> adopt(File file) async {
        if (!await file.exists()) return false;
        final name = p.basename(file.path);
        final stableName = _stableWallpaperName(name);
        var resolved = file;
        if (name != stableName || p.normalize(p.dirname(file.path)) != p.normalize(root.path)) {
          final dest = File(p.join(root.path, stableName));
          if (p.normalize(file.path) != p.normalize(dest.path)) {
            if (!await dest.exists()) {
              await dest.parent.create(recursive: true);
              await file.copy(dest.path);
            }
            resolved = dest;
          }
        }
        wallpaperPath = resolved.path;
        if (_prefs.getString(_kWallpaper) != stableName) {
          await _prefs.setString(_kWallpaper, stableName);
        }
        return true;
      }

      if (stored != null && stored.isNotEmpty) {
        final candidate = p.isAbsolute(stored)
            ? File(stored)
            : File(p.join(root.path, stored));
        if (await adopt(candidate)) return;
      }

      final found = await _findWallpaperFile(root);
      if (found != null && await adopt(found)) return;

      for (final legacyRoot in await AppStorage.legacyRoots()) {
        if (p.normalize(legacyRoot.path).toLowerCase() == p.normalize(root.path).toLowerCase()) {
          continue;
        }
        final legacy = await _findWallpaperFile(legacyRoot);
        if (legacy != null) await adopt(legacy);
        if (hasWallpaper) return;
      }
    } catch (_) {}
  }

  String _stableWallpaperName(String name) {
    final ext = p.extension(name);
    final safeExt = ext.isEmpty ? '.jpg' : ext;
    if (RegExp(r'^theme_wallpaper_\d+', caseSensitive: false).hasMatch(name)) {
      return 'theme_wallpaper$safeExt';
    }
    if (name.toLowerCase().startsWith('theme_wallpaper')) {
      return 'theme_wallpaper$safeExt';
    }
    return 'theme_wallpaper$safeExt';
  }

  Future<File?> _findWallpaperFile(Directory dir) async {
    if (!await dir.exists()) return null;
    File? best;
    var bestStamp = -1;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.toLowerCase().startsWith('theme_wallpaper')) continue;
      final match = RegExp(r'theme_wallpaper_(\d+)', caseSensitive: false).firstMatch(name);
      final stamp = match != null
          ? (int.tryParse(match.group(1)!) ?? 0)
          : 1 << 30; // fixed name wins over timestamped
      if (stamp >= bestStamp) {
        bestStamp = stamp;
        best = entity;
      }
    }
    return best;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await setThemeId(switch (mode) {
      ThemeMode.light => AppThemeId.light,
      ThemeMode.system => AppThemeId.system,
      ThemeMode.dark => AppThemeId.dark,
    });
  }

  Future<void> setMinDuration(int seconds) async {
    minDurationSec = seconds;
    await _prefs.setInt(_kMinDuration, seconds);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    await _prefs.setDouble(_kVolume, volume);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setSpeed(double value, {bool persist = true}) async {
    speed = value.clamp(0.5, 1.5);
    if (persist) {
      await _prefs.setDouble(_kSpeed, speed);
      unawaited(_persistDurable());
    }
    notifyListeners();
  }

  Future<void> setPitch(double value, {bool persist = true}) async {
    pitch = value.clamp(0.5, 1.5);
    if (persist) {
      await _prefs.setDouble(_kPitch, pitch);
      unawaited(_persistDurable());
    }
    notifyListeners();
  }

  Future<void> setBeatHalo(bool value) async {
    beatHalo = value;
    await _prefs.setBool(_kBeatHalo, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setBeatHaloMode(BeatHaloMode value) async {
    beatHaloMode = value;
    await _prefs.setString(_kBeatHaloMode, value.name);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setInteractiveCover(bool value) async {
    interactiveCover = value;
    await _prefs.setBool(_kInteractiveCover, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setInteractiveCoverMode(InteractiveCoverMode value) async {
    interactiveCoverMode = value;
    await _prefs.setString(_kInteractiveCoverMode, value.name);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setShowLyricsOnCover(bool value) async {
    showLyricsOnCover = value;
    await _prefs.setBool(_kShowLyricsOnCover, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setOfflineMode(bool value) async {
    offlineMode = value;
    NetworkGate.offline = value;
    await _prefs.setBool(_kOffline, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setStatsEnabled(bool value) async {
    statsEnabled = value;
    await _prefs.setBool(_kStatsEnabled, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setPauseFade(bool value) async {
    pauseFade = value;
    await _prefs.setBool(_kPauseFade, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setCrossfade(bool value) async {
    crossfade = value;
    await _prefs.setBool(_kCrossfade, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setContinuous(bool value) async {
    continuous = value;
    await _prefs.setBool(_kContinuous, value);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> setEq({required List<double> bands, required bool enabled, String? preset}) async {
    eqBands = List<double>.from(bands);
    eqEnabled = enabled;
    if (preset != null) eqPreset = preset;
    await _prefs.setString(_kEq, jsonEncode(eqBands));
    await _prefs.setBool(_kEqOn, eqEnabled);
    await _prefs.setString(_kEqPreset, eqPreset);
    unawaited(_persistDurable());
    notifyListeners();
  }

  Future<void> addFolder() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final picked = await const MethodChannel('com.nullmp3.nullmp3/files')
            .invokeMethod<String>('pickFolder')
            .timeout(const Duration(seconds: 120));
        if (picked != null && picked.isNotEmpty) {
          await addFolderPath(picked);
          return;
        }
      } catch (_) {}
    }
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    await addFolderPath(path);
  }

  Future<bool> addFolderPath(String path) async {
    final normalized = _normalizeFolder(path);
    if (normalized.isEmpty) return false;
    if (libraryFolders.any((folder) => _sameFolder(folder, normalized))) return false;
    libraryFolders = [...libraryFolders, normalized];
    await _saveLibraryFolders();
    notifyListeners();
    return true;
  }

  bool folderIsSelected(String path) {
    return libraryFolders.any((folder) => pathIsUnderRoots(path, [folder]));
  }

  static String _normalizeFolder(String path) {
    return path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  }

  static bool _sameFolder(String a, String b) {
    return _normalizeFolder(a).toLowerCase() == _normalizeFolder(b).toLowerCase();
  }

  static List<String> _uniqueFolders(List<String> folders) {
    final seen = <String>{};
    final result = <String>[];
    for (final folder in folders) {
      final normalized = _normalizeFolder(folder);
      final key = normalized.toLowerCase();
      if (normalized.isEmpty || !seen.add(key)) continue;
      result.add(normalized);
    }
    return result;
  }

  Future<void> _saveLibraryFolders() async {
    await _prefs.setString(_kLibraryFolders, jsonEncode(libraryFolders));
    await _prefs.setString(_kFolders, jsonEncode(libraryFolders));
    unawaited(_persistDurable());
  }

  Future<void> removeFolder(String path) async {
    libraryFolders = [
      for (final folder in libraryFolders)
        if (!_sameFolder(folder, path)) folder,
    ];
    await _saveLibraryFolders();
    notifyListeners();
  }

  Future<void> rememberFiles(List<String> paths) async {
    final next = <String>[...extraFiles];
    final keys = {for (final f in next) canonicalTrackPath(f)};
    for (final raw in paths) {
      final path = resolveTrackPath(raw);
      // Already covered by a scanned library folder — don't keep a second entry.
      if (libraryFolders.any((folder) => pathIsUnderRoots(path, [folder]))) continue;
      final key = canonicalTrackPath(path);
      if (!keys.add(key)) continue;
      next.add(path);
    }
    if (next.length == extraFiles.length && next.every(extraFiles.contains)) return;
    extraFiles = next;
    await _prefs.setString(_kExtraFiles, jsonEncode(extraFiles));
    notifyListeners();
  }

  Future<void> forgetFile(String path) async {
    extraFiles = [
      for (final f in extraFiles)
        if (!sameTrackPath(f, path)) f,
    ];
    await _prefs.setString(_kExtraFiles, jsonEncode(extraFiles));
    notifyListeners();
  }

  Future<List<String>> pickAudioFiles() async {
    final useAudioType = !kIsWeb && Platform.isAndroid;
    final result = await FilePicker.pickFiles(
      dialogTitle: S(language).selectSongs,
      type: useAudioType ? FileType.audio : FileType.custom,
      allowedExtensions: useAudioType
          ? null
          : const [
              'mp3',
              'm4a',
              'aac',
              'flac',
              'wav',
              'ogg',
              'opus',
              'wma',
              'aiff',
              'aif',
              'alac',
            ],
    );
    final paths = <String>{};
    for (final file in result) {
      final path = file.path ?? (file.uri.scheme == 'file' ? file.uri.toFilePath() : null);
      if (path == null || path.isEmpty) continue;
      final ext = p.extension(path).toLowerCase();
      if (ext.isNotEmpty && !audioExtensions.contains(ext)) continue;
      paths.add(path);
    }
    return paths.toList();
  }

  bool _askedAllFiles = false;

  Future<bool> requestMediaPermission() async {
    if (kIsWeb) return true;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return true;
    try {
      var status = await Permission.audio.status;
      if (!status.isGranted && !status.isLimited) {
        status = await Permission.audio.request().timeout(
          const Duration(seconds: 6),
          onTimeout: () => status,
        );
      }
      try {
        final video = await Permission.videos.status;
        if (!video.isGranted && !video.isLimited) {
          await Permission.videos.request().timeout(
            const Duration(seconds: 6),
            onTimeout: () => video,
          );
        }
      } catch (_) {}
      final allFiles = await Permission.manageExternalStorage.status;
      if (!allFiles.isGranted) {
        _askedAllFiles = true;
        await _prefs.setBool(_kAskedAllFiles, true);
        await Permission.manageExternalStorage.request().timeout(
          const Duration(seconds: 20),
          onTimeout: () => allFiles,
        );
      }
      if (status.isGranted || status.isLimited) return true;
      final storage = await Permission.storage.status;
      if (storage.isGranted || storage.isLimited) return true;
      final requested = await Permission.storage.request().timeout(
        const Duration(seconds: 6),
        onTimeout: () => storage,
      );
      return requested.isGranted || requested.isLimited;
    } catch (_) {
      return true;
    }
  }
}
