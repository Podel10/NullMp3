import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'app_storage.dart';
import 'network.dart';
import 'stable_hash.dart';

const _kLrcTime = r'\[\d{1,2}:\d{2}';
const _kLrclibAgent = 'NullMP3/1.0 (https://lrclib.net)';

class LyricsOfflineException implements Exception {}

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class LyricsResult {
  const LyricsResult({
    this.lines = const [],
    this.plain,
    this.instrumental = false,
  });

  final List<LyricLine> lines;
  final String? plain;
  final bool instrumental;

  bool get isEmpty =>
      !instrumental && lines.isEmpty && (plain == null || plain!.trim().isEmpty);

  bool get synced => lines.isNotEmpty;

  String get raw {
    if (instrumental) return '[instrumental]';
    if (lines.isNotEmpty) {
      return lines.map((line) {
        final m = line.time.inMinutes;
        final s = (line.time.inSeconds % 60).toString().padLeft(2, '0');
        final cs = ((line.time.inMilliseconds % 1000) / 10).floor().toString().padLeft(2, '0');
        return '[$m:$s.$cs]${line.text}';
      }).join('\n');
    }
    return plain ?? '';
  }
}

class LyricHit {
  const LyricHit({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSec,
    required this.source,
    required this.lyrics,
    required this.score,
  });

  final String title;
  final String artist;
  final String album;
  final int durationSec;
  final String source;
  final LyricsResult lyrics;
  final int score;
}

class LyricSearchFilters {
  const LyricSearchFilters({
    this.similarDuration = false,
    this.matchArtist = false,
    this.syncedOnly = false,
  });

  final bool similarDuration;
  final bool matchArtist;
  final bool syncedOnly;

  LyricSearchFilters copyWith({
    bool? similarDuration,
    bool? matchArtist,
    bool? syncedOnly,
  }) {
    return LyricSearchFilters(
      similarDuration: similarDuration ?? this.similarDuration,
      matchArtist: matchArtist ?? this.matchArtist,
      syncedOnly: syncedOnly ?? this.syncedOnly,
    );
  }
}

Directory? _lyricsDir;

Future<Directory> _dir() async {
  if (_lyricsDir != null) return _lyricsDir!;
  final dir = await AppStorage.subdir('lyrics');
  _lyricsDir = dir;
  return dir;
}

String _key(String path) => stablePathKey(path);

String _legacyKey(String path) => legacyPathKey(path);

Future<File> _overrideFile(String path) async =>
    File(p.join((await _dir()).path, '${_key(path)}.txt'));

Future<File> _legacyOverrideFile(String path) async =>
    File(p.join((await _dir()).path, '${_legacyKey(path)}.txt'));

Future<File> _clearedFile(String path) async =>
    File(p.join((await _dir()).path, '${_key(path)}.cleared'));

bool _isUnknown(String value) {
  final text = value.trim().toLowerCase();
  return text.isEmpty ||
      text == 'unknown' ||
      text == 'unknown artist' ||
      text == 'unknown album' ||
      text == 'неизвестный исполнитель' ||
      text == 'неизвестный альбом';
}

LyricsResult parseLyrics(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) return const LyricsResult();
  if (trimmed.toLowerCase() == '[instrumental]' || trimmed.toLowerCase() == 'instrumental') {
    return const LyricsResult(instrumental: true);
  }
  if (RegExp(_kLrcTime).hasMatch(trimmed)) {
    final parsed = _parseLrc(trimmed);
    if (parsed.lines.isNotEmpty) return parsed;
  }
  return LyricsResult(plain: trimmed);
}

Future<void> saveLyrics(String trackPath, String text) async {
  final file = await _overrideFile(trackPath);
  await file.writeAsString(text);
  final cleared = await _clearedFile(trackPath);
  if (await cleared.exists()) await cleared.delete();
}

Future<void> clearSavedLyrics(String trackPath) async {
  final file = await _overrideFile(trackPath);
  if (await file.exists()) await file.delete();
  final cleared = await _clearedFile(trackPath);
  await cleared.writeAsString('');
}

Future<bool> lyricsSearchSuppressed(String path) async {
  try {
    return await (await _clearedFile(path)).exists();
  } catch (_) {
    return false;
  }
}

