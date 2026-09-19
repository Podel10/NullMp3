import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cover_image.dart';
import 'file_actions.dart';
import 'network.dart';
import 'tag_write.dart';

const _kAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
const _kMaxBytes = 250 * 1024 * 1024;
const _kMaxPlaylist = 50;

bool get webAudioSupported => !kIsWeb;

enum WebAudioKind { soundcloud }

class WebAudioLink {
  const WebAudioLink({
    required this.kind,
    required this.url,
  });

  final WebAudioKind kind;
  final String url;
}

class WebAudioFile {
  const WebAudioFile({
    required this.path,
    required this.title,
    required this.artist,
    this.cover,
  });

  final String path;
  final String title;
  final String artist;
  final Uint8List? cover;
}

class WebAudioProgress {
  const WebAudioProgress({
    required this.title,
    required this.index,
    required this.total,
    this.fraction,
    this.stage = 'download',
  });

  final String title;
  final int index;
  final int total;
  final double? fraction;
  final String stage;
}

class WebAudioException implements Exception {
  const WebAudioException(this.code);
  final String code;

  @override
  String toString() => 'WebAudioException($code)';
}

WebAudioLink? parseWebAudioUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final direct = _parseWebAudioUrl(text);
  if (direct != null) return direct;
  final matches = RegExp(r'(?:https?://|www\.)[^\s<>]+', caseSensitive: false).allMatches(text);
  for (final match in matches) {
    final found = match.group(0);
    if (found == null) continue;
    final parsed = _parseWebAudioUrl(found.replaceAll(RegExp(r'[),.;]+$'), ''));
    if (parsed != null) return parsed;
  }
  return null;
}

WebAudioLink? _parseWebAudioUrl(String text) {
  final uri = _asUri(text);
  if (uri == null || uri.host.isEmpty) return null;
  var host = uri.host.toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);

  if (host == 'soundcloud.com' || host.endsWith('.soundcloud.com') || host == 'on.soundcloud.com') {
    if (uri.pathSegments.where((part) => part.isNotEmpty).isEmpty) return null;
    return WebAudioLink(kind: WebAudioKind.soundcloud, url: uri.toString());
  }
  return null;
}

Future<Directory> webAudioOutputDir() async {
  if (!kIsWeb && Platform.isAndroid) {
    final music = Directory('/storage/emulated/0/Music/NullMP3');
    if (await _canWrite(music)) return music;
  }
  if (!kIsWeb && Platform.isWindows) {
    final home = Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final music = Directory(p.join(home, 'Music', 'NullMP3'));
      if (await _canWrite(music)) return music;
    }
  }
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'NullMP3'));
  await dir.create(recursive: true);
  return dir;
}

typedef WebAudioProgressCb = void Function(WebAudioProgress progress);

Future<List<WebAudioFile>> downloadWebAudio(
  String raw, {
  WebAudioProgressCb? onProgress,
  bool Function()? isCancelled,
}) {
  return _WebAudioJob(onProgress: onProgress, isCancelled: isCancelled).run(raw);
}

class _WebAudioJob {
  _WebAudioJob({this.onProgress, this.isCancelled});

  final WebAudioProgressCb? onProgress;
  final bool Function()? isCancelled;

  final HttpClient _client = HttpClient()
    ..userAgent = _kAgent
    ..connectionTimeout = const Duration(seconds: 20);
  static String? _soundClientId;

  bool get _stop => isCancelled?.call() == true;

  void _throwIfStop() {
    if (_stop) throw const WebAudioException('cancelled');
  }

  Future<List<WebAudioFile>> run(String raw) async {
    try {
      NetworkGate.requireOnline();
      final link = parseWebAudioUrl(raw);
      if (link == null) throw const WebAudioException('badUrl');
      final dir = await webAudioOutputDir();
      return await _soundCloud(link.url, dir);
    } on WebAudioException {
      rethrow;
    } on SocketException {
      throw const WebAudioException('offline');
    } catch (error, stack) {
      debugPrint('webAudio failed: $error\n$stack');
      throw const WebAudioException('failed');
    } finally {
      _client.close(force: true);
    }
  }

