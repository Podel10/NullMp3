import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/settings.dart';
import 'app_labeled_slider.dart';

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
          AppLabeledSlider(
            min: 0,
            max: 60,
            divisions: 12,
            value: settings.minDurationSec.toDouble(),
            labelOf: (value) => value.round() == 0 ? s.off : '${value.round()}s',
            onChanged: (value) => settings.setMinDuration(value.round()),
          ),
          ListTile(
            title: Text(s.librarySizeLabel),
            subtitle: Text(s.librarySize(library.songs.length, library.albums.length, library.artists.length)),
          ),
          _Section(s.statistics),
          ListTile(
            title: Text(s.listenTime),
            subtitle: Text(s.listenHours(library.listenMs)),
          ),
          ListTile(
            title: Text(s.tracksListened),
            subtitle: Text('${library.listenedTrackCount}'),
          ),
          if (!settings.statsEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                s.statisticsOffHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FilledButton.tonal(
              onPressed: () async {
                final player = context.read<PlayerController>();
                if (settings.statsEnabled) {
                  player.discardListenClock();
                  await library.clearListenStats();
                  await settings.setStatsEnabled(false);
                } else {
                  await settings.setStatsEnabled(true);
                  player.resumeListenClock();
                }
              },
              child: Text(settings.statsEnabled ? s.disableStatistics : s.enableStatistics),
            ),
          ),
          SwitchListTile(
            secondary: Icon(settings.offlineMode ? Icons.cloud_off_rounded : Icons.cloud_rounded),
            title: Text(s.offlineMode),
            subtitle: Text(s.offlineModeHint),
            value: settings.offlineMode,
            onChanged: settings.setOfflineMode,
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
          _Section(s.supportProject),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              s.supportProjectHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _SupportAddressTile(
            label: s.supportBnbEth,
            address: '0x5Ac0E1472895F3457771558cC4EDeb712AB69F91',
            copiedLabel: s.supportAddressCopied,
          ),
          _SupportAddressTile(
            label: s.supportTon,
            address: 'UQA_sZk8ChNLMx2AY_HnIGrS6DtRWgXe2DqsNuk5-F0i-pBB',
            copiedLabel: s.supportAddressCopied,
          ),
          _Section(s.faq),
          _FaqTile(question: s.faqMicQ, answer: s.faqMicA),
          _FaqTile(question: s.faqWavesQ, answer: s.faqWavesA),
          _FaqTile(question: s.faqRecordQ, answer: s.faqRecordA),
        ],
      ),
    );
  }

  Future<void> _chooseLanguage(BuildContext context, SettingsController settings) async {
    final selected = await showDialog<AppLanguage>(
      context: context,
      builder: (context) => _LanguageDialog(current: settings.language),
    );
    if (selected != null) await settings.setLanguage(selected);
  }
}

class _SupportAddressTile extends StatelessWidget {
  const _SupportAddressTile({
    required this.label,
    required this.address,
    required this.copiedLabel,
  });

  final String label;
  final String address;
  final String copiedLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(address),
      trailing: const Icon(Icons.copy_rounded),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: address));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copiedLabel)),
        );
      },
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(question),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            answer,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({required this.current});
  final AppLanguage current;

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final q = _query.trim().toLowerCase();
    final items = AppLanguage.all.where((language) {
      if (q.isEmpty) return true;
      return language.nativeName.toLowerCase().contains(q) ||
          language.code.toLowerCase().contains(q);
    }).toList(growable: false);
    return Dialog(
      child: SizedBox(
        width: 420,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      s.chooseLanguage,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: s.searchLanguages,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final language = items[index];
                  final selected = language == widget.current;
                  return ListTile(
                    leading: Icon(selected ? Icons.check_rounded : null),
                    title: Text(language.nativeName),
                    subtitle: Text(language.code),
                    onTap: () => Navigator.pop(context, language),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