Future<LyricsResult> loadLyricsFor(Track track) async {
  try {
    final override = await _overrideFile(track.path);
    if (await override.exists()) {
      return parseLyrics(await override.readAsString());
    }
    final legacy = await _legacyOverrideFile(track.path);
    if (await legacy.exists()) {
      final text = await legacy.readAsString();
      await override.writeAsString(text);
      return parseLyrics(text);
    }
  } catch (_) {}

  if (!track.path.startsWith('content:')) {
    try {
      final lrcFile = File('${p.withoutExtension(track.path)}.lrc');
      if (lrcFile.existsSync()) {
        return parseLyrics(lrcFile.readAsStringSync());
      }
    } catch (_) {}
    try {
      final raw = readMetadata(File(track.path), getImage: false).lyrics?.trim();
      if (raw != null && raw.isNotEmpty) return parseLyrics(raw);
    } catch (_) {}
  }

  return const LyricsResult();
}

String defaultLyricsQuery(Track track) {
  final parsed = _queryParts(track);
  if (parsed.remix && parsed.titles.isNotEmpty) {
    return parsed.titles.reduce((a, b) => a.length <= b.length ? a : b);
  }
  if (parsed.artist.isNotEmpty && parsed.titles.isNotEmpty) {
    return '${parsed.artist} ${parsed.titles.first}';
  }
  if (parsed.titles.isNotEmpty) return parsed.titles.first;
  return _cleanTitle(track.title);
}

Future<LyricsResult> fetchLyricsOnline(Track track) async {
  final parsed = _queryParts(track);
  if (parsed.remix || parsed.artist.isEmpty) return const LyricsResult();
  final hits = await searchLyricHits(track);
  if (hits.isEmpty) return const LyricsResult();
  final best = hits.first;
  final duration = (track.durationMs / 1000).round();
  final close = duration <= 0 || (best.durationSec - duration).abs() <= 3;
  final sameArtist = best.artist.toLowerCase() == parsed.artist.toLowerCase();
  if (best.score >= 70 && sameArtist && close) return best.lyrics;
  return const LyricsResult();
}

Future<List<LyricHit>> searchLyricHits(
  Track track, {
  String? query,
  LyricSearchFilters filters = const LyricSearchFilters(),
}) async {
  if (NetworkGate.offline) throw LyricsOfflineException();
  final parsed = _queryParts(track);
  final q = (query ?? defaultLyricsQuery(track)).trim();
  if (q.isEmpty && parsed.titles.isEmpty) return const [];

  final hits = <LyricHit>[];
  final seen = <String>{};

  void addHit(LyricHit hit) {
    if (hit.lyrics.isEmpty) return;
    final key = '${hit.artist.toLowerCase()}|${hit.title.toLowerCase()}|${hit.durationSec}|${hit.source}';
    if (!seen.add(key)) return;
    if (filters.syncedOnly && !hit.lyrics.synced) return;
    if (filters.matchArtist && parsed.artist.isNotEmpty) {
      final artist = hit.artist.toLowerCase();
      final want = parsed.artist.toLowerCase();
      if (artist != want && !artist.contains(want) && !want.contains(artist)) return;
    }
    if (filters.similarDuration && parsed.duration > 0 && hit.durationSec > 0) {
      if ((hit.durationSec - parsed.duration).abs() > 8) return;
    }
    hits.add(hit);
  }

  for (final uri in _searchUris(parsed, extraQuery: q).take(5)) {
    final found = await _lrclibJson(uri);
    if (found is! List) continue;
    for (final item in found) {
      if (item is! Map<String, dynamic>) continue;
      final lyrics = _fromLrclib(item);
      if (lyrics.isEmpty) continue;
      addHit(
        LyricHit(
          title: (item['trackName'] as String?)?.trim() ?? '',
          artist: (item['artistName'] as String?)?.trim() ?? '',
          album: (item['albumName'] as String?)?.trim() ?? '',
          durationSec: (item['duration'] as num?)?.round() ?? 0,
          source: 'LRCLIB',
          lyrics: lyrics,
          score: _matchScore(item, parsed, searchText: q),
        ),
      );
    }
  }

  await _addLyricsOvhHits(q, parsed, addHit);

  hits.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    if (parsed.duration > 0) {
      final da = a.durationSec == 0 ? 999 : (a.durationSec - parsed.duration).abs();
      final db = b.durationSec == 0 ? 999 : (b.durationSec - parsed.duration).abs();
      return da.compareTo(db);
    }
    return a.title.compareTo(b.title);
  });
  return hits;
}

