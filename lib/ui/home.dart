import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/artwork.dart';
import '../data/playback_file.dart';
import '../data/video_gif.dart';
import '../data/web_audio.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/settings.dart';
import 'alphabet_index.dart';
import 'customization_settings.dart';
import 'details.dart';
import 'equalizer.dart';
import 'library_folders.dart';
import 'now_playing.dart';
import 'platform_features.dart';
import 'recommended.dart';
import 'search.dart';
import 'settings.dart';
import 'theme_settings.dart';
import 'tools.dart';
import 'widgets.dart';
import 'zoom_settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: LibraryTab.values.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    final player = context.read<PlayerController>();
    try {
      await settings.load();
      await library.load();
      library.setMinDurationSec(settings.minDurationSec);
      await ArtworkStore.instance.init();
      await PlaybackCache.init();
      await player.init();
    } catch (error, stack) {
      debugPrint('Startup failed: $error\n$stack');
    }
    if (!mounted) return;
    unawaited(player.restoreSession());
    unawaited(_scan());
  }

  Future<void> _scan({List<String> extraFiles = const []}) async {
    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    final player = context.read<PlayerController>();
    await settings.requestMediaPermission();
    await library.scan(
      folders: settings.libraryFolders,
      minDurationSec: settings.minDurationSec,
      extraFiles: {...settings.extraFiles, ...extraFiles}.toList(),
    );
    if (!player.hasTrack) {
      await player.restoreSession();
    }
  }

  Future<void> _addFiles() async {
    final settings = context.read<SettingsController>();
    final library = context.read<LibraryController>();
    final files = await settings.pickAudioFiles();
    if (files.isEmpty) return;
    await settings.rememberFiles(files);
    final before = library.allTracks.length;
    await library.addFiles(files);
    if (!mounted) return;
    final added = library.allTracks.length - before;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 0 ? context.s.alreadyInLibrary : context.s.addedSongs(added))),
    );
  }

  Future<void> _addFolder() async {
    await context.read<SettingsController>().addFolder();
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final s = context.s;
    final tab = LibraryTab.values[_tabs.index];

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(tab, s)),
        bottom: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.zero,
                onTap: (index) {
                  if (LibraryTab.values[index] == LibraryTab.recommended) {
                    _scan();
                  }
                },
                tabs: [
                  Tab(text: s.tabRecommended),
                  Tab(text: s.tabSongs),
                  Tab(text: s.tabAlbums),
                  Tab(text: s.tabArtists),
                  Tab(text: s.tabPlaylists),
                  Tab(text: s.tabFolders),
                ],
              ),
        actions: [
          if (tab == LibraryTab.songs)
            PopupMenuButton<SongSort>(
              icon: const Icon(Icons.sort_rounded),
              onSelected: library.setSort,
              itemBuilder: (context) => [
                for (final sort in SongSort.values)
                  PopupMenuItem(value: sort, child: Text(_sortLabel(sort, s))),
              ],
            ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'eq':
                  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const EqualizerScreen()));
                case 'sleep':
                  showSleepTimerSheet(context);
                case 'settings':
                  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
                case 'folder':
                  await _addFolder();
                case 'files':
                  await _addFiles();
              }
            },
            itemBuilder: (context) {
              final s = context.s;
              return [
                PopupMenuItem(value: 'eq', child: Text(s.equalizer)),
                PopupMenuItem(value: 'sleep', child: Text(s.sleepTimer)),
                PopupMenuItem(value: 'settings', child: Text(s.settings)),
                PopupMenuItem(value: 'folder', child: Text(s.addFolder)),
                PopupMenuItem(value: 'files', child: Text(s.addFiles)),
              ];
            },
          ),
        ],
      ),
      drawer: _AppDrawer(onAddFolder: _addFolder, onAddFiles: _addFiles),
      body: Column(
        children: [
          if (library.scanning)
            LinearProgressIndicator(
              minHeight: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          if (library.scanMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(s.scanStatus(library.scanMessage), style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tab in LibraryTab.values)
                  _LibraryBody(tab: tab, onScan: _scan, onAddFiles: _addFiles, onAddFolder: _addFolder),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: MiniPlayer(
              onOpen: () => openNowPlaying(context),
              onPrevious: () => context.read<PlayerController>().previous(),
              onPlayPause: () => context.read<PlayerController>().playPause(),
              onNext: () => context.read<PlayerController>().next(),
            ),
      floatingActionButton: tab != LibraryTab.songs || library.songs.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton(
                onPressed: () async {
                  final player = context.read<PlayerController>();
                  final songs = library.songs;
                  await player.playTracks(songs);
                  if (!player.shuffle) await player.toggleShuffle();
                },
                child: const Icon(Icons.shuffle_rounded),
              ),
            ),
    );

    return scaffold;
  }

  String _titleFor(LibraryTab tab, S s) => switch (tab) {
        LibraryTab.recommended => s.appName,
        LibraryTab.songs => s.tabSongs,
        LibraryTab.albums => s.tabAlbums,
        LibraryTab.artists => s.tabArtists,
        LibraryTab.playlists => s.tabPlaylists,
        LibraryTab.folders => s.tabFolders,
      };

  String _sortLabel(SongSort sort, S s) => switch (sort) {
        SongSort.title => s.sortTitle,
        SongSort.artist => s.sortArtist,
        SongSort.album => s.sortAlbum,
        SongSort.duration => s.sortDuration,
        SongSort.date => s.sortDate,
      };
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.onAddFolder, required this.onAddFiles});

  final Future<void> Function() onAddFolder;
  final Future<void> Function() onAddFiles;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final theme = Theme.of(context);
    final s = context.s;
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            DrawerHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.library_music_rounded, size: 42, color: theme.colorScheme.primary),
                  const Spacer(),
                  Text('Null MP3', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(s.songsInLibrary(library.allTracks.length), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (pcParityEnabled)
              ListTile(
                leading: const Icon(Icons.zoom_in_rounded),
                title: Text(s.zoomSettings),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const ZoomSettingsScreen()),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(s.themeSettings),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ThemeSettingsScreen()));
              },
            ),
            if (pcParityEnabled)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(s.customization),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const CustomizationSettingsScreen()),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.equalizer_rounded),
              title: Text(s.equalizer),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const EqualizerScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.alarm_outlined),
              title: Text(s.sleepTimer),
              onTap: () {
                Navigator.pop(context);
                showSleepTimerSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(s.tabFolders),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const LibraryFoldersScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_rounded),
              title: Text(s.addFiles),
              onTap: () {
                Navigator.pop(context);
                onAddFiles();
              },
            ),
            if (webAudioSupported || videoGifSupported)
              ListTile(
                leading: const Icon(Icons.handyman_outlined),
                title: Text(s.tools),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ToolsScreen()));
                },
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(s.settings),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.tab,
    required this.onScan,
    required this.onAddFiles,
    required this.onAddFolder,
  });

  final LibraryTab tab;
  final Future<void> Function() onScan;
  final Future<void> Function() onAddFiles;
  final Future<void> Function() onAddFolder;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    if (library.allTracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: onScan,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: constraints.maxHeight,
                child: EmptyLibrary(
                  onScan: () => onScan(),
                  onAddFiles: () => onAddFiles(),
                  onAddFolder: () => onAddFolder(),
                  message: library.scanning ? context.s.scanStatus(library.scanMessage) : null,
                ),
              ),
            );
          },
        ),
      );
    }
    return switch (tab) {
      LibraryTab.recommended => RecommendedTab(onRefresh: onScan),
      LibraryTab.songs => _SongsTab(onRefresh: onScan),
      LibraryTab.albums => _AlbumsTab(onRefresh: onScan),
      LibraryTab.artists => _ArtistsTab(onRefresh: onScan),
      LibraryTab.playlists => _PlaylistsTab(onRefresh: onScan),
      LibraryTab.folders => _FoldersTab(onRefresh: onScan),
    };
  }
}

