import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';

const audioExtensions = {
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
  '.aiff',
  '.aif',
  '.alac',
  '.mp4',
  '.m4v',
  '.webm',
  '.mkv',
  '.3gp',
};

const _skipScanDirs = {
  'alarms',
  'notifications',
  'ringtones',
  'recordings',
  'telegram audio',
  'callrecorder',
  '.thumbnails',
  '.trash',
  '.cache',
};

List<String> defaultDownloadRoots() {
  return const [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Downloads',
  ];
}

List<String> defaultTelegramRoots() {
  return const [
    '/storage/emulated/0/Music/Telegram',
    '/storage/emulated/0/Telegram',
    '/storage/emulated/0/Download/Telegram',
    '/storage/emulated/0/Downloads/Telegram',
    '/storage/emulated/0/Android/media/org.telegram.messenger/Telegram',
    '/storage/emulated/0/Android/media/org.telegram.messenger.web/Telegram',
    '/storage/emulated/0/Android/media/org.thunderdog.challegram/Telegram',
  ];
}

List<String> defaultMusicRoots() {
  if (kIsWeb) return const [];
  if (Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'] ?? '';
    return [
      p.join(home, 'Music'),
      p.join(home, 'Documents', 'Music'),
    ];
  }
  if (Platform.isAndroid) {
    return [
      ...defaultDownloadRoots(),
      '/storage/emulated/0/Music/Telegram',
    ];
  }
  final home = Platform.environment['HOME'] ?? '';
  return [p.join(home, 'Music')];
}

List<String> listAudioFiles(List<String> roots) {
  final files = <String>{};
  for (final root in roots) {
    try {
      _collectAudioFiles(Directory(root), files);
    } catch (_) {}
  }
  final sorted = files.map(resolveTrackPath).toSet().toList()..sort();
  return sorted;
}

void _collectAudioFiles(Directory dir, Set<String> files) {
  try {
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is Directory) {
        final name = p.basename(entity.path).toLowerCase();
        if (_skipScanDirs.contains(name)) continue;
        _collectAudioFiles(entity, files);
      } else if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (audioExtensions.contains(ext)) files.add(entity.path);
      }
    }
  } catch (_) {}
}

bool isTelegramLibraryPath(String path, {String? relative}) {
  final normalized = canonicalTrackPath(path);
  if (normalized.contains('/telegram/') || normalized.endsWith('/telegram')) return true;
  final rel = (relative ?? '').replaceAll('\\', '/').toLowerCase();
  return rel.contains('telegram');
}

bool pathIsUnderRoots(String path, List<String> roots) {
  if (roots.isEmpty) return false;
  final normalized = canonicalTrackPath(path);
  for (final root in roots) {
    final prefix = canonicalTrackPath(root).replaceAll(RegExp(r'/+$'), '');
    if (normalized == prefix || normalized.startsWith('$prefix/')) return true;
  }
  return false;
}

/// Stable identity for a file path across `/` vs `\` and drive-letter case.
String canonicalTrackPath(String path) {
  var normalized = p.normalize(path).replaceAll('\\', '/').toLowerCase();
  const aliases = [
    '/storage/self/primary',
    '/storage/emulated/0',
    '/mnt/user/0/primary',
    '/mnt/sdcard',
    '/sdcard',
  ];
  for (final alias in aliases) {
    if (normalized == alias || normalized.startsWith('$alias/')) {
      normalized = normalized.replaceFirst(alias, '/storage/emulated/0');
      break;
    }
  }
  return normalized;
}

bool sameTrackPath(String a, String b) => canonicalTrackPath(a) == canonicalTrackPath(b);

/// Prefer the OS-native absolute path so Downloads imports and folder scans match.
String resolveTrackPath(String path) {
  try {
    return File(path).absolute.path;
  } catch (_) {
    return path;
  }
}

List<Track> parseAudioFiles(List<String> paths) {
  return [for (final path in paths) parseAudioFile(path)];
}