Future<void> _addLyricsOvhHits(String query, _LyricQuery parsed, void Function(LyricHit hit) addHit) async {
  final pairs = <(String, String)>[];
  if (parsed.artist.isNotEmpty) {
    for (final title in parsed.titles.take(2)) {
      pairs.add((parsed.artist, title));
    }
  }
  final split = query.split(RegExp(r'\s+-\s+'));
  if (split.length >= 2) {
    pairs.add((split.first.trim(), split.sublist(1).join(' - ').trim()));
  }
  final words = query.split(' ').where((word) => word.isNotEmpty).toList();
  if (words.length >= 3) {
    pairs.add((words.first, words.sublist(1).join(' ')));
  }

  final tried = <String>{};
  for (final pair in pairs) {
    final artist = pair.$1.trim();
    final title = pair.$2.trim();
    if (artist.length < 2 || title.length < 2) continue;
    if (!tried.add('${artist.toLowerCase()}|${title.toLowerCase()}')) continue;
    try {
      final data = await _httpJson(
        Uri.parse('https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}'),
      );
      if (data is! Map<String, dynamic>) continue;
      final text = (data['lyrics'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;
      addHit(
        LyricHit(
          title: title,
          artist: artist,
          album: '',
          durationSec: 0,
          source: 'lyrics.ovh',
          lyrics: parseLyrics(text),
          score: 20,
        ),
      );
    } catch (_) {}
  }
}

class _LyricQuery {
  const _LyricQuery({
    required this.titles,
    required this.artist,
    required this.duration,
    required this.remix,
  });

  final List<String> titles;
  final String artist;
  final int duration;
  final bool remix;
}

_LyricQuery _queryParts(Track track) {
  var raw = track.title.trim();
  if (raw.isEmpty) raw = track.fileName;
  raw = _normalizeSeparators(raw);
  final remix = _looksLikeRemix(raw);

  var artist = _isUnknown(track.artist) ? '' : _cleanPerson(track.artist);
  var body = raw;

  if (artist.isEmpty) {
    final dash = raw.split(RegExp(r'\s+-\s+'));
    if (dash.length >= 2) {
      artist = _cleanPerson(dash.first);
      body = dash.sublist(1).join(' - ');
    }
  }

  body = _stripVersionSuffix(_cleanTitle(body));
  final titles = _titleVariants(body);
  return _LyricQuery(
    titles: titles,
    artist: artist,
    duration: (track.durationMs / 1000).round(),
    remix: remix,
  );
}

bool _looksLikeRemix(String value) {
  return RegExp(
    r'\b(mix|remix|bootleg|edit|flip|vip|mashup|cover|refix|slowed|reverb|nightcore)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

String _normalizeSeparators(String value) {
  var text = value.trim().replaceAll('—', '-').replaceAll('–', '-');
  text = text.replaceAll(RegExp(r'\s+_\s+'), ' - ');
  text = text.replaceAll('_', ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stripVersionSuffix(String title) {
  return title
      .replaceAll(
        RegExp(
          r'\s+\b(mix|remix|bootleg|edit|flip|vip|mashup|cover|refix|version|slowed|reverb|nightcore|extended|radio)\b.*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
}

List<String> _titleVariants(String title) {
  final cleaned = title.trim();
  if (cleaned.isEmpty) return const [];
  final words = cleaned.split(' ').where((word) => word.isNotEmpty).toList();
  final out = <String>{cleaned};
  if (words.length >= 4) out.add(words.sublist(1).join(' '));
  if (words.length >= 3) out.add(words.sublist(words.length - 3).join(' '));
  if (words.length >= 4) out.add(words.sublist(words.length - 4).join(' '));
  return [
    for (final item in out)
      if (item.split(' ').length >= 2 || item.length >= 6) item,
  ];
}

String _cleanPerson(String value) {
  return _normalizeSeparators(value)
      .replaceAll(RegExp(r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring)\b[^\)\]]*[\)\]]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _cleanTitle(String value) {
  var text = _normalizeSeparators(value);
  text = text.replaceAll(
    RegExp(r'\s*[\(\[]\s*(feat\.?|ft\.?|featuring)\b[^\)\]]*[\)\]]', caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(
      r'\s*[\(\[]\s*(official|audio|video|lyric[s]?|visualizer|hd|4k|remaster(?:ed)?|explicit|radio edit)[^\)\]]*[\)\]]',
      caseSensitive: false,
    ),
    '',
  );
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Iterable<Uri> _searchUris(_LyricQuery query, {String? extraQuery}) sync* {
  final seen = <String>{};
  void add(String text) {
    final value = text.trim();
    if (value.length >= 4) seen.add(value.toLowerCase());
  }

  add(extraQuery ?? '');
  for (final title in query.titles) {
    if (query.artist.isNotEmpty && !query.remix) add('${query.artist} $title');
    add(title);
  }

  for (final text in seen) {
    yield Uri.https('lrclib.net', '/api/search', {'q': text});
  }
  for (final title in query.titles.take(2)) {
    yield Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (query.artist.isNotEmpty && !query.remix) 'artist_name': query.artist,
    });
  }
}

int _matchScore(Map<String, dynamic> item, _LyricQuery query, {String searchText = ''}) {
  final title = (item['trackName'] as String? ?? '').toLowerCase();
  final artist = (item['artistName'] as String? ?? '').toLowerCase();
  final wantArtist = query.artist.toLowerCase();
  var score = 0;
  var titleScore = 0;
  for (final wantTitle in query.titles) {
    final want = wantTitle.toLowerCase();
    if (title == want) {
      titleScore = 50;
      break;
    }
    if (title.isNotEmpty && (want.contains(title) || title.contains(want))) {
      titleScore = titleScore < 28 ? 28 : titleScore;
    } else if (_allWordsIn(want, title)) {
      titleScore = titleScore < 22 ? 22 : titleScore;
    }
  }
  score += titleScore;
  final search = searchText.toLowerCase();
  if (search.isNotEmpty) {
    if (title.isNotEmpty && search.contains(title)) score += 10;
    if (artist.isNotEmpty && search.contains(artist)) score += 10;
  }
  if (wantArtist.isNotEmpty) {
    if (artist == wantArtist) {
      score += 40;
    } else if (artist.contains(wantArtist) || wantArtist.contains(artist)) {
      score += 18;
    } else if (query.remix) {
      score += 0;
    }
  } else if (artist.length >= 3 && query.titles.any((title) => title.toLowerCase().contains(artist))) {
    score += 16;
  }
  final duration = (item['duration'] as num?)?.round() ?? 0;
  if (!query.remix && query.duration > 0 && duration > 0) {
    final delta = (duration - query.duration).abs();
    if (delta <= 2) {
      score += 30;
    } else if (delta <= 6) {
      score += 12;
    }
  }
  if ((item['syncedLyrics'] as String?)?.trim().isNotEmpty == true) score += 4;
  return score;
}

bool _allWordsIn(String haystack, String needle) {
  final words = needle.split(' ').where((word) => word.length > 1);
  return words.isNotEmpty && words.every(haystack.contains);
}

LyricsResult _fromLrclib(Map<String, dynamic> data) {
  final synced = (data['syncedLyrics'] as String?)?.trim() ?? '';
  if (synced.isNotEmpty) return parseLyrics(synced);
  final plain = (data['plainLyrics'] as String?)?.trim() ?? '';
  if (plain.isNotEmpty) return LyricsResult(plain: plain);
  if (data['instrumental'] == true) return const LyricsResult(instrumental: true);
  return const LyricsResult();
}

Future<Object?> _lrclibJson(Uri uri) => _httpJson(uri);

Future<Object?> _httpJson(Uri uri) async {
  NetworkGate.requireOnline();
  final client = HttpClient();
  try {
    client.userAgent = _kLrclibAgent;
    client.connectionTimeout = const Duration(seconds: 12);
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _kLrclibAgent);
    request.headers.set('Lrclib-Client', _kLrclibAgent);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return jsonDecode(body);
  } on LyricsOfflineException {
    rethrow;
  } catch (error) {
    if (_isOfflineError(error)) throw LyricsOfflineException();
    rethrow;
  } finally {
    client.close(force: true);
  }
}

bool _isOfflineError(Object error) {
  if (error is LyricsOfflineException) return true;
  if (error is SocketException ||
      error is HandshakeException ||
      error is TlsException ||
      error is TimeoutException ||
      error is HttpException ||
      error is OSError) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('failed host lookup') ||
      text.contains('timed out');
}

LyricsResult _parseLrc(String source) {
  final pattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');
  final lines = <LyricLine>[];
  for (final raw in source.split('\n')) {
    for (final match in pattern.allMatches(raw)) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3);
      var ms = 0;
      if (fraction != null) {
        ms = int.parse(fraction.padRight(3, '0').substring(0, 3));
      }
      final text = match.group(4)!.trim();
      if (text.isEmpty) continue;
      lines.add(
        LyricLine(Duration(minutes: minutes, seconds: seconds, milliseconds: ms), text),
      );
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return LyricsResult(lines: lines);
}