  Future<List<WebAudioFile>> _soundCloud(String url, Directory dir) async {
    onProgress?.call(const WebAudioProgress(title: 'SoundCloud', index: 1, total: 1, stage: 'resolve'));
    final resolved = await _resolveSoundCloud(url);
    final kind = (resolved['kind'] as String? ?? '').toLowerCase();
    if (kind == 'playlist' || kind == 'system-playlist') {
      return _soundCloudPlaylist(resolved, dir);
    }
    if (kind != 'track') throw const WebAudioException('failed');
    return [await _soundCloudTrack(resolved, dir, index: 1, total: 1)];
  }

  Future<List<WebAudioFile>> _soundCloudPlaylist(Map<String, dynamic> playlist, Directory dir) async {
    var tracks = _asMaps(playlist['tracks']);
    final missing = [
      for (final track in tracks)
        if (track['media'] == null && track['id'] != null) '${track['id']}',
    ];
    if (missing.isNotEmpty) {
      final fetched = {
        for (final track in await _soundCloudTracksById(missing)) '${track['id']}': track,
      };
      tracks = [
        for (final track in tracks) fetched['${track['id']}'] ?? track,
      ];
    }
    if (tracks.isEmpty) throw const WebAudioException('failed');
    if (tracks.length > _kMaxPlaylist) tracks = tracks.take(_kMaxPlaylist).toList();
    final out = <WebAudioFile>[];
    for (var i = 0; i < tracks.length; i++) {
      _throwIfStop();
      try {
        out.add(await _soundCloudTrack(tracks[i], dir, index: i + 1, total: tracks.length));
      } on WebAudioException catch (error) {
        if (error.code == 'cancelled') rethrow;
      } catch (_) {}
    }
    if (out.isEmpty) throw const WebAudioException('failed');
    return out;
  }

  Future<WebAudioFile> _soundCloudTrack(
    Map<String, dynamic> track,
    Directory dir, {
    required int index,
    required int total,
  }) async {
    _throwIfStop();
    final title = (track['title'] as String?)?.trim();
    if (title == null || title.isEmpty) throw const WebAudioException('failed');
    final user = track['user'];
    final artist = user is Map
        ? ((user['username'] as String?)?.trim().isNotEmpty == true
            ? (user['username'] as String).trim()
            : (user['permalink'] as String?)?.trim() ?? 'SoundCloud')
        : 'SoundCloud';
    const album = 'SoundCloud';
    onProgress?.call(WebAudioProgress(title: title, index: index, total: total, stage: 'resolve'));

    final media = track['media'];
    final transcodings = media is Map ? media['transcodings'] : track['transcodings'];
    final picked = _pickSoundCloudTranscoding(transcodings);
    if (picked == null) throw const WebAudioException('failed');
    final stream = await _soundCloudStream(picked);
    if (stream == null) throw const WebAudioException('failed');

    final dest = await _uniqueFile(dir, _fileStem(artist, title), stream.ext);
    onProgress?.call(WebAudioProgress(title: title, index: index, total: total, fraction: 0));
    if (stream.hls) {
      await _downloadHls(stream.url!, dest);
    } else {
      await _downloadUrl(
        stream.url!,
        dest,
        referer: 'https://soundcloud.com/',
        onBytes: (got, totalBytes) => onProgress?.call(
          WebAudioProgress(
            title: title,
            index: index,
            total: total,
            fraction: totalBytes == null || totalBytes <= 0 ? null : (got / totalBytes).clamp(0.0, 1.0),
          ),
        ),
      );
    }

    final path = await _renameByMagic(dest);
    final cover = await _coverBytes(_soundArtwork(track['artwork_url'] as String?));
    onProgress?.call(WebAudioProgress(title: title, index: index, total: total, stage: 'tag'));
    await _tagFile(path, title: title, artist: artist, album: album, cover: cover);
    return WebAudioFile(path: path, title: title, artist: artist, cover: cover);
  }