Track parseAudioFile(String path) {
  final fallback = p.basenameWithoutExtension(path);
  var title = fallback;
  var artist = 'Unknown artist';
  var album = 'Unknown album';
  var genre = 'Unknown';
  var durationMs = 0;
  int? year;
  int? trackNumber;
  var modifiedMs = 0;

  try {
    modifiedMs = File(path).lastModifiedSync().millisecondsSinceEpoch;
  } catch (_) {}

  try {
    final meta = readMetadata(File(path), getImage: false);
    if (meta.title != null && meta.title!.trim().isNotEmpty) {
      title = _visibleTitle(meta.title!.trim(), fallback);
    }
    if (meta.artist != null && meta.artist!.trim().isNotEmpty) {
      artist = meta.artist!.trim();
    } else if (meta.performers.isNotEmpty) {
      artist = meta.performers.first.trim();
    }
    if (meta.album != null && meta.album!.trim().isNotEmpty) {
      album = meta.album!.trim();
    }
    if (meta.genres.isNotEmpty && meta.genres.first.trim().isNotEmpty) {
      genre = meta.genres.first.trim();
    }
    durationMs = meta.duration?.inMilliseconds ?? 0;
    year = meta.year?.year;
    trackNumber = meta.trackNumber;
  } catch (_) {
    final dash = fallback.split(' - ');
    if (dash.length >= 2) {
      artist = dash.first.trim();
      title = dash.sublist(1).join(' - ').trim();
    }
  }

  return Track(
    path: path,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    durationMs: durationMs,
    modifiedMs: modifiedMs,
    year: year,
    trackNumber: trackNumber,
  );
}

Track trackFromPathFast(String path, {int modifiedMs = 0, int durationMs = 0}) {
  final fallback = p.basenameWithoutExtension(path);
  var title = fallback;
  var artist = 'Unknown artist';
  final dash = fallback.split(' - ');
  if (dash.length >= 2) {
    artist = dash.first.trim();
    title = dash.sublist(1).join(' - ').trim();
  }
  return Track(
    path: path,
    title: title,
    artist: artist,
    album: 'Unknown album',
    genre: 'Unknown',
    durationMs: durationMs,
    modifiedMs: modifiedMs,
  );
}

Track? trackFromMediaMap(Map<dynamic, dynamic> map) {
  final path = map['path'] as String?;
  if (path == null || path.isEmpty) return null;
  final artist = (map['artist'] as String?)?.trim();
  final album = (map['album'] as String?)?.trim();
  final title = (map['title'] as String?)?.trim();
  final fileName = p.basenameWithoutExtension(path);
  final unknownArtist = artist == null || artist.isEmpty || artist.toLowerCase() == '<unknown>';
  final unknownAlbum = album == null || album.isEmpty || album.toLowerCase() == '<unknown>';
  final uri = (map['uri'] as String?)?.trim();
  return Track(
    path: path,
    title: _visibleTitle(title, fileName),
    artist: unknownArtist ? 'Unknown artist' : artist,
    album: unknownAlbum ? 'Unknown album' : album,
    genre: 'Unknown',
    durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    modifiedMs: (map['modifiedMs'] as num?)?.toInt() ?? 0,
    year: (map['year'] as num?)?.toInt(),
    trackNumber: (map['trackNumber'] as num?)?.toInt(),
    uri: uri == null || uri.isEmpty ? null : uri,
  );
}

bool titleNeedsTagRead(String title) {
  final t = title.trim();
  if (t.isEmpty) return true;
  if (t.contains('+') && !t.contains(' ')) return true;
  if (RegExp(r'^2_\d{6,}').hasMatch(t)) return true;
  if (RegExp(r'^[a-zA-Z0-9_-]{16,}$').hasMatch(t)) return true;
  return false;
}

bool pathLooksLikeTelegram(String path) {
  return path.replaceAll('\\', '/').toLowerCase().contains('/telegram/');
}

String _visibleTitle(String? title, String fileName) {
  final media = title?.trim() ?? '';
  if (media.isEmpty || media.toLowerCase() == '<unknown>') return fileName;
  if (fileName.toLowerCase().contains(media.toLowerCase()) && fileName.length > media.length + 2) {
    return fileName;
  }
  return media;
}