class _SongsTab extends StatefulWidget {
  const _SongsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends State<_SongsTab> {
  final _scroll = ScrollController();
  String? _activeLetter;

  static const _itemExtent = 64.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _labelFor(Track track, SongSort sort) => switch (sort) {
        SongSort.title => track.title,
        SongSort.artist => track.artist,
        SongSort.album => track.album,
        SongSort.duration || SongSort.date => track.title,
      };

  void _jumpToLetter(String letter, List<String> labels, List<String> letters) {
    if (!_scroll.hasClients) return;
    final first = firstIndexByLetter(labels);
    final index = indexForLetter(letter, first, letters);
    final max = _scroll.position.maxScrollExtent;
    _scroll.jumpTo((index * _itemExtent).clamp(0, max));
    setState(() => _activeLetter = letter);
  }

  void _syncActive(List<String> labels) {
    if (!_scroll.hasClients || labels.isEmpty) return;
    final index = (_scroll.offset / _itemExtent).floor().clamp(0, labels.length - 1);
    final letter = indexLetterFor(labels[index]);
    if (letter != _activeLetter) {
      setState(() => _activeLetter = letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final currentPath = context.select<PlayerController, String?>((player) => player.current?.path);
    final s = context.s;
    final songs = library.songs;
    final labels = [for (final track in songs) _labelFor(track, library.sort)];
    final letters = alphabetLettersFor(labels);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
          child: Row(
            children: [
              Text(
                s.songsCount(songs.length),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
              ),
              const Spacer(),
              PopupMenuButton<SongSort>(
                tooltip: s.sort,
                onSelected: library.setSort,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _songSortLabel(library.sort, s),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                            ),
                      ),
                      const Icon(Icons.arrow_downward_rounded, size: 14),
                    ],
                  ),
                ),
                itemBuilder: (context) => [
                  for (final sort in SongSort.values)
                    PopupMenuItem(value: sort, child: Text(_songSortLabel(sort, s))),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0) _syncActive(labels);
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(right: 18, bottom: 88),
                    itemCount: songs.length,
                    itemExtent: _itemExtent,
                    itemBuilder: (context, i) {
                      final track = songs[i];
                      return SongTile(
                        key: ValueKey(track.path),
                        track: track,
                        selected: currentPath == track.path,
                        onTap: () => context.read<PlayerController>().playTracks(songs, start: i),
                      );
                    },
                  ),
                ),
              ),
              if (songs.length >= 12)
                Positioned(
                  right: 0,
                  top: 4,
                  bottom: 88,
                  child: AlphabetJumpBar(
                    labels: letters,
                    activeLetter: _activeLetter,
                    onSelect: (letter) => _jumpToLetter(letter, labels, letters),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _songSortLabel(SongSort sort, S s) => switch (sort) {
        SongSort.title => s.sortTitle,
        SongSort.artist => s.sortArtist,
        SongSort.album => s.sortAlbum,
        SongSort.duration => s.sortDuration,
        SongSort.date => s.sortDate,
      };
}

class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final albums = context.watch<LibraryController>().albums;
    final s = context.s;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1200 ? 5 : width > 900 ? 4 : width > 600 ? 3 : 2;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final album = albums[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AlbumDetailScreen(album: album))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: CoverArt(track: album.representative, radius: 14, expand: true)),
              const SizedBox(height: 8),
              Text(s.displayAlbum(album.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(s.displayArtist(album.artist), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    ),
    );
  }
}