  Future<Map<String, dynamic>> _resolveSoundCloud(String url) async {
    final clientId = await _soundCloudClientId();
    var target = url;
    final host = Uri.parse(url).host.toLowerCase();
    if (host.contains('on.soundcloud.com') || host.startsWith('m.soundcloud')) {
      target = await _expandSoundCloud(url) ?? url;
    }
    final uri = Uri.https('api-v2.soundcloud.com', '/resolve', {
      'url': target,
      'client_id': clientId,
    });
    final data = await _getJson(uri);
    if (data is! Map) throw const WebAudioException('failed');
    return Map<String, dynamic>.from(data);
  }

  Future<String?> _expandSoundCloud(String url) async {
    try {
      final request = await _client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.headers.set(HttpHeaders.userAgentHeader, _kAgent);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decodeStream(response);
      final canonical = RegExp(
        r'https://soundcloud\.com/[A-Za-z0-9_\-./]+',
      ).firstMatch(body)?.group(0);
      if (canonical != null) return canonical.split('?').first;
      if (response.redirects.isNotEmpty) {
        return response.redirects.last.location.toString();
      }
    } catch (_) {}
    return null;
  }

  Future<String> _soundCloudClientId() async {
    if (_soundClientId != null) return _soundClientId!;
    final pages = [
      'https://soundcloud.com',
      'https://soundcloud.com/discover',
    ];
    for (final page in pages) {
      _throwIfStop();
      final home = await _getString(Uri.parse(page));
      if (home == null || home.isEmpty) continue;
      final fromPage = _findSoundCloudClientId(home);
      if (fromPage != null) {
        _soundClientId = fromPage;
        return fromPage;
      }
      final scripts = [
        ...RegExp(r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+)"').allMatches(home).map((m) => m.group(1)!),
        ...RegExp(r"src='(https://a-v2\.sndcdn\.com/assets/[^']+)'").allMatches(home).map((m) => m.group(1)!),
      ];
      for (final script in scripts.reversed) {
        _throwIfStop();
        final js = await _getString(Uri.parse(script));
        if (js == null) continue;
        final id = _findSoundCloudClientId(js);
        if (id != null) {
          _soundClientId = id;
          return id;
        }
      }
    }
    throw const WebAudioException('failed');
  }

