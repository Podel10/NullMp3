import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import 'audio_edit.dart';
import 'cover_image.dart';
import 'tag_write.dart';

Future<String> exportTrackForShare({
  required Track track,
  Uint8List? cover,
}) async {
  var source = track.path;
  if (!kIsWeb && Platform.isAndroid) {
    source = await materializeAudioFile(track.path);
  }

  final tmp = await getTemporaryDirectory();
  final dir = Directory(p.join(tmp.path, 'share'));
  if (!await dir.exists()) await dir.create(recursive: true);

  final ext = p.extension(track.path).isEmpty ? '.mp3' : p.extension(track.path);
  final dest = File(p.join(dir.path, '${_safeFileName(track.title, track.fileName)}$ext'));
  if (await dest.exists()) await dest.delete();
  await File(source).copy(dest.path);

  Uint8List? still;
  Uint8List? motion;
  if (cover != null) {
    if (isAnimatedCover(cover) && cover.lengthInBytes <= 8 * 1024 * 1024) {
      motion = cover;
    }
    still = await flattenCoverForEmbed(cover);
  }

  await compute(writeAudioTags, <String, Object?>{
    'path': dest.path,
    'title': track.title,
    'artist': track.artist,
    'album': track.album,
    'albumArtist': track.albumArtist ?? '',
    'composer': track.composer ?? '',
    'cover': still,
    'coverMime': still == null ? null : mimeOfImage(still),
    'motion': motion,
  });
  return dest.path;
}

String shareAudioMime(String path) {
  return switch (p.extension(path).toLowerCase()) {
    '.mp3' => 'audio/mpeg',
    '.m4a' || '.aac' || '.mp4' => 'audio/mp4',
    '.flac' => 'audio/flac',
    '.wav' => 'audio/wav',
    '.ogg' || '.opus' => 'audio/ogg',
    _ => 'audio/*',
  };
}

String _safeFileName(String title, String fallback) {
  var name = title.trim();
  if (name.isEmpty) name = fallback;
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.isEmpty) return 'track';
  if (name.length > 80) name = name.substring(0, 80).trim();
  return name;
}
