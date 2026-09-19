import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'scanner.dart';

const _filesChannel = MethodChannel('com.nullmp3.nullmp3/files');

class DeviceAudioFolder {
  const DeviceAudioFolder({required this.path, required this.count});

  final String path;
  final int count;

  String get name {
    final parts = path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[parts.length - 2]}/${parts.last}';
    return parts.isEmpty ? path : parts.last;
  }
}

Future<List<DeviceAudioFolder>> queryDeviceAudioFolders() async {
  if (kIsWeb || !Platform.isAndroid) return const [];
  try {
    final raw = await _filesChannel.invokeMethod<List<dynamic>>('listAudioFolders');
    if (raw == null) return const [];
    final folders = <DeviceAudioFolder>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final path = item['path'] as String?;
      final count = (item['count'] as num?)?.toInt() ?? 0;
      if (path == null || path.isEmpty || count <= 0) continue;
      folders.add(DeviceAudioFolder(path: path.replaceAll(RegExp(r'/+$'), ''), count: count));
    }
    folders.sort((a, b) => b.count.compareTo(a.count));
    return folders;
  } catch (_) {
    return const [];
  }
}

Future<List<Track>> queryDeviceAudio({List<String> folders = const []}) async {
  if (kIsWeb || !Platform.isAndroid) return const [];
  try {
    final raw = await _filesChannel.invokeMethod<List<dynamic>>(
      'listAudio',
      {'folders': folders},
    );
    if (raw == null) return const [];
    final tracks = <Track>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final track = trackFromMediaMap(item);
      if (track == null) continue;
      if (folders.isNotEmpty && !pathIsUnderRoots(track.path, folders)) continue;
      tracks.add(track);
    }
    return tracks;
  } catch (_) {
    return const [];
  }
}