class _ArtistsTab extends StatefulWidget {
  const _ArtistsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<_ArtistsTab> {
  final _scroll = ScrollController();
  String? _activeLetter;
  static const _itemExtent = 72.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artists = context.watch<LibraryController>().artists;
    final s = context.s;
    final labels = [for (final artist in artists) artist.name];
    final letters = alphabetLettersFor(labels);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 && _scroll.hasClients && labels.isNotEmpty) {
              final index = (_scroll.offset / _itemExtent).floor().clamp(0, labels.length - 1);
              final letter = indexLetterFor(labels[index]);
              if (letter != _activeLetter) setState(() => _activeLetter = letter);
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(right: 18),
            itemCount: artists.length,
            itemExtent: _itemExtent,
            itemBuilder: (context, i) {
              final artist = artists[i];
              return ListTile(
                leading: ClipOval(child: CoverArt(track: artist.tracks.first, size: 52, radius: 26)),
                title: Text(s.displayArtist(artist.name), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(s.albumsAndSongs(artist.albums.length, artist.tracks.length)),
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ArtistDetailScreen(artist: artist))),
              );
            },
          ),
          ),
        ),
        if (artists.length >= 12)
          Positioned(
            right: 0,
            top: 4,
            bottom: 8,
            child: AlphabetJumpBar(
              labels: letters,
              activeLetter: _activeLetter,
              onSelect: (letter) {
                if (!_scroll.hasClients) return;
                final index = indexForLetter(letter, firstIndexByLetter(labels), letters);
                _scroll.jumpTo((index * _itemExtent).clamp(0, _scroll.position.maxScrollExtent));
                setState(() => _activeLetter = letter);
              },
            ),
          ),
      ],
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final s = context.s;
    final tiles = <Widget>[
      _SmartPlaylistTile(
        icon: Icons.favorite_rounded,
        title: s.favorites,
        subtitle: s.songsCount(library.favoriteTracks.length),
        onTap: () => _openSmart(context, s.favorites, library.favoriteTracks),
      ),
      _SmartPlaylistTile(
        icon: Icons.history_rounded,
        title: s.recentlyPlayed,
        subtitle: s.songsCount(library.recentlyPlayedTracks.length),
        onTap: () => _openSmart(context, s.recentlyPlayed, library.recentlyPlayedTracks),
      ),
      _SmartPlaylistTile(
        icon: Icons.fiber_new_rounded,
        title: s.recentlyAdded,
        subtitle: s.songsCount(library.recentlyAddedTracks.length),
        onTap: () => _openSmart(context, s.recentlyAdded, library.recentlyAddedTracks),
      ),
      _SmartPlaylistTile(
        icon: Icons.trending_up_rounded,
        title: s.mostPlayed,
        subtitle: s.songsCount(library.mostPlayedTracks.length),
        onTap: () => _openSmart(context, s.mostPlayed, library.mostPlayedTracks),
      ),
      ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(s.newPlaylist),
        onTap: () async {
          final name = await promptName(context, title: s.newPlaylist);
          if (name == null || name.trim().isEmpty) return;
          await library.createPlaylist(name.trim());
        },
      ),
      for (final playlist in library.playlists)
        ListTile(
          leading: CoverArt(
            track: library.tracksForPlaylist(playlist).isEmpty ? null : library.tracksForPlaylist(playlist).first,
            size: 52,
          ),
          title: Text(playlist.name),
          subtitle: Text(s.songsCount(playlist.trackPaths.length)),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () async {
              final action = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(s.rename),
                        onTap: () => Navigator.pop(context, 'rename'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: Text(s.delete),
                        onTap: () => Navigator.pop(context, 'delete'),
                      ),
                    ],
                  ),
                ),
              );
              if (action == 'rename') {
                if (!context.mounted) return;
                final name = await promptName(context, title: context.s.renamePlaylist, initial: playlist.name);
                if (name != null && name.trim().isNotEmpty) {
                  await library.renamePlaylist(playlist.id, name.trim());
                }
              } else if (action == 'delete') {
                await library.deletePlaylist(playlist.id);
              }
            },
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => PlaylistDetailScreen(playlistId: playlist.id)),
          ),
        ),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: tiles,
      ),
    );
  }

  void _openSmart(BuildContext context, String title, List<Track> tracks) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => SmartPlaylistScreen(title: title, tracks: tracks)),
    );
  }
}

class _SmartPlaylistTile extends StatelessWidget {
  const _SmartPlaylistTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _FoldersTab extends StatelessWidget {
  const _FoldersTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final folders = context.watch<LibraryController>().folders;
    final entries = folders.entries.toList();
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return ListTile(
          leading: const Icon(Icons.folder_rounded, size: 36),
          title: Text(entry.value.first.folderName),
          subtitle: Text('${context.s.songsCount(entry.value.length)} • ${entry.key}', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FolderDetailScreen(folder: entry.key, tracks: entry.value),
            ),
          ),
        );
      },
    ),
    );
  }
}