  Future<List<Map<String, dynamic>>> _soundCloudTracksById(List<String> ids) async {
    final clientId = await _soundCloudClientId();
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 10) {
      _throwIfStop();
      final slice = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final uri = Uri.https('api-v2.soundcloud.com', '/tracks', {
        'ids': slice.join(','),
        'client_id': clientId,
      });
      final data = await _getJson(uri);
      if (data is List) {
        out.addAll(_asMaps(data));
      }
    }
    return out;
  }

  Map<String, dynamic>? _pickSoundCloudTranscoding(Object? raw) {
    if (raw is! List) return null;
    Map<String, dynamic>? progressiveMp3;
    Map<String, dynamic>? hlsMp3;
    Map<String, dynamic>? progressive;
    Map<String, dynamic>? hls;
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final format = row['format'];
      if (format is! Map) continue;
      final protocol = '${format['protocol'] ?? ''}'.toLowerCase();
      final mime = '${format['mime_type'] ?? ''}'.toLowerCase();
      final mp3 = mime.contains('mpeg') || mime.contains('mp3');
      final hq = '${row['quality'] ?? ''}' == 'hq';
      if (protocol == 'progressive' && mp3) {
        if (progressiveMp3 == null || hq) progressiveMp3 = row;
      } else if (protocol.contains('hls') && mp3) {
        hlsMp3 ??= row;
      } else if (protocol == 'progressive') {
        progressive ??= row;
      } else if (protocol.contains('hls')) {
        hls ??= row;
      }
    }
    return progressiveMp3 ?? hlsMp3 ?? progressive ?? hls;
  }

  Future<_AudioSource?> _soundCloudStream(Map<String, dynamic> transcoding) async {
    final rawUrl = (transcoding['url'] as String?)?.trim();
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final clientId = await _soundCloudClientId();
    final lookup = Uri.parse(rawUrl).replace(
      queryParameters: {
        ...Uri.parse(rawUrl).queryParameters,
        'client_id': clientId,
      },
    );
    final data = await _getJson(lookup);
    if (data is! Map) return null;
    final url = (data['url'] as String?)?.trim();
    if (url == null || url.isEmpty) return null;
    final format = transcoding['format'];
    final protocol = format is Map ? '${format['protocol'] ?? ''}'.toLowerCase() : '';
    final mime = format is Map ? '${format['mime_type'] ?? ''}'.toLowerCase() : '';
    final ext = mime.contains('ogg') || mime.contains('opus')
        ? '.ogg'
        : mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')
            ? '.m4a'
            : '.mp3';
    return _AudioSource(url: Uri.parse(url), ext: ext, hls: protocol.contains('hls'));
  }

  Future<void> _downloadHls(Uri playlist, File dest) async {
    const referer = 'https://soundcloud.com/';
    var current = playlist;
    var body = await _getString(current, referer: referer);
    if (body == null || body.isEmpty) throw const WebAudioException('failed');
    var playlistBody = body;
    if (playlistBody.contains('#EXT-X-STREAM-INF')) {
      for (final line in playlistBody.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        current = current.resolve(trimmed);
        final nested = await _getString(current, referer: referer);
        if (nested == null || nested.isEmpty) throw const WebAudioException('failed');
        playlistBody = nested;
        break;
      }
    }
    final lines = playlistBody.split(RegExp(r'\r?\n'));
    final parts = <Uri>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      parts.add(current.resolve(trimmed));
    }
    if (parts.isEmpty) throw const WebAudioException('failed');
    final tmp = File('${dest.path}.part');
    if (await tmp.exists()) await tmp.delete();
    final sink = tmp.openWrite();
    var got = 0;
    try {
      for (var i = 0; i < parts.length; i++) {
        _throwIfStop();
        final bytes = await _getBytes(parts[i], referer: referer);
        if (bytes == null || bytes.isEmpty) continue;
        got += bytes.length;
        if (got > _kMaxBytes) throw const WebAudioException('failed');
        sink.add(bytes);
        onProgress?.call(
          WebAudioProgress(
            title: p.basenameWithoutExtension(dest.path),
            index: 1,
            total: 1,
            fraction: ((i + 1) / parts.length).clamp(0.0, 1.0),
          ),
        );
      }
      await sink.flush();
      await sink.close();
      if (got <= 0) throw const WebAudioException('failed');
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
    } catch (error) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _downloadUrl(
    Uri uri,
    File dest, {
    String? referer,
    void Function(int got, int? total)? onBytes,
  }) async {
    final tmp = File('${dest.path}.part');
    if (await tmp.exists()) await tmp.delete();
    final request = await _client.getUrl(uri);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.userAgentHeader, _kAgent);
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer);
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw const WebAudioException('failed');
    }
    final total = response.contentLength;
    final sink = tmp.openWrite();
    var got = 0;
    try {
      await for (final chunk in response) {
        _throwIfStop();
        got += chunk.length;
        if (got > _kMaxBytes) throw const WebAudioException('failed');
        sink.add(chunk);
        onBytes?.call(got, total >= 0 ? total : null);
      }
      await sink.flush();
      await sink.close();
      if (got <= 0) throw const WebAudioException('failed');
      if (await dest.exists()) await dest.delete();
      await tmp.rename(dest.path);
    } catch (error) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<Object?> _getJson(Uri uri) async {
    final body = await _getString(uri);
    if (body == null || body.isEmpty) return null;
    return jsonDecode(body);
  }

  Future<String?> _getString(Uri uri, {String? referer}) async {
    final bytes = await _getBytes(uri, referer: referer);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<Uint8List?> _getBytes(Uri uri, {String? referer}) async {
    NetworkGate.requireOnline();
    _throwIfStop();
    final request = await _client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.followRedirects = true;
    request.headers.set(HttpHeaders.userAgentHeader, _kAgent);
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (referer != null) request.headers.set(HttpHeaders.refererHeader, referer);
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > _kMaxBytes) return null;
    }
    return builder.takeBytes();
  }

  Future<Uint8List?> _coverBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final bytes = await _getBytes(Uri.parse(url));
      if (bytes == null || bytes.length < 32) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _tagFile(
    String path, {
    required String title,
    required String artist,
    required String album,
    Uint8List? cover,
  }) async {
    try {
      Uint8List? still;
      if (cover != null) {
        still = await flattenCoverForEmbed(cover);
      }
      await compute(writeAudioTags, <String, Object?>{
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'albumArtist': artist,
        'composer': '',
        'cover': still,
        'coverMime': still == null ? null : mimeOfImage(still),
      });
    } catch (_) {}
  }
}

