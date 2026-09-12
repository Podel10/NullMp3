import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../data/artwork.dart';
import '../data/file_actions.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import 'widgets.dart';

Future<void> showTagEditor(BuildContext context, Track track) {
  return showDialog<void>(
    context: context,
    builder: (context) => TagEditorDialog(track: track),
  );
}

class TagEditorDialog extends StatefulWidget {
  const TagEditorDialog({super.key, required this.track});

  final Track track;

  @override
  State<TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<TagEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _album;
  late final TextEditingController _artist;
  late final TextEditingController _albumArtist;
  late final TextEditingController _composer;
  Uint8List? _cover;
  String? _coverMime;
  bool _coverChanged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.track.title);
    _album = TextEditingController(text: widget.track.album == 'Unknown album' ? '' : widget.track.album);
    _artist = TextEditingController(text: widget.track.artist == 'Unknown artist' ? '' : widget.track.artist);
    _albumArtist = TextEditingController(text: widget.track.albumArtist ?? '');
    _composer = TextEditingController(text: widget.track.composer ?? '');
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final bytes = await ArtworkStore.instance.get(widget.track.path);
    if (mounted && bytes != null) setState(() => _cover = bytes);
    try {
      final meta = readAllMetadata(File(widget.track.path), getImage: false);
      if (!mounted) return;
      switch (meta) {
        case Mp3Metadata m:
          _albumArtist.text = m.bandOrOrchestra ?? _albumArtist.text;
          _composer.text = m.composer ?? _composer.text;
        case VorbisMetadata m:
          if (m.composer.isNotEmpty) _composer.text = m.composer.first;
        case ApeMetadata m:
          _albumArtist.text = m.albumArtist ?? _albumArtist.text;
          _composer.text = m.composer ?? _composer.text;
        default:
          break;
      }
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _album.dispose();
    _artist.dispose();
    _albumArtist.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final files = await FilePicker.pickFiles(type: FileType.image, dialogTitle: context.s.cover);
    if (files.isEmpty) return;
    final file = files.first;
    final path = file.path ?? (file.uri.scheme == 'file' ? file.uri.toFilePath() : null);
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _cover = bytes;
      _coverMime = _mimeFor(path);
      _coverChanged = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final library = contextLibrary(context, listen: false);
    final player = contextPlayer(context, listen: false);
    final oldPath = widget.track.path;
    final wasCurrent = player.current?.path == oldPath;
    final wasPlaying = wasCurrent && player.playing;
    final position = wasCurrent ? player.player.position : Duration.zero;
    if (wasPlaying) await player.player.pause();

    try {
      _writeTags();
      await _finishSave(library, player, oldPath: oldPath, wasPlaying: wasPlaying, position: position);
    } catch (error) {
      var saved = false;
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.request();
        if (status.isGranted) {
          try {
            _writeTags();
            await _finishSave(library, player, oldPath: oldPath, wasPlaying: wasPlaying, position: position);
            saved = true;
          } catch (_) {}
        }
      }
      if (!saved && mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.s.saveTagsFailed('$error'))),
        );
        if (wasPlaying) await player.player.play();
      }
    }
  }

  Future<void> _finishSave(
    LibraryController library,
    PlayerController player, {
    required String oldPath,
    required bool wasPlaying,
    required Duration position,
  }) async {
    if (_coverChanged && _cover != null) {
      await ArtworkStore.instance.put(oldPath, _cover!);
    }
    final title = _title.text.trim().isEmpty ? widget.track.title : _title.text.trim();
    var path = oldPath;
    final renamed = await renameAudioFile(oldPath, title);
    if (renamed != null && renamed.isNotEmpty) path = renamed;
    if (path != oldPath) {
      await ArtworkStore.instance.rekey(oldPath, path);
    }
    final updated = widget.track.copyWith(
      path: path,
      title: title,
      artist: _artist.text.trim().isEmpty ? 'Unknown artist' : _artist.text.trim(),
      album: _album.text.trim().isEmpty ? 'Unknown album' : _album.text.trim(),
      albumArtist: _albumArtist.text.trim(),
      composer: _composer.text.trim(),
    );
    if (path == oldPath) {
      library.replaceTrack(updated);
      player.replaceQueuedTrack(updated);
      if (wasPlaying) await player.player.play();
    } else {
      await library.retargetTrack(oldPath, updated);
      await player.retargetQueuedTrack(oldPath, updated, play: wasPlaying, position: position);
    }
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(path == oldPath ? context.s.tagsSaved : context.s.tagsSavedRenamed),
        ),
      );
    }
  }

  void _writeTags() {
    updateMetadata(File(widget.track.path), (metadata) {
      metadata.setTitle(_title.text.trim());
      metadata.setArtist(_artist.text.trim());
      metadata.setAlbum(_album.text.trim());
      switch (metadata) {
        case Mp3Metadata m:
          m.bandOrOrchestra = _albumArtist.text.trim();
          m.composer = _composer.text.trim();
        case VorbisMetadata m:
          m.composer = [_composer.text.trim()];
        case ApeMetadata m:
          m.albumArtist = _albumArtist.text.trim();
          m.composer = _composer.text.trim();
        default:
          break;
      }
      if (_coverChanged && _cover != null) {
        metadata.setPictures([
          Picture(_cover!, _coverMime ?? 'image/jpeg', PictureType.coverFront),
        ]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    const fieldStyle = InputDecoration(
      isDense: true,
      border: UnderlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(vertical: 8),
    );
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final compact = keyboard > 80;
    final coverSize = compact ? 0.0 : 112.0;
    final maxHeight = media.size.height - keyboard - 16;
    return Dialog(
      alignment: Alignment.bottomCenter,
      backgroundColor: const Color(0xFF102A36),
      insetPadding: EdgeInsets.fromLTRB(12, 8, 12, 8 + keyboard),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight.clamp(240, 720)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(s.tagEditor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      ),
                    if (!compact)
                      Center(
                        child: SizedBox(
                          width: coverSize,
                          height: coverSize,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _cover == null
                                      ? const ColoredBox(
                                          color: Color(0xFF3A4A56),
                                          child: Icon(Icons.music_note, color: Colors.white54, size: 56),
                                        )
                                      : Image.memory(_cover!, fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Material(
                                  color: const Color(0xFF1C3A48),
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: _pickCover,
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.edit, size: 18, color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!compact) const SizedBox(height: 10),
                    TextField(
                      controller: _title,
                      textInputAction: TextInputAction.next,
                      decoration: fieldStyle.copyWith(labelText: s.fieldTitle),
                    ),
                    TextField(
                      controller: _album,
                      textInputAction: TextInputAction.next,
                      decoration: fieldStyle.copyWith(labelText: s.fieldAlbum),
                    ),
                    TextField(
                      controller: _artist,
                      textInputAction: TextInputAction.next,
                      decoration: fieldStyle.copyWith(labelText: s.fieldArtist),
                    ),
                    TextField(
                      controller: _albumArtist,
                      textInputAction: TextInputAction.next,
                      decoration: fieldStyle.copyWith(labelText: s.fieldAlbumArtist),
                    ),
                    TextField(
                      controller: _composer,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_saving) _save();
                      },
                      decoration: fieldStyle.copyWith(labelText: s.fieldComposer),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(s.cancel),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(s.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _mimeFor(String path) {
    return switch (p.extension(path).toLowerCase()) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }
}
