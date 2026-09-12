import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/media_index.dart';
import '../l10n/strings.dart';
import '../state/library.dart';
import '../state/settings.dart';

class LibraryFoldersScreen extends StatefulWidget {
  const LibraryFoldersScreen({super.key});

  @override
  State<LibraryFoldersScreen> createState() => _LibraryFoldersScreenState();
}

class _LibraryFoldersScreenState extends State<LibraryFoldersScreen> {
  late Future<List<DeviceAudioFolder>> _future;

  @override
  void initState() {
    super.initState();
    _future = queryDeviceAudioFolders();
  }

  Future<void> _scan() {
    final settings = context.read<SettingsController>();
    return context.read<LibraryController>().scan(
          folders: settings.libraryFolders,
          minDurationSec: settings.minDurationSec,
          extraFiles: settings.extraFiles,
        );
  }

  Future<void> _add(String path, {String? label}) async {
    final added = await context.read<SettingsController>().addFolderPath(path);
    if (!added || !mounted) return;
    await _scan();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.s.addedFolder(label ?? path))),
    );
  }

  Future<void> _remove(String path, {String? label}) async {
    await context.read<SettingsController>().removeFolder(path);
    if (!mounted) return;
    await _scan();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.s.removedFolder(label ?? path))),
    );
  }

  Future<void> _pick() async {
    await context.read<SettingsController>().addFolder();
    if (!mounted) return;
    await _scan();
  }

  String _label(String path) {
    final parts = path.replaceAll('\\', '/').split('/').where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[parts.length - 2]}/${parts.last}';
    return parts.isEmpty ? path : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final theme = Theme.of(context);
    final s = context.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tabFolders),
        actions: [
          IconButton(
            onPressed: _pick,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            title: Text(s.libraryFolders),
            subtitle: Text(s.libraryFoldersHint),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              s.inLibrary,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (settings.libraryFolders.isEmpty)
            ListTile(
              title: Text(s.nothingSelected),
              subtitle: Text(s.tapFolderBelow),
            )
          else
            for (final folder in settings.libraryFolders)
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(_label(folder)),
                subtitle: Text(folder, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  onPressed: () => _remove(folder, label: _label(folder)),
                  icon: const Icon(Icons.close_rounded),
                ),
                onTap: () => _remove(folder, label: _label(folder)),
              ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              s.foldersWithMostTracks,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FutureBuilder<List<DeviceAudioFolder>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              final selected = settings.libraryFolders;
              final folders = [
                for (final folder in snapshot.data ?? const <DeviceAudioFolder>[])
                  if (!settings.folderIsSelected(folder.path)) folder,
              ];
              if (folders.isEmpty) {
                return ListTile(
                  title: Text(selected.isEmpty ? s.noFoldersFound : s.allFoldersAdded),
                  subtitle: Text(s.pickFolderYourself),
                );
              }
              return Column(
                children: [
                  for (final folder in folders)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.name),
                      subtitle: Text(
                        s.tracksInPath(folder.count, folder.path),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.add_rounded),
                      onTap: () => _add(folder.path, label: folder.name),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
