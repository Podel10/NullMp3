import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

@immutable
class Track {
  const Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.durationMs,
    required this.modifiedMs,
    this.year,
    this.trackNumber,
    this.albumArtist,
    this.composer,
    this.uri,
    this.coverShape = CoverShape.square,
    this.tagsEdited = false,
  });

  final String path;
  final String? uri;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int durationMs;
  final int modifiedMs;
  final int? year;
  final int? trackNumber;
  final String? albumArtist;
  final String? composer;
  final CoverShape coverShape;
  final bool tagsEdited;

  bool get isCircleCover => coverShape == CoverShape.circle;

  String get id => path;
  Duration get duration => Duration(milliseconds: durationMs);
  String get folder => p.dirname(path);
  String get folderName => p.basename(folder);
  String get fileName => p.basenameWithoutExtension(path);
  String get albumKey => '${artist.toLowerCase()}::${album.toLowerCase()}';
  String get artistKey => artist.toLowerCase();

  Track copyWith({
    String? path,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? durationMs,
    int? modifiedMs,
    int? year,
    int? trackNumber,
    String? albumArtist,
    String? composer,
    String? uri,
    CoverShape? coverShape,
    bool? tagsEdited,
  }) {
    return Track(
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      durationMs: durationMs ?? this.durationMs,
      modifiedMs: modifiedMs ?? this.modifiedMs,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      albumArtist: albumArtist ?? this.albumArtist,
      composer: composer ?? this.composer,
      uri: uri ?? this.uri,
      coverShape: coverShape ?? this.coverShape,
      tagsEdited: tagsEdited ?? this.tagsEdited,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'durationMs': durationMs,
        'modifiedMs': modifiedMs,
        'year': year,
        'trackNumber': trackNumber,
        'albumArtist': albumArtist,
        'composer': composer,
        'uri': uri,
        'coverShape': coverShape.name,
        'tagsEdited': tagsEdited,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        path: json['path'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String,
        genre: json['genre'] as String? ?? 'Unknown',
        durationMs: json['durationMs'] as int? ?? 0,
        modifiedMs: json['modifiedMs'] as int? ?? 0,
        year: json['year'] as int?,
        trackNumber: json['trackNumber'] as int?,
        albumArtist: json['albumArtist'] as String?,
        composer: json['composer'] as String?,
        uri: json['uri'] as String?,
        coverShape: CoverShape.values.firstWhere(
          (value) => value.name == json['coverShape'],
          orElse: () => CoverShape.square,
        ),
        tagsEdited: json['tagsEdited'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) => other is Track && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class Album {
  Album({required this.name, required this.artist, required this.tracks});

  final String name;
  final String artist;
  final List<Track> tracks;

  String get key => '${artist.toLowerCase()}::${name.toLowerCase()}';
  Track get representative => tracks.first;
  int get year =>
      tracks.map((t) => t.year).whereType<int>().fold(0, (a, b) => a > b ? a : b);
}

class Artist {
  Artist({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;

  List<Album> get albums {
    final map = <String, List<Track>>{};
    for (final track in tracks) {
      map.putIfAbsent(track.album, () => []).add(track);
    }
    final albums = map.entries
        .map((e) => Album(name: e.key, artist: name, tracks: e.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return albums;
  }
}

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.trackPaths,
    this.system = false,
  });

  final String id;
  String name;
  final List<String> trackPaths;
  final bool system;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackPaths': trackPaths,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        trackPaths: List<String>.from(json['trackPaths'] as List),
      );
}

enum CoverShape { square, circle }

enum RepeatKind { off, one }

enum SleepKind { off, timer, endOfTrack }

enum LibraryTab { recommended, songs, albums, artists, playlists, folders }

enum SongSort { title, artist, album, duration, date }

class EqPreset {
  const EqPreset(this.name, this.bands);

  final String name;
  final List<double> bands;

  static const presets = <EqPreset>[
    EqPreset('Normal', [0, 0, 0, 0, 0]),
    EqPreset('Pop', [-1.5, 2.5, 3.5, 1.5, -1]),
    EqPreset('Rock', [4.5, 3, -2, 2.5, 4]),
    EqPreset('Jazz', [3, 2, -1.5, 2, 3]),
    EqPreset('Classical', [4, 2, -2, 3, 3.5]),
    EqPreset('Dance', [5.5, 3.5, 0, 2, 4]),
    EqPreset('Bass boost', [7, 4.5, 0, -2, -1]),
    EqPreset('Treble boost', [-2, -1, 1.5, 4.5, 6.5]),
    EqPreset('Vocal', [-2, 0, 4.5, 3.5, 0]),
    EqPreset('Flat', [0, 0, 0, 0, 0]),
  ];
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(hours > 0 ? 2 : 1, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
