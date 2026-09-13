import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/file_actions.dart';
import '../data/media_index.dart';
import '../data/scanner.dart';
import '../models/models.dart';

class LibraryController extends ChangeNotifier {
  static const _kFavorites = 'favorites';
  static const _kPlaylists = 'playlists';
  static const _kPlayCounts = 'playCounts';
  static const _kRecent = 'recentlyPlayed';
  static const _kHidden = 'hiddenPaths';

  late SharedPreferences _prefs;

  List<Track> _allTracks = [];
  Set<String> hiddenPaths = {};
  Set<String> favorites = {};
  List<Playlist> playlists = [];
  Map<String, int> playCounts = {};
  List<String> recentlyPlayed = [];
  bool scanning = false;
  String? scanMessage;
  SongSort sort = SongSort.title;
  bool _loaded = false;
  int _derivedRev = 0;
  int _songsRev = -1;
  int _albumsRev = -1;
  int _artistsRev = -1;
  int _foldersRev = -1;
  SongSort? _songsSort;
  List<Track>? _songsCache;
  List<Album>? _albumsCache;
  List<Artist>? _artistsCache;
  Map<String, List<Track>>? _foldersCache;
  Timer? _markPlayedNotify;
  Timer? _saveCacheTimer;

  List<Track> get allTracks => _allTracks;
  set allTracks(List<Track> value) {
    _allTracks = value;
    _invalidateDerived();
  }

