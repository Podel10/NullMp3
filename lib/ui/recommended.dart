import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import 'details.dart';
import 'now_playing.dart';
import 'widgets.dart';

class RecommendedTab extends StatelessWidget {
  const RecommendedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final s = context.s;
    final recentlyPlayed = library.recentlyPlayedTracks.take(16).toList();
    final popular = _uniqueAlbums(
      library.mostPlayedTracks.isNotEmpty ? library.mostPlayedTracks : library.recentlyAddedTracks,
    );
    final favorites = library.favoriteTracks.take(16).toList();
    final added = library.recentlyAddedTracks.take(10).toList();

    if (recentlyPlayed.isEmpty && popular.isEmpty && favorites.isEmpty && added.isEmpty) {
      return Center(child: Text(s.playToFill));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (recentlyPlayed.isNotEmpty)
          _CarouselSection(
            title: s.recentlyPlayed,
            tracks: recentlyPlayed,
            onSeeAll: () => _openAll(context, s.recentlyPlayed, library.recentlyPlayedTracks),
          ),
        if (popular.isNotEmpty)
          _CarouselSection(
            title: s.mostPopular,
            tracks: popular,
            preferAlbum: true,
            onSeeAll: () => _openAll(
              context,
              s.mostPopular,
              library.mostPlayedTracks.isNotEmpty ? library.mostPlayedTracks : library.recentlyAddedTracks,
            ),
          ),
        if (favorites.isNotEmpty)
          _CarouselSection(
            title: s.favorites,
            tracks: favorites,
            preferAlbum: true,
            onSeeAll: () => _openAll(context, s.favorites, library.favoriteTracks),
          ),
        if (added.isNotEmpty) ...[
          _SectionHeader(
            title: s.recentlyAdded,
            onSeeAll: () => _openAll(context, s.recentlyAdded, library.recentlyAddedTracks),
          ),
          for (var i = 0; i < added.length; i++)
            _AddedTile(track: added[i], queue: added, index: i),
        ],
      ],
    );
  }

  List<Track> _uniqueAlbums(List<Track> tracks) {
    final seen = <String>{};
    final out = <Track>[];
    for (final track in tracks) {
      if (!seen.add(track.albumKey)) continue;
      out.add(track);
      if (out.length >= 12) break;
    }
    return out;
  }

  void _openAll(BuildContext context, String title, List<Track> tracks) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => SmartPlaylistScreen(title: title, tracks: tracks)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
            child: Text(context.s.seeAll, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _CarouselSection extends StatelessWidget {
  const _CarouselSection({
    required this.title,
    required this.tracks,
    required this.onSeeAll,
    this.preferAlbum = false,
  });

  final String title;
  final List<Track> tracks;
  final VoidCallback onSeeAll;
  final bool preferAlbum;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, onSeeAll: onSeeAll),
        SizedBox(
          height: 176,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final track = tracks[i];
              final heading = preferAlbum && track.album != 'Unknown album' ? track.album : track.title;
              final subtitle = track.artist == 'Unknown artist' && heading != track.title
                  ? track.title
                  : s.displayArtist(track.artist);
              return SizedBox(
                width: 124,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    unawaited(context.read<PlayerController>().playTracks(tracks, start: i));
                    unawaited(openNowPlaying(context));
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverArt(track: track, size: 124, radius: 10, loadArtwork: true),
                      const SizedBox(height: 8),
                      Text(
                        heading == track.album ? s.displayAlbum(track.album) : heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddedTile extends StatelessWidget {
  const _AddedTile({required this.track, required this.queue, required this.index});

  final Track track;
  final List<Track> queue;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.s;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      leading: CoverArt(track: track, size: 52, radius: 8, loadArtwork: true),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${s.timeAgo(track.modifiedMs)} • ${s.displayArtist(track.artist)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.more_vert_rounded, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
        onPressed: () => showSongMenu(context, track),
      ),
      onTap: () {
        unawaited(context.read<PlayerController>().playTracks(queue, start: index));
        unawaited(openNowPlaying(context));
      },
    );
  }
}
