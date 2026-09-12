import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import 'widgets.dart';

class AlbumDetailScreen extends StatelessWidget {
  const AlbumDetailScreen({super.key, required this.album});
  final Album album;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final tracks = album.tracks;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CoverArt(track: album.representative, expand: true, radius: 0),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: PlayHeader(
              countLabel: context.s.songsCount(tracks.length),
              onPlay: () => player.playTracks(tracks),
              onShuffle: () async {
                await player.playTracks(tracks);
                if (!player.shuffle) await player.toggleShuffle();
              },
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) {
              final track = tracks[i];
              return SongTile(
                track: track,
                selected: player.current?.path == track.path,
                onTap: () => player.playTracks(tracks, start: i),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ArtistDetailScreen extends StatelessWidget {
  const ArtistDetailScreen({super.key, required this.artist});
  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return Scaffold(
      appBar: AppBar(title: Text(artist.name)),
      body: ListView(
        children: [
          PlayHeader(
            countLabel: context.s.songsCount(artist.tracks.length),
            onPlay: () => player.playTracks(artist.tracks),
            onShuffle: () async {
              await player.playTracks(artist.tracks);
              if (!player.shuffle) await player.toggleShuffle();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(context.s.tabAlbums, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            height: 180,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: artist.albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final album = artist.albums[i];
                return SizedBox(
                  width: 132,
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AlbumDetailScreen(album: album))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CoverArt(track: album.representative, size: 132, radius: 12),
                        const SizedBox(height: 8),
                        Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(context.s.tabSongs, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          for (var i = 0; i < artist.tracks.length; i++)
            SongTile(
              track: artist.tracks[i],
              selected: player.current?.path == artist.tracks[i].path,
              onTap: () => player.playTracks(artist.tracks, start: i),
            ),
        ],
      ),
    );
  }
}

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final player = context.watch<PlayerController>();
    final matches = library.playlists.where((p) => p.id == playlistId);
    if (matches.isEmpty) {
      return Scaffold(body: Center(child: Text(context.s.playlistRemoved)));
    }
    final playlist = matches.first;
    final tracks = library.tracksForPlaylist(playlist);
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: tracks.isEmpty
          ? Center(child: Text(context.s.noSongsInPlaylist))
          : Column(
              children: [
                PlayHeader(
                  countLabel: context.s.songsCount(tracks.length),
                  onPlay: () => player.playTracks(tracks),
                  onShuffle: () async {
                    await player.playTracks(tracks);
                    if (!player.shuffle) await player.toggleShuffle();
                  },
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, i) {
                      final track = tracks[i];
                      return SongTile(
                        track: track,
                        playlist: playlist,
                        selected: player.current?.path == track.path,
                        onTap: () => player.playTracks(tracks, start: i),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class SmartPlaylistScreen extends StatelessWidget {
  const SmartPlaylistScreen({super.key, required this.title, required this.tracks});
  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tracks.isEmpty
          ? Center(child: Text(context.s.nothingHereYet))
          : Column(
              children: [
                PlayHeader(
                  countLabel: context.s.songsCount(tracks.length),
                  onPlay: () => player.playTracks(tracks),
                  onShuffle: () async {
                    await player.playTracks(tracks);
                    if (!player.shuffle) await player.toggleShuffle();
                  },
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, i) {
                      final track = tracks[i];
                      return SongTile(
                        track: track,
                        selected: player.current?.path == track.path,
                        onTap: () => player.playTracks(tracks, start: i),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class FolderDetailScreen extends StatelessWidget {
  const FolderDetailScreen({super.key, required this.folder, required this.tracks});
  final String folder;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return Scaffold(
      appBar: AppBar(title: Text(tracks.isEmpty ? folder : tracks.first.folderName)),
      body: Column(
        children: [
          PlayHeader(
            countLabel: context.s.songsCount(tracks.length),
            onPlay: () => player.playTracks(tracks),
            onShuffle: () async {
              await player.playTracks(tracks);
              if (!player.shuffle) await player.toggleShuffle();
            },
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final track = tracks[i];
                return SongTile(
                  track: track,
                  selected: player.current?.path == track.path,
                  onTap: () => player.playTracks(tracks, start: i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
