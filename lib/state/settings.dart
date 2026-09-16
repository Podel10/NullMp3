import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/network.dart';
import '../data/scanner.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

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
  static const _kOffline = 'offlineMode';

  late SharedPreferences _prefs;

  ThemeMode themeMode = ThemeMode.dark;
  AppThemeId themeId = AppThemeId.dark;
  int accentIndex = 0;
  Color customBackground = const Color(0xFF1B1428);
  Color customAccent = const Color(0xFFFFC933);
  bool useCustomAccent = false;
  String? wallpaperPath;
  double wallpaperBlur = 0.45;
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
    _prefs = await SharedPreferences.getInstance();
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
    offlineMode = _prefs.getBool(_kOffline) ?? false;
    NetworkGate.offline = offlineMode;
    eqEnabled = _prefs.getBool(_kEqOn) ?? true;
    eqPreset = _prefs.getString(_kEqPreset) ?? 'Normal';
    language = AppLanguage.fromName(_prefs.getString(_kLanguage));
    final storedEq = _prefs.getString(_kEq);
    if (storedEq != null) {
      eqBands = List<double>.from((jsonDecode(storedEq) as List).map((e) => (e as num).toDouble()));
      if (eqBands.length < 5) {
        eqBands = [...eqBands, ...List<double>.filled(5 - eqBands.length, 0)];
      }
    }
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage value) async {
    language = value;
    await _prefs.setString(_kLanguage, value.name);
    notifyListeners();
  }

  Future<void> setThemeId(AppThemeId id) async {
    themeId = id;
    themeMode = _modeFor(id);
    await _prefs.setString(_kThemeId, id.name);
    await _prefs.setInt(_kTheme, themeMode.index);
    notifyListeners();
  }

  Future<void> setCustomBackground(Color color) async {
    customBackground = color;
    if (themeId == AppThemeId.custom) {
      themeMode = _modeFor(AppThemeId.custom);
      await _prefs.setInt(_kTheme, themeMode.index);
    }
    await _prefs.setInt(_kCustomBg, color.toARGB32());
    notifyListeners();
  }

  Future<void> setCustomAccent(Color color) async {
    customAccent = color;
    useCustomAccent = true;
    await _prefs.setInt(_kCustomAccent, color.toARGB32());
    await _prefs.setBool(_kUseCustomAccent, true);
    notifyListeners();
  }

  Future<void> setAccent(int index) async {
    accentIndex = index;
    useCustomAccent = false;
    await _prefs.setInt(_kAccent, index);
    await _prefs.setBool(_kUseCustomAccent, false);
    notifyListeners();
  }

  Future<void> setWallpaperBlur(double value) async {
    wallpaperBlur = value.clamp(0, 1);
    await _prefs.setDouble(_kWallpaperBlur, wallpaperBlur);
    notifyListeners();
  }

  Future<void> pickWallpaper() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await Permission.photos.request();
      } catch (_) {}
    }
    final result = await FilePicker.pickFiles(
      dialogTitle: S(language).chooseWallpaper,
      type: FileType.image,
    );
    String? source;
    for (final file in result) {
      source = file.path ?? (file.uri.scheme == 'file' ? file.uri.toFilePath() : null);
      if (source != null && source.isNotEmpty) break;
    }
    if (source == null) return;
    final support = await getApplicationSupportDirectory();
    final dest = File(p.join(support.path, 'theme_wallpaper${p.extension(source)}'));
    await File(source).copy(dest.path);
    wallpaperPath = dest.path;
    await _prefs.setString(_kWallpaper, dest.path);
    await setThemeId(AppThemeId.gallery);
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
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    volume = value.clamp(0, 1);
    await _prefs.setDouble(_kVolume, volume);
    notifyListeners();
  }

  Future<void> setSpeed(double value, {bool persist = true}) async {
    speed = value.clamp(0.5, 1.5);
    if (persist) await _prefs.setDouble(_kSpeed, speed);
    notifyListeners();
  }

  Future<void> setPitch(double value, {bool persist = true}) async {
    pitch = value.clamp(0.5, 1.5);
    if (persist) await _prefs.setDouble(_kPitch, pitch);
    notifyListeners();
  }

  Future<void> setBeatHalo(bool value) async {
    beatHalo = value;
    await _prefs.setBool(_kBeatHalo, value);
    notifyListeners();
  }

  Future<void> setOfflineMode(bool value) async {
    offlineMode = value;
    NetworkGate.offline = value;
    await _prefs.setBool(_kOffline, value);
    notifyListeners();
  }

  Future<void> setStatsEnabled(bool value) async {
    statsEnabled = value;
    await _prefs.setBool(_kStatsEnabled, value);
    notifyListeners();
  }

  Future<void> setPauseFade(bool value) async {
    pauseFade = value;
    await _prefs.setBool(_kPauseFade, value);
    notifyListeners();
  }

  Future<void> setCrossfade(bool value) async {
    crossfade = value;
    await _prefs.setBool(_kCrossfade, value);
    notifyListeners();
  }

  Future<void> setContinuous(bool value) async {
    continuous = value;
    await _prefs.setBool(_kContinuous, value);
    notifyListeners();
  }

  Future<void> setEq({required List<double> bands, required bool enabled, String? preset}) async {
    eqBands = List<double>.from(bands);
    eqEnabled = enabled;
    if (preset != null) eqPreset = preset;
    await _prefs.setString(_kEq, jsonEncode(eqBands));
    await _prefs.setBool(_kEqOn, eqEnabled);
    await _prefs.setString(_kEqPreset, eqPreset);
    notifyListeners();
  }

  Future<void> addFolder() async {
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
    extraFiles = {...extraFiles, ...paths}.toList();
    await _prefs.setString(_kExtraFiles, jsonEncode(extraFiles));
    notifyListeners();
  }

  Future<void> forgetFile(String path) async {
    extraFiles = extraFiles.where((f) => f != path).toList();
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
      var status = await Permission.audio.request();
      if (!_askedAllFiles) {
        _askedAllFiles = true;
        final allFiles = await Permission.manageExternalStorage.status;
        if (!allFiles.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      }
      if (status.isGranted || status.isLimited) return true;
      status = await Permission.storage.request();
      return status.isGranted || status.isLimited;
    } catch (_) {
      return true;
    }
  }
}
