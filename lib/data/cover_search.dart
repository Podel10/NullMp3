import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/models.dart';
import 'network.dart';

const _kAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

/// Animated covers are kept whole, so this has to fit a small GIF.
const _kMaxCoverBytes = 8 * 1024 * 1024;

enum CoverSearchKind { art, image, gif }

class CoverCandidate {
  const CoverCandidate({
    required this.previewUrl,
    required this.fullUrl,
    required this.source,
    required this.label,
  });

  final String previewUrl;
  final String fullUrl;
  final String source;
  final String label;
}

String coverSearchQuery(Track track) {
  var artist = track.artist.trim();
  var title = track.title.trim();
  if (title.isEmpty) title = track.fileName;
  title = title.replaceAll(RegExp(r'\s+_\s+'), ' - ').replaceAll('_', ' ');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  final unknown = artist.isEmpty ||
      artist.toLowerCase() == 'unknown artist' ||
      artist.toLowerCase() == 'неизвестный исполнитель';
  if (unknown) {
    final dash = title.split(RegExp(r'\s+-\s+'));
    if (dash.length >= 2) {
      artist = dash.first.trim();
      title = dash.sublist(1).join(' - ').trim();
    }
  }
  title = title.replaceAll(
    RegExp(
      r'\s*[\(\[]\s*(feat\.?|ft\.?|official|audio|video|lyric[s]?|mix|remix|hd)[^\)\]]*[\)\]]',
      caseSensitive: false,
    ),
    '',
  );
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (unknown || artist.isEmpty) return title;
  return _withoutRepeatedArtist(artist, title);
}