class _AudioSource {
  const _AudioSource({this.url, required this.ext, this.hls = false});

  final Uri? url;
  final String ext;
  final bool hls;
}

String? _findSoundCloudClientId(String source) {
  return RegExp('client_id["\\s:=]+["\']([A-Za-z0-9]{16,})["\']').firstMatch(source)?.group(1) ??
      RegExp(r'client_id=([A-Za-z0-9]{16,})').firstMatch(source)?.group(1);
}

Future<String> _renameByMagic(File dest) async {
  var path = dest.path;
  final magicExt = await _extFromFile(File(path));
  if (magicExt == null || magicExt == p.extension(path).toLowerCase()) return path;
  final renamed = File(p.setExtension(path, magicExt));
  if (renamed.path == path) return path;
  if (await renamed.exists()) await renamed.delete();
  await File(path).rename(renamed.path);
  return renamed.path;
}

Uri? _asUri(String text) {
  try {
    var value = text.trim();
    if (!value.contains('://')) {
      value = value.startsWith('//') ? 'https:$value' : 'https://$value';
    }
    final uri = Uri.parse(value);
    if (uri.host.isEmpty) return null;
    return uri;
  } catch (_) {
    return null;
  }
}

String _fileStem(String artist, String title) {
  final left = safeAudioFileName(artist);
  final right = safeAudioFileName(title);
  if (left.isEmpty || left.toLowerCase() == 'soundcloud') {
    return right.isEmpty ? 'track' : right;
  }
  if (right.toLowerCase().startsWith(left.toLowerCase())) return right;
  final combined = safeAudioFileName('$left - $right');
  return combined.isEmpty ? 'track' : combined;
}

Future<File> _uniqueFile(Directory dir, String stem, String ext) async {
  var dest = File(p.join(dir.path, '$stem$ext'));
  var n = 1;
  while (await dest.exists()) {
    dest = File(p.join(dir.path, '$stem ($n)$ext'));
    n++;
  }
  return dest;
}

Future<bool> _canWrite(Directory dir) async {
  try {
    if (!await dir.exists()) await dir.create(recursive: true);
    final probe = File(p.join(dir.path, '.nullmp3_write'));
    await probe.writeAsString('ok');
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> _extFromFile(File file) async {
  try {
    final raf = await file.open();
    final head = await raf.read(16);
    await raf.close();
    if (head.length >= 3 && head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) return '.mp3';
    if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) return '.mp3';
    if (head.length >= 8 && String.fromCharCodes(head.sublist(4, 8)) == 'ftyp') return '.m4a';
    if (head.length >= 4 && String.fromCharCodes(head.sublist(0, 4)) == 'OggS') return '.ogg';
    if (head.length >= 4 && head[0] == 0x1A && head[1] == 0x45) return '.opus';
  } catch (_) {}
  return null;
}

String? _soundArtwork(String? url) {
  if (url == null || url.isEmpty) return null;
  return url.replaceAll('-large', '-t500x500').replaceAll('-badge', '-t500x500');
}

List<Map<String, dynamic>> _asMaps(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}
