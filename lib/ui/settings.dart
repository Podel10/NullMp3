import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/library.dart';
import '../state/settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Section(s.appearance),
          ListTile(
            title: Text(s.language),
            subtitle: Text(settings.language.nativeName),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _chooseLanguage(context, settings),
          ),
          _Section(s.library),
          ListTile(
            title: Text(s.tabFolders),
            subtitle: Text(s.foldersHint),
          ),
          ListTile(
            title: Text(s.skipShortTracks),
            subtitle: Text(settings.minDurationSec == 0 ? s.off : s.seconds(settings.minDurationSec)),
          ),
          Slider(
            min: 0,
            max: 60,
            divisions: 12,
            value: settings.minDurationSec.toDouble(),
            label: settings.minDurationSec == 0 ? s.off : '${settings.minDurationSec}s',
            onChanged: (value) => settings.setMinDuration(value.round()),
          ),
          ListTile(
            title: Text(s.librarySizeLabel),
            subtitle: Text(s.librarySize(library.songs.length, library.albums.length, library.artists.length)),
          ),
          _Section(s.hiddenSongs),
          if (library.hiddenTracks.isEmpty)
            ListTile(
              title: Text(s.nothingHidden),
              subtitle: Text(s.hiddenHint),
            )
          else
            for (final track in library.hiddenTracks)
              ListTile(
                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(s.displayArtist(track.artist), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: () => library.unhideTrack(track.path),
                  child: Text(s.show),
                ),
              ),
          _Section(s.about),
          ListTile(
            title: Text(s.appName),
            subtitle: Text(s.aboutBlurb),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseLanguage(BuildContext context, SettingsController settings) async {
    final selected = await showDialog<AppLanguage>(
      context: context,
      builder: (context) {
        final s = context.s;
        return SimpleDialog(
          title: Text(s.chooseLanguage),
          children: [
            for (final language in AppLanguage.values)
              ListTile(
                leading: Icon(settings.language == language ? Icons.check_rounded : null),
                title: Text(language.nativeName),
                onTap: () => Navigator.pop(context, language),
              ),
          ],
        );
      },
    );
    if (selected != null) await settings.setLanguage(selected);
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