String _withoutRepeatedArtist(String artist, String title) {
  final escaped = RegExp.escape(artist);
  var cleaned = title.replaceAll(RegExp(escaped, caseSensitive: false), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return artist;
  return '$artist $cleaned';
}

Future<List<CoverCandidate>> searchCoverCandidates(
  Track track, {
  String? query,
  CoverSearchKind kind = CoverSearchKind.art,
}) async {
  final q = (query ?? coverSearchQuery(track)).trim();
  if (q.length < 2) return const [];
  final hits = switch (kind) {
    CoverSearchKind.art => await Future.wait([_itunes(q), _deezer(q), _youtube(q)]),
    CoverSearchKind.gif => await Future.wait([
        _tenor(q),
        _giphy(q),
        _bingImages(q, gif: true),
        _pinterest(q, gif: true),
      ]),
    CoverSearchKind.image => [await _pinterest(q, gif: false)],
  };
  final seen = <String>{};
  final out = <CoverCandidate>[];
  var i = 0;
  var more = true;
  while (more) {
    more = false;
    for (final group in hits) {
      if (i >= group.length) continue;
      more = true;
      final hit = group[i];
      final key = hit.fullUrl.split('?').first;
      if (seen.add(key)) out.add(hit);
    }
    i++;
  }
  return out;
}

Future<Uint8List?> downloadCoverBytes(String url) async {
  final urls = <String>[url];
  final id = _videoIdFromUrl(url);
  if (id != null) {
    urls
      ..clear()
      ..addAll([
        'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        'https://i.ytimg.com/vi/$id/sddefault.jpg',
        'https://i.ytimg.com/vi/$id/mqdefault.jpg',
        url,
      ]);
  }
  for (final candidate in urls) {
    final bytes = await _getBytes(Uri.parse(candidate));
    if (bytes != null && bytes.length >= 64) return bytes;
  }
  return null;
}

Future<List<CoverCandidate>> _itunes(String query) async {
  try {
    final data = await _getJson(
      Uri.https('itunes.apple.com', '/search', {
        'term': query,
        'media': 'music',
        'entity': 'song',
        'limit': '8',
      }),
    );
    if (data is! Map<String, dynamic>) return const [];
    final results = data['results'];
    if (results is! List) return const [];
    return [
      for (final item in results)
        if (item is Map<String, dynamic> && item['artworkUrl100'] is String)
          CoverCandidate(
            previewUrl: item['artworkUrl100'] as String,
            fullUrl: (item['artworkUrl100'] as String).replaceAll('100x100bb', '600x600bb'),
            source: 'iTunes',
            label: '${item['artistName'] ?? ''} — ${item['trackName'] ?? ''}'.trim(),
          ),
    ];
  } catch (_) {
    return const [];
  }
}

Future<List<CoverCandidate>> _deezer(String query) async {
  try {
    final data = await _getJson(Uri.https('api.deezer.com', '/search', {'q': query, 'limit': '8'}));
    if (data is! Map<String, dynamic>) return const [];
    final results = data['data'];
    if (results is! List) return const [];
    return [
      for (final item in results)
        if (item is Map<String, dynamic>)
          ..._deezerCover(item),
    ];
  } catch (_) {
    return const [];
  }
}

List<CoverCandidate> _deezerCover(Map<String, dynamic> item) {
  final album = item['album'];
  if (album is! Map<String, dynamic>) return const [];
  final preview = (album['cover_medium'] as String?) ?? (album['cover'] as String?);
  final full = (album['cover_xl'] as String?) ?? (album['cover_big'] as String?) ?? preview;
  if (preview == null || full == null) return const [];
  final artist = item['artist'];
  final artistName = artist is Map<String, dynamic> ? (artist['name'] as String? ?? '') : '';
  return [
    CoverCandidate(
      previewUrl: preview,
      fullUrl: full,
      source: 'Deezer',
      label: '$artistName — ${item['title'] ?? ''}'.trim(),
    ),
  ];
}

/// Pinterest image search. Image/GIF covers are whatever the user typed,
/// not a guess from the track title.
Future<List<CoverCandidate>> _pinterest(String query, {required bool gif}) async {
  try {
    final q = gif && !RegExp(r'\bgifs?\b', caseSensitive: false).hasMatch(query) ? '$query gif' : query;
    final payload = jsonEncode({
      'options': {
        'query': q,
        'bookmarks': [''],
        if (gif) 'mediaType': 'gif',
      },
      'context': {},
    });
    final data = await _getJson(
      Uri.https('www.pinterest.com', '/resource/BaseSearchResource/get/', {'data': payload}),
      referer: 'https://www.pinterest.com/',
      accept: 'application/json, text/javascript, */*; q=0.01',
      extraHeaders: const {
        'X-Requested-With': 'XMLHttpRequest',
        'X-Pinterest-AppState': 'active',
        'X-Pinterest-Source-Url': '/ideas/',
        'X-Pinterest-PWS-Handler': 'www/ideas.js',
      },
    );
    if (data is! Map) return const [];
    final resource = data['resource_response'];
    if (resource is! Map) return const [];
    final inner = resource['data'];
    final results = inner is Map ? inner['results'] : null;
    if (results is! List) return const [];
    final limit = gif ? 16 : 24;
    final out = <CoverCandidate>[];
    for (final item in results) {
      if (item is! Map) continue;
      if ((item['type'] as String? ?? '') == 'story') continue;
      final urls = _pinterestUrls(item['images']);
      if (urls == null) continue;
      final isGif = _looksLikeGif(urls.full);
      if (gif && !isGif) continue;
      if (!gif && isGif) continue;
      final grid = (item['grid_title'] as String?)?.trim() ?? '';
      final title = grid.isNotEmpty
          ? grid
          : ((item['title'] as String?) ?? (item['auto_alt_text'] as String?) ?? '').trim();
      out.add(
        CoverCandidate(
          previewUrl: gif ? urls.full : urls.preview,
          fullUrl: urls.full,
          source: 'Pinterest',
          label: title,
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

({String preview, String full})? _pinterestUrls(Object? images) {
  if (images is! Map) return null;
  String? urlOf(String key) {
    final size = images[key];
    if (size is Map && size['url'] is String) {
      final url = (size['url'] as String).trim();
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  final orig = urlOf('orig');
  final mid = urlOf('736x') ?? urlOf('474x');
  final thumb = urlOf('236x') ?? mid;
  if (orig == null && mid == null && thumb == null) return null;
  return (preview: thumb ?? mid ?? orig!, full: orig ?? mid ?? thumb!);
}

/// `.gifv` links are wrappers, not real GIF bytes, so they are skipped.
bool _looksLikeGif(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.endsWith('.gif');
}

Future<List<CoverCandidate>> _tenor(String query) async {
  try {
    final slug = query.trim().replaceAll(RegExp(r'\s+'), '-');
    final body = await _getString(
      Uri.https('tenor.com', '/search/$slug-gifs'),
      accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
      referer: 'https://tenor.com/',
    );
    if (body == null || body.isEmpty) return const [];
    final byName = <String, String>{};
    for (final match in RegExp(r'https://media\.tenor\.com/[^"\\]+\.gif').allMatches(body)) {
      final url = match.group(0)!;
      final name = Uri.parse(url).pathSegments.last;
      final previous = byName[name];
      if (previous == null || previous.contains('AAAAM')) byName[name] = url;
    }
    return [
      for (final entry in byName.entries.take(16))
        CoverCandidate(
          previewUrl: entry.value,
          fullUrl: entry.value,
          source: 'Tenor',
          label: entry.key.replaceAll('.gif', '').replaceAll('-', ' '),
        ),
    ];
  } catch (_) {
    return const [];
  }
}

Future<List<CoverCandidate>> _giphy(String query) async {
  try {
    final body = await _getString(
      Uri.https('giphy.com', '/search/${query.trim()}'),
      accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
      referer: 'https://giphy.com/',
    );
    if (body == null || body.isEmpty) return const [];
    final ids = <String>{};
    for (final match in RegExp(r'/media/(?:v1\.[^/]+/)?([A-Za-z0-9]+)/giphy\.gif').allMatches(body)) {
      ids.add(match.group(1)!);
      if (ids.length >= 16) break;
    }
    return [
      for (final id in ids)
        CoverCandidate(
          previewUrl: 'https://media.giphy.com/media/$id/giphy-preview.gif',
          fullUrl: 'https://media.giphy.com/media/$id/giphy-downsized.gif',
          source: 'Giphy',
          label: '',
        ),
    ];
  } catch (_) {
    return const [];
  }
}

Future<List<CoverCandidate>> _bingImages(String query, {required bool gif}) async {
  try {
    final q = gif && !RegExp(r'\bgifs?\b', caseSensitive: false).hasMatch(query) ? '$query gif' : query;
    final body = await _getString(
      Uri.https('www.bing.com', '/images/async', {
        'q': q,
        'first': '1',
        'count': '32',
        'mmasync': '1',
        if (gif) 'qft': '+filterui:photo-animatedgif',
      }),
      accept: 'text/html,application/xhtml+xml,*/*;q=0.8',
      referer: 'https://www.bing.com/images/search?q=${Uri.encodeQueryComponent(q)}',
    );
    if (body == null || body.isEmpty) return const [];
    final limit = gif ? 16 : 24;
    final out = <CoverCandidate>[];
    for (final block in RegExp(r'm="(\{&quot;.*?\})"').allMatches(body)) {
      Map<String, dynamic> meta;
      try {
        meta = jsonDecode(_unescapeHtml(block.group(1)!)) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final full = (meta['murl'] as String?)?.trim();
      if (full == null || full.isEmpty) continue;
      if (gif && !_looksLikeGif(full)) continue;
      if (!gif && _looksLikeGif(full)) continue;
      final thumb = (meta['turl'] as String?)?.trim();
      out.add(
        CoverCandidate(
          previewUrl: gif || thumb == null || thumb.isEmpty ? full : thumb,
          fullUrl: full,
          source: gif ? 'Bing' : (_hostLabel(meta['purl'] as String?) ?? 'Bing'),
          label: (meta['t'] as String?)?.trim() ?? '',
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String _unescapeHtml(String value) => value
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

String? _hostLabel(String? url) {
  if (url == null || url.isEmpty) return null;
  try {
    final host = Uri.parse(url).host;
    if (host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  } catch (_) {
    return null;
  }
}

Future<List<CoverCandidate>> _youtube(String query) async {
  final instances = [
    Uri.https('pipedapi.kavin.rocks', '/search', {'q': query, 'filter': 'videos'}),
    Uri.parse('https://inv.nadeko.net/api/v1/search?q=${Uri.encodeQueryComponent(query)}&type=video'),
  ];
  for (final uri in instances) {
    try {
      final data = await _getJson(uri);
      final items = _youtubeItems(data);
      if (items.isNotEmpty) return items.take(8).toList();
    } catch (_) {}
  }
  return const [];
}

List<CoverCandidate> _youtubeItems(Object? data) {
  final raw = switch (data) {
    List list => list,
    Map<String, dynamic> map when map['items'] is List => map['items'] as List,
    _ => const [],
  };
  final out = <CoverCandidate>[];
  for (final item in raw) {
    if (item is! Map<String, dynamic>) continue;
    final type = (item['type'] as String? ?? '').toLowerCase();
    if (type.isNotEmpty && type != 'video' && type != 'stream') continue;
    final title = (item['title'] as String?)?.trim() ?? '';
    final thumb = _youtubeThumb(item);
    if (thumb == null) continue;
    out.add(
      CoverCandidate(
        previewUrl: thumb.$1,
        fullUrl: thumb.$2,
        source: 'YouTube',
        label: title,
      ),
    );
  }
  return out;
}

(String, String)? _youtubeThumb(Map<String, dynamic> item) {
  final id = item['videoId'] as String? ??
      _videoIdFromUrl(item['url'] as String?) ??
      _videoIdFromUrl(item['thumbnail'] as String?) ??
      _videoIdFromThumbList(item['videoThumbnails']);
  if (id == null || id.length != 11) return null;
  return (
    'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    'https://i.ytimg.com/vi/$id/sddefault.jpg',
  );
}

String? _videoIdFromThumbList(Object? thumbs) {
  if (thumbs is! List) return null;
  for (final thumb in thumbs) {
    if (thumb is Map<String, dynamic>) {
      final id = _videoIdFromUrl(thumb['url'] as String?);
      if (id != null) return id;
    }
  }
  return null;
}

String? _videoIdFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final vi = RegExp(r'/vi/([\w-]{11})(?:/|$)').firstMatch(url);
  if (vi != null) return vi.group(1);
  final watch = RegExp(r'[?&]v=([\w-]{11})').firstMatch(url);
  if (watch != null) return watch.group(1);
  final short = RegExp(r'youtu\.be/([\w-]{11})').firstMatch(url);
  if (short != null) return short.group(1);
  if (url.startsWith('/watch?v=') && url.length >= 20) return url.substring(9, 20);
  return null;
}

Future<Object?> _getJson(
  Uri uri, {
  String? referer,
  String? accept,
  Map<String, String>? extraHeaders,
}) async {
  final body = await _getString(uri, referer: referer, accept: accept, extraHeaders: extraHeaders);
  if (body == null || body.isEmpty) return null;
  return jsonDecode(body);
}

Future<String?> _getString(
  Uri uri, {
  String? referer,
  String? accept,
  Map<String, String>? extraHeaders,
}) async {
  final bytes = await _getBytes(uri, referer: referer, accept: accept, extraHeaders: extraHeaders);
  if (bytes == null) return null;
  return utf8.decode(bytes, allowMalformed: true);
}

Future<Uint8List?> _getBytes(
  Uri uri, {
  String? referer,
  String? accept,
  Map<String, String>? extraHeaders,
}) async {
  NetworkGate.requireOnline();
  final client = HttpClient();
  try {
    client.userAgent = _kAgent;
    client.connectionTimeout = const Duration(seconds: 8);
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _kAgent);
    request.headers.set(
      HttpHeaders.acceptHeader,
      accept ?? 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    );
    request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
    final host = uri.host;
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer);
    } else if (host.contains('ytimg') || host.contains('youtube')) {
      request.headers.set(HttpHeaders.refererHeader, 'https://www.youtube.com/');
    } else if (host.contains('pinimg') || host.contains('pinterest')) {
      request.headers.set(HttpHeaders.refererHeader, 'https://www.pinterest.com/');
    } else if (host.contains('tenor')) {
      request.headers.set(HttpHeaders.refererHeader, 'https://tenor.com/');
    } else if (host.contains('giphy')) {
      request.headers.set(HttpHeaders.refererHeader, 'https://giphy.com/');
    } else if (host.contains('bing')) {
      request.headers.set(HttpHeaders.refererHeader, 'https://www.bing.com/');
    }
    extraHeaders?.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > _kMaxCoverBytes) return null;
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}