  void _invalidateDerived() {
    _derivedRev++;
    _songsCache = null;
    _albumsCache = null;
    _artistsCache = null;
    _foldersCache = null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _prefs = await SharedPreferences.getInstance();
    favorites = (_prefs.getStringList(_kFavorites) ?? []).toSet();
    hiddenPaths = (_prefs.getStringList(_kHidden) ?? []).toSet();
    recentlyPlayed = _prefs.getStringList(_kRecent) ?? [];
    final countsRaw = _prefs.getString(_kPlayCounts);
    if (countsRaw != null) {
      playCounts = Map<String, int>.from(
        (jsonDecode(countsRaw) as Map).map((k, v) => MapEntry(k as String, v as int)),
      );
    }
    final playlistsRaw = _prefs.getString(_kPlaylists);
    if (playlistsRaw != null) {
      playlists = [
        for (final item in jsonDecode(playlistsRaw) as List)
          Playlist.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    }
    await _loadCache();
    notifyListeners();
  }

  Future<void> _loadCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      allTracks = await compute(_parseTrackCache, await file.readAsString());
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final payload = [for (final track in allTracks) track.toJson()];
      final encoded = jsonEncode(payload);
      final file = await _cacheFile();
      await file.writeAsString(encoded);
    } catch (_) {}
  }

  void _scheduleSaveCache() {
    _saveCacheTimer?.cancel();
    _saveCacheTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveCache());
    });
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'library_cache_v3.json'));
  }

  Iterable<Track> get visibleTracks =>
      allTracks.where((track) => !hiddenPaths.contains(track.path));

  List<Track> get hiddenTracks =>
      allTracks.where((track) => hiddenPaths.contains(track.path)).toList();

  List<Track> get songs {
    if (_songsCache != null && _songsRev == _derivedRev && _songsSort == sort) {
      return _songsCache!;
    }
    final list = [...visibleTracks];
    switch (sort) {
      case SongSort.title:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SongSort.artist:
        list.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      case SongSort.album:
        list.sort((a, b) => a.album.toLowerCase().compareTo(b.album.toLowerCase()));
      case SongSort.duration:
        list.sort((a, b) => a.durationMs.compareTo(b.durationMs));
      case SongSort.date:
        list.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
    }
    _songsCache = list;
    _songsRev = _derivedRev;
    _songsSort = sort;
    return list;
  }

  List<Album> get albums {
    if (_albumsCache != null && _albumsRev == _derivedRev) return _albumsCache!;
    final map = <String, List<Track>>{};
    for (final track in visibleTracks) {
      map.putIfAbsent(track.albumKey, () => []).add(track);
    }
    final albums = map.values.map((tracks) {
      tracks.sort((a, b) => (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999));
      return Album(name: tracks.first.album, artist: tracks.first.artist, tracks: tracks);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _albumsCache = albums;
    _albumsRev = _derivedRev;
    return albums;
  }

  List<Artist> get artists {
    if (_artistsCache != null && _artistsRev == _derivedRev) return _artistsCache!;
    final map = <String, List<Track>>{};
    for (final track in visibleTracks) {
      map.putIfAbsent(track.artistKey, () => []).add(track);
    }
    final artists = map.values
        .map((tracks) => Artist(name: tracks.first.artist, tracks: tracks))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _artistsCache = artists;
    _artistsRev = _derivedRev;
    return artists;
  }

  Map<String, List<Track>> get folders {
    if (_foldersCache != null && _foldersRev == _derivedRev) return _foldersCache!;
    final map = <String, List<Track>>{};
    for (final track in visibleTracks) {
      map.putIfAbsent(track.folder, () => []).add(track);
    }
    final folders = Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
    _foldersCache = folders;
    _foldersRev = _derivedRev;
    return folders;
  }

  List<Track> get favoriteTracks =>
      visibleTracks.where((t) => favorites.contains(t.path)).toList();

  List<Track> get recentlyPlayedTracks {
    final byPath = {for (final t in visibleTracks) t.path: t};
    return [
      for (final path in recentlyPlayed)
        if (byPath[path] != null) byPath[path]!,
    ];
  }

  List<Track> get recentlyAddedTracks {
    final list = [...visibleTracks]..sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
    return list.take(80).toList();
  }

  List<Track> get mostPlayedTracks {
    final list = [...visibleTracks]
      ..sort((a, b) => (playCounts[b.path] ?? 0).compareTo(playCounts[a.path] ?? 0));
    return list.where((t) => (playCounts[t.path] ?? 0) > 0).take(80).toList();
  }

  List<Track> tracksForPlaylist(Playlist playlist) {
    final byPath = {for (final t in visibleTracks) t.path: t};
    return [
      for (final path in playlist.trackPaths)
        if (byPath[path] != null) byPath[path]!,
    ];
  }

  List<Track> search(String query) {
    final raw = query.trim();
    if (raw.isEmpty) return <Track>[];
    final q = raw.toLowerCase();
    final folded = _foldSearch(raw);
    final tokens = folded.split(' ').where((part) => part.isNotEmpty).toList();
    return visibleTracks.where((track) => _matchesQuery(track, q, folded, tokens)).toList();
  }

  bool _matchesQuery(Track track, String q, String folded, List<String> tokens) {
    final fields = [
      track.title,
      track.artist,
      track.album,
      track.genre,
      track.fileName,
      track.albumArtist ?? '',
      track.composer ?? '',
      track.path,
    ];
    for (final field in fields) {
      if (field.toLowerCase().contains(q)) return true;
    }
    final blob = _foldSearch(fields.join(' '));
    if (folded.isNotEmpty && blob.contains(folded)) return true;
    if (tokens.length > 1 && tokens.every(blob.contains)) return true;
    return false;
  }

  void setSort(SongSort value) {
    sort = value;
    _songsCache = null;
    notifyListeners();
  }

  Future<void> scan({
    required List<String> folders,
    required int minDurationSec,
    List<String> extraFiles = const [],
  }) async {
    final hadCache = allTracks.isNotEmpty;
    scanning = true;
    scanMessage = hadCache ? 'updatingLibrary' : 'lookingForMusic';
    notifyListeners();

    try {
      final roots = folders;
      if (roots.isEmpty) {
        allTracks = [];
        scanning = false;
        scanMessage = null;
        notifyListeners();
        _scheduleSaveCache();
        return;
      }
      final media = await queryDeviceAudio(folders: roots);
      final diskRoots = <String>[
        for (final root in roots)
          if (media.isEmpty || !Platform.isAndroid || !pathIsUnderRoots(root, defaultDownloadRoots())) root,
      ];
      List<String> disk = const [];
      try {
        disk = diskRoots.isEmpty ? const <String>[] : await compute(listAudioFiles, diskRoots);
      } catch (_) {}
      final unique = <String>{
        for (final track in media) track.path,
        ...disk,
        ...extraFiles,
      };

      final cached = {for (final track in allTracks) track.path: track};
      final fromMedia = {for (final track in media) track.path: track};
      final merged = <Track>[];
      final toParse = <String>[];

      var checked = 0;
      for (final path in unique) {
        final mediaTrack = fromMedia[path];
        if (mediaTrack != null) {
          final old = cached[path];
          final hashed = titleNeedsTagRead(mediaTrack.title) ||
              titleNeedsTagRead(mediaTrack.fileName) ||
              (pathLooksLikeTelegram(path) && mediaTrack.title == mediaTrack.fileName);
          if (hashed && (old == null || titleNeedsTagRead(old.title))) {
            toParse.add(path);
            merged.add(_keepUserTags(old ?? mediaTrack, old));
          } else {
            final next = (old != null && (!titleNeedsTagRead(old.title) || old.tagsEdited)) ? old : mediaTrack;
            merged.add(_keepUserTags(next, old));
          }
          continue;
        }
        var modifiedMs = 0;
        try {
          modifiedMs = File(path).lastModifiedSync().millisecondsSinceEpoch;
        } catch (_) {}
        final old = cached[path];
        if (old != null && old.modifiedMs != 0 && old.modifiedMs == modifiedMs) {
          merged.add(old);
        } else {
          toParse.add(path);
          merged.add(old ?? trackFromPathFast(path, modifiedMs: modifiedMs));
        }
        checked++;
        if (checked % 40 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      final minMs = minDurationSec * 1000;
      allTracks = [
        for (final track in merged)
          if (minMs == 0 || track.durationMs == 0 || track.durationMs >= minMs) track,
      ];
      scanning = false;
      scanMessage = null;
      notifyListeners();
      await Future<void>.delayed(Duration.zero);

      if (toParse.isNotEmpty) {
        const chunk = 40;
        for (var i = 0; i < toParse.length; i += chunk) {
          final slice = toParse.sublist(i, math.min(i + chunk, toParse.length));
          final parsed = await compute(parseAudioFiles, slice);
          final byPath = {for (final track in parsed) track.path: track};
          allTracks = [
            for (final track in allTracks)
              _keepUserTags(byPath[track.path] ?? track, track),
          ];
        }
        notifyListeners();
      }

      _scheduleSaveCache();
    } finally {
      scanning = false;
      scanMessage = null;
      notifyListeners();
    }
  }

  Future<void> addFiles(List<String> paths) async {
    if (paths.isEmpty) return;
    final existing = allTracks.map((t) => t.path).toSet();
    final fresh = paths.where((p) => !existing.contains(p)).toList();
    if (fresh.isEmpty) return;
    final parsed = await compute(parseAudioFiles, fresh);
    allTracks = [...allTracks, ...parsed];
    notifyListeners();
    _scheduleSaveCache();
  }

  Future<void> toggleFavorite(String path) async {
    if (favorites.contains(path)) {
      favorites = {...favorites}..remove(path);
    } else {
      favorites = {...favorites, path};
    }
    await _prefs.setStringList(_kFavorites, favorites.toList());
    notifyListeners();
  }

  Future<void> markPlayed(String path) async {
    playCounts = {...playCounts, path: (playCounts[path] ?? 0) + 1};
    recentlyPlayed = [path, ...recentlyPlayed.where((p) => p != path)].take(100).toList();
    await _prefs.setString(_kPlayCounts, jsonEncode(playCounts));
    await _prefs.setStringList(_kRecent, recentlyPlayed);
    _markPlayedNotify?.cancel();
    _markPlayedNotify = Timer(const Duration(milliseconds: 800), notifyListeners);
  }

  Future<void> createPlaylist(String name) async {
    playlists = [
      ...playlists,
      Playlist(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        trackPaths: [],
      ),
    ];
    await _savePlaylists();
  }

  Future<void> renamePlaylist(String id, String name) async {
    playlists = [
      for (final playlist in playlists)
        if (playlist.id == id)
          Playlist(id: playlist.id, name: name, trackPaths: playlist.trackPaths)
        else
          playlist,
    ];
    await _savePlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    playlists = playlists.where((p) => p.id != id).toList();
    await _savePlaylists();
  }

  Future<void> addToPlaylist(String id, Track track) async {
    playlists = [
      for (final playlist in playlists)
        if (playlist.id == id && !playlist.trackPaths.contains(track.path))
          Playlist(id: playlist.id, name: playlist.name, trackPaths: [...playlist.trackPaths, track.path])
        else
          playlist,
    ];
    await _savePlaylists();
  }

  Future<void> removeFromPlaylist(String id, String path) async {
    playlists = [
      for (final playlist in playlists)
        if (playlist.id == id)
          Playlist(
            id: playlist.id,
            name: playlist.name,
            trackPaths: playlist.trackPaths.where((p) => p != path).toList(),
          )
        else
          playlist,
    ];
    await _savePlaylists();
  }

  Track _keepUserTags(Track next, Track? previous) {
    if (previous == null) return next;
    if (!previous.tagsEdited) {
      return _keepCoverShape(next, previous);
    }
    return next.copyWith(
      title: previous.title,
      artist: previous.artist,
      album: previous.album,
      albumArtist: previous.albumArtist,
      composer: previous.composer,
      coverShape: previous.coverShape,
      tagsEdited: true,
    );
  }

  Track _keepCoverShape(Track next, Track? previous) {
    if (previous == null || next.coverShape == previous.coverShape) return next;
    return next.copyWith(coverShape: previous.coverShape);
  }

  Future<void> replaceTrack(Track updated, {String? fromPath}) async {
    final oldPath = fromPath ?? updated.path;
    allTracks = [
      for (final track in allTracks)
        if (track.path == oldPath) updated else track,
    ];
    notifyListeners();
    await _saveCache();
  }

  Future<void> retargetTrack(String oldPath, Track updated) async {
    if (oldPath == updated.path) {
      replaceTrack(updated);
      return;
    }
    allTracks = [
      for (final track in allTracks)
        if (track.path == oldPath) updated else track,
    ];
    if (hiddenPaths.contains(oldPath)) {
      hiddenPaths = {...hiddenPaths}..remove(oldPath)..add(updated.path);
      await _saveHidden();
    }
    if (favorites.contains(oldPath)) {
      favorites = {...favorites}..remove(oldPath)..add(updated.path);
      await _prefs.setStringList(_kFavorites, favorites.toList());
    }
    final plays = playCounts[oldPath];
    playCounts = {
      for (final entry in playCounts.entries)
        if (entry.key != oldPath) entry.key: entry.value,
      if (plays != null) updated.path: plays,
    };
    await _prefs.setString(_kPlayCounts, jsonEncode(playCounts));
    recentlyPlayed = [for (final path in recentlyPlayed) path == oldPath ? updated.path : path];
    await _prefs.setStringList(_kRecent, recentlyPlayed);
    playlists = [
      for (final playlist in playlists)
        Playlist(
          id: playlist.id,
          name: playlist.name,
          trackPaths: [for (final path in playlist.trackPaths) path == oldPath ? updated.path : path],
        ),
    ];
    await _savePlaylists();
    notifyListeners();
    _scheduleSaveCache();
  }

  Future<void> hideTrack(String path) async {
    hiddenPaths = {...hiddenPaths, path};
    _invalidateDerived();
    await _saveHidden();
    notifyListeners();
  }

  Future<void> unhideTrack(String path) async {
    hiddenPaths = {...hiddenPaths}..remove(path);
    _invalidateDerived();
    await _saveHidden();
    notifyListeners();
  }

  Future<void> removeTrack(String path) async {
    allTracks = allTracks.where((track) => track.path != path).toList();
    hiddenPaths = {...hiddenPaths}..remove(path);
    _invalidateDerived();
    favorites = {...favorites}..remove(path);
    playCounts = {...playCounts}..remove(path);
    recentlyPlayed = recentlyPlayed.where((item) => item != path).toList();
    playlists = [
      for (final playlist in playlists)
        Playlist(
          id: playlist.id,
          name: playlist.name,
          trackPaths: playlist.trackPaths.where((item) => item != path).toList(),
        ),
    ];
    await _prefs.setStringList(_kFavorites, favorites.toList());
    await _prefs.setString(_kPlayCounts, jsonEncode(playCounts));
    await _prefs.setStringList(_kRecent, recentlyPlayed);
    await _savePlaylists();
    await _saveHidden();
    notifyListeners();
    _scheduleSaveCache();
  }

  Future<String?> deleteFromDevice(Track track) async {
    final error = await deleteAudioFile(track.path);
    if (error != null) return error;
    await removeTrack(track.path);
    return null;
  }

  Future<void> _saveHidden() async {
    await _prefs.setStringList(_kHidden, hiddenPaths.toList());
  }

  Future<void> _savePlaylists() async {
    await _prefs.setString(
      _kPlaylists,
      jsonEncode([for (final playlist in playlists) playlist.toJson()]),
    );
    notifyListeners();
  }
}

List<Track> _parseTrackCache(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return [
    for (final item in decoded)
      if (item is Map) Track.fromJson(Map<String, dynamic>.from(item)),
  ];
}

String _foldSearch(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
