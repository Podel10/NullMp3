import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/library.dart';
import '../state/player.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final player = context.watch<PlayerController>();
    final s = context.s;
    final results = library.search(_query)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.searchHint,
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: _query.isEmpty
          ? Center(child: Text(s.searchYourLibrary))
          : results.isEmpty
              ? Center(child: Text(s.noMatches))
              : ListView.builder(
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final track = results[i];
                    return SongTile(
                      track: track,
                      selected: player.current?.path == track.path,
                      onTap: () => player.playTracks(results, start: i),
                    );
                  },
                ),
    );
  }
}
