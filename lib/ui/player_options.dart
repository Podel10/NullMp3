import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/artwork.dart';
import '../data/cover_search.dart';
import '../data/share_export.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/settings.dart';
import 'driving_mode.dart';
import 'equalizer.dart';
import 'lock_player.dart';
import 'lyrics_page.dart';
import 'music_editor.dart';
import 'cover_search.dart';
import 'settings.dart';
import 'speed_sheet.dart';
import 'tag_editor.dart';
import 'widgets.dart';

void showPlayerOptionsSheet(BuildContext context, Track track, {Playlist? playlist}) {
  final host = context;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFF0E2A38),
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => PlayerOptionsSheet(track: track, playlist: playlist, host: host),
  );
}

class PlayerOptionsSheet extends StatelessWidget {
  const PlayerOptionsSheet({
    super.key,
    required this.track,
    required this.host,
    this.playlist,
  });

  final Track track;
  final Playlist? playlist;
  final BuildContext host;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final player = context.watch<PlayerController>();
    final settings = context.watch<SettingsController>();
    final library = context.watch<LibraryController>();
    final accent = Theme.of(context).colorScheme.primary;
    final speed = settings.speed;
    final speedText = formatPlaybackRate(speed);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            Text(
              s.playingFrom,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54, fontSize: 12),
            ),
            Text(
              track.folderName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 0,
              childAspectRatio: 1.08,
              children: [
                _GridAction(
                  icon: Icons.lyrics_outlined,
                  label: s.lyrics,
                  onTap: () => _open(context, LyricsScreen(track: track)),
                ),
                _GridAction(
                  icon: Icons.playlist_add_rounded,
                  label: s.addToPlaylistEllipsis,
                  onTap: () async {
                    Navigator.pop(context);
                    if (!host.mounted) return;
                    await showAddToPlaylistSheet(host, track);
                  },
                ),
                _GridAction(
                  icon: Icons.display_settings_outlined,
                  label: s.displaySettings,
                  onTap: () async {
                    Navigator.pop(context);
                    if (!host.mounted) return;
                    await showTagEditor(host, track);
                  },
                ),
                _GridAction(
                  icon: Icons.info_outline_rounded,
                  label: s.details,
                  onTap: () {
                    Navigator.pop(context);
                    if (!host.mounted) return;
                    showTrackInfo(host, track);
                  },
                ),
                _GridAction(
                  label: s.playbackSpeed,
                  badge: '${speedText}X',
                  onTap: () {
                    Navigator.pop(context);
                    if (!host.mounted) return;
                    showSpeedPitchSheet(host);
                  },
                ),
                _GridAction(
                  icon: Icons.equalizer_rounded,
                  label: s.equalizer,
                  onTap: () => _open(context, const EqualizerScreen()),
                ),
                _GridAction(
                  icon: Icons.content_cut_rounded,
                  label: s.musicEditor,
                  onTap: () => _open(context, MusicEditorScreen(track: track)),
                ),
                _GridAction(
                  icon: Icons.drive_eta_outlined,
                  label: s.drivingMode,
                  onTap: () => _open(context, const DrivingModeScreen(), playTrack: true),
                ),
                _GridAction(
                  icon: Icons.share_outlined,
                  label: s.share,
                  onTap: () => _share(context),
                ),
                _GridAction(
                  icon: Icons.auto_awesome_rounded,
                  label: s.autoStyle,
                  onTap: () => _openOnline(context, CoverSearchScreen(track: track)),
                ),
                _GridAction(
                  icon: Icons.gif_box_outlined,
                  label: s.searchGif,
                  onTap: () => _openOnline(
                    context,
                    CoverSearchScreen(track: track, kind: CoverSearchKind.gif),
                  ),
                ),
                _GridAction(
                  icon: Icons.image_search_rounded,
                  label: s.searchImage,
                  onTap: () => _openOnline(
                    context,
                    CoverSearchScreen(track: track, kind: CoverSearchKind.image),
                  ),
                ),
                _GridAction(
                  icon: Icons.phonelink_lock_rounded,
                  label: s.lockScreen,
                  onTap: () => _open(context, const LockPlayerScreen(), playTrack: true),
                ),
                _GridAction(
                  icon: Icons.settings_outlined,
                  label: s.settings,
                  onTap: () => _open(context, const SettingsScreen()),
                ),
                _GridAction(
                  icon: Icons.visibility_off_outlined,
                  label: s.hide,
                  onTap: () => _hide(context, library, player),
                ),
                _GridAction(
                  icon: Icons.delete_outline_rounded,
                  label: s.deleteFromDevice,
                  onTap: () => _delete(context, library, player, settings),
                ),
                if (playlist != null)
                  _GridAction(
                    icon: Icons.remove_circle_outline_rounded,
                    label: s.removeFromPlaylist,
                    onTap: () {
                      library.removeFromPlaylist(playlist!.id, track.path);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _ToggleCell(
                    title: s.playPauseFade,
                    subtitle: s.milliseconds300,
                    value: settings.pauseFade,
                    accent: accent,
                    onChanged: settings.setPauseFade,
                  ),
                ),
                Expanded(
                  child: _ToggleCell(
                    title: s.crossfade,
                    value: settings.crossfade,
                    accent: accent,
                    onChanged: settings.setCrossfade,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  const Icon(Icons.volume_up_outlined, size: 20, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      value: settings.volume,
                      onChanged: player.setVolume,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOnline(BuildContext sheetContext, Widget page) async {
    if (host.read<SettingsController>().offlineMode) {
      Navigator.pop(sheetContext);
      if (!host.mounted) return;
      ScaffoldMessenger.of(host).showSnackBar(SnackBar(content: Text(host.s.offlineModeHint)));
      return;
    }
    await _open(sheetContext, page);
  }

  Future<void> _open(BuildContext sheetContext, Widget page, {bool playTrack = false}) async {
    if (playTrack) {
      final player = contextPlayer(host, listen: false);
      final library = contextLibrary(host, listen: false);
      if (player.current?.path != track.path) {
        final queued = player.queue.indexWhere((item) => item.path == track.path);
        if (queued >= 0) {
          await player.playAt(queued);
        } else {
          final songs = library.songs;
          final start = songs.indexWhere((item) => item.path == track.path);
          if (start >= 0) {
            await player.playTracks(songs, start: start);
          } else {
            await player.playTracks([track]);
          }
        }
      }
      player.ensureBrowsableQueue();
    }
    if (!sheetContext.mounted) return;
    Navigator.pop(sheetContext);
    if (!host.mounted) return;
    await Navigator.of(host).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _hide(BuildContext sheetContext, LibraryController library, PlayerController player) async {
    final s = sheetContext.s;
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (context) => AlertDialog(
        title: Text(s.hideTrack),
        content: Text(s.hideTrackBody(track.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.hide)),
        ],
      ),
    );
    if (confirmed != true || !sheetContext.mounted) return;
    Navigator.pop(sheetContext);
    await player.removePath(track.path);
    await library.hideTrack(track.path);
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(SnackBar(content: Text(host.s.hiddenFromLibrary)));
  }

  Future<void> _delete(
    BuildContext sheetContext,
    LibraryController library,
    PlayerController player,
    SettingsController settings,
  ) async {
    final s = sheetContext.s;
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (context) => AlertDialog(
        title: Text(s.deleteFromDevice),
        content: Text(s.deleteFileBody(track.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.delete)),
        ],
      ),
    );
    if (confirmed != true || !sheetContext.mounted) return;
    Navigator.pop(sheetContext);
    final wasPlaying = player.playing;
    final wasCurrent = player.current?.path == track.path;
    if (wasCurrent) {
      await player.player.pause();
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final error = await library.deleteFromDevice(track);
    if (error == null) {
      await player.removePath(track.path, resume: wasPlaying);
      await settings.forgetFile(track.path);
    } else if (wasCurrent && wasPlaying) {
      // The file survived, so undo the pause that freed it for deletion.
      await player.resumePlayback();
    }
    if (!host.mounted) return;
    ScaffoldMessenger.of(host).showSnackBar(
      SnackBar(content: Text(error == null ? host.s.fileDeleted : host.s.deleteResult(error))),
    );
  }

  Future<void> _share(BuildContext sheetContext) async {
    Navigator.pop(sheetContext);
    if (!host.mounted) return;
    var preparing = true;
    showDialog<void>(
      context: host,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(host.s.preparingShare)),
          ],
        ),
      ),
    );
    try {
      final cover = await ArtworkStore.instance.get(track.path);
      final path = await exportTrackForShare(track: track, cover: cover);
      if (host.mounted && preparing) {
        Navigator.of(host, rootNavigator: true).pop();
        preparing = false;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              path,
              mimeType: shareAudioMime(path),
            ),
          ],
          text: '${track.artist} — ${track.title}',
        ),
      );
    } catch (error) {
      if (host.mounted && preparing) {
        Navigator.of(host, rootNavigator: true).pop();
        preparing = false;
      }
      if (!host.mounted) return;
      ScaffoldMessenger.of(host).showSnackBar(
        SnackBar(content: Text(host.s.shareFailed('$error'))),
      );
    }
  }
}

class _GridAction extends StatelessWidget {
  const _GridAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.badge,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 22,
              child: badge != null
                  ? Text(
                      badge!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: 0.1,
                          ),
                    )
                  : Icon(icon, size: 22, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    height: 1.1,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.title,
    required this.value,
    required this.onChanged,
    required this.accent,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.15),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54, fontSize: 10),
                  ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.82,
            child: Switch(
              value: value,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeThumbColor: accent,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
