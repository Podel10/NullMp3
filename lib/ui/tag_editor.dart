import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/artwork.dart';
import '../data/cover_image.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/settings.dart';
import 'cover_crop.dart';
import 'cover_media.dart';
import 'cover_search.dart';
import 'widgets.dart';

Future<void> showTagEditor(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF102A36),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => TagEditorSheet(track: track),
  );
}

class TagEditorSheet extends StatefulWidget {
  const TagEditorSheet({super.key, required this.track});

  final Track track;

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _album;
  late final TextEditingController _artist;
  late final TextEditingController _albumArtist;
  late final TextEditingController _composer;
  Uint8List? _cover;
  bool _coverChanged = false;
  bool _saving = false;
  bool _picking = false;
  String? _error;
  late CoverShape _coverShape;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.track.title);
    _album = TextEditingController(text: widget.track.album == 'Unknown album' ? '' : widget.track.album);
    _artist = TextEditingController(text: widget.track.artist == 'Unknown artist' ? '' : widget.track.artist);
    _albumArtist = TextEditingController(text: widget.track.albumArtist ?? '');
    _composer = TextEditingController(text: widget.track.composer ?? '');
    _coverShape = widget.track.coverShape;
    ArtworkStore.instance.get(widget.track.path).then((bytes) {
      if (mounted && bytes != null) setState(() => _cover = bytes);
    });
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
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await pickCoverBytes();
      if (!mounted) return;
      if (picked == null || picked.isEmpty) {
        setState(() => _picking = false);
        return;
      }
      if (!mounted) return;
      setState(() => _picking = false);
      final cropped = await showCoverCrop(context, picked);
      if (!mounted) return;
      if (cropped == null || cropped.isEmpty) return;
      final cover = await downscaleCover(cropped);
      if (!mounted) return;
      setState(() {
        _cover = cover;
        _coverChanged = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = context.s.pickCoverFailed;
      });
    }
  }

  Future<void> _autoCover() async {
    if (_picking) return;
    if (context.read<SettingsController>().offlineMode) {
      setState(() => _error = context.s.offlineModeHint);
      return;
    }
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await showCoverSearch(context, widget.track);
      if (!mounted) return;
      setState(() {
        _picking = false;
        if (picked != null && picked.isNotEmpty) {
          _cover = picked;
          _coverChanged = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = context.s.coverSearchFailed;
      });
    }
  }

  Future<void> _cropCurrentCover() async {
    final current = _cover;
    if (current == null || isAnimatedCover(current) || _picking) return;
    final cropped = await showCoverCrop(context, current);
    if (!mounted || cropped == null || cropped.isEmpty) return;
    final cover = await downscaleCover(cropped);
    if (!mounted) return;
    setState(() {
      _cover = cover;
      _coverChanged = true;
    });
  }

  void _setCoverShape(CoverShape shape) {
    if (_coverShape == shape) return;
    setState(() => _coverShape = shape);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final title = _title.text.trim().isEmpty ? widget.track.title : _title.text.trim();
    final artist = _artist.text.trim().isEmpty ? 'Unknown artist' : _artist.text.trim();
    final album = _album.text.trim().isEmpty ? 'Unknown album' : _album.text.trim();
    final updated = widget.track.copyWith(
      title: title,
      artist: artist,
      album: album,
      albumArtist: _albumArtist.text.trim(),
      composer: _composer.text.trim(),
      coverShape: _coverShape,
      tagsEdited: true,
    );
    try {
      final library = contextLibrary(context, listen: false);
      final player = contextPlayer(context, listen: false);
      if (_coverChanged && _cover != null) {
        await ArtworkStore.instance.put(widget.track.path, _cover!);
      }
      await library.replaceTrack(updated);
      player.replaceQueuedTrack(updated);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.s.saveTagsFailed('$error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    const fieldStyle = InputDecoration(
      isDense: true,
      border: UnderlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(vertical: 8),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: maxHeight - keyboard.clamp(0, maxHeight * 0.45),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(s.displaySettings, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  Center(
                    child: SizedBox(
                      width: 112,
                      height: 112,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: () => _setCoverShape(
                                  _coverShape == CoverShape.circle ? CoverShape.square : CoverShape.circle,
                                ),
                                customBorder: _coverShape == CoverShape.circle
                                    ? const CircleBorder()
                                    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                child: _coverPreview(),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Material(
                              color: const Color(0xFF1C3A48),
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                onTap: _picking ? null : _pickCover,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: _picking
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.edit, size: 18, color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(s.coverShape, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _shapeChoice(
                        shape: CoverShape.square,
                        icon: Icons.crop_square_rounded,
                        label: s.shapeSquare,
                      ),
                      const SizedBox(width: 8),
                      _shapeChoice(
                        shape: CoverShape.circle,
                        icon: Icons.circle_outlined,
                        label: s.shapeCircle,
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.beatHalo, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(s.beatHaloHint, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    value: context.watch<SettingsController>().beatHalo,
                    onChanged: (value) => context.read<SettingsController>().setBeatHalo(value),
                  ),
                  if (context.watch<SettingsController>().beatHalo) ...[
                    Text(
                      s.beatHaloModeHint,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _haloModeChoice(
                          mode: BeatHaloMode.simple,
                          icon: Icons.waves_outlined,
                          label: s.simpleWaves,
                        ),
                        const SizedBox(width: 8),
                        _haloModeChoice(
                          mode: BeatHaloMode.advanced,
                          icon: Icons.graphic_eq_rounded,
                          label: s.advancedWaves,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _picking ? null : _pickCover,
                          icon: const Icon(Icons.gif_box_outlined, size: 18),
                          label: Text('${s.changeCover} · ${s.changeCoverHint}'),
                        ),
                        TextButton.icon(
                          onPressed: _picking ? null : _autoCover,
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(s.autoStyle),
                        ),
                        if (_cover != null && !isAnimatedCover(_cover!))
                          TextButton.icon(
                            onPressed: _picking ? null : _cropCurrentCover,
                            icon: const Icon(Icons.crop_rounded, size: 18),
                            label: Text(s.cropCover),
                          ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13)),
                    ),
                  TextField(
                    controller: _title,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    decoration: fieldStyle.copyWith(labelText: s.fieldTitle, labelStyle: const TextStyle(color: Colors.white70)),
                  ),
                  TextField(
                    controller: _album,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    decoration: fieldStyle.copyWith(labelText: s.fieldAlbum, labelStyle: const TextStyle(color: Colors.white70)),
                  ),
                  TextField(
                    controller: _artist,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    decoration: fieldStyle.copyWith(labelText: s.fieldArtist, labelStyle: const TextStyle(color: Colors.white70)),
                  ),
                  TextField(
                    controller: _albumArtist,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    decoration: fieldStyle.copyWith(labelText: s.fieldAlbumArtist, labelStyle: const TextStyle(color: Colors.white70)),
                  ),
                  TextField(
                    controller: _composer,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_saving) _save();
                    },
                    decoration: fieldStyle.copyWith(labelText: s.fieldComposer, labelStyle: const TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
            Material(
              color: const Color(0xFF0B1E28),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text(s.cancel, style: const TextStyle(color: Colors.white70)),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4D8FA8),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(128, 48),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(s.save),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPreview() {
    final art = _cover == null
        ? const ColoredBox(
            color: Color(0xFF3A4A56),
            child: Icon(Icons.music_note, color: Colors.white54, size: 56),
          )
        : CoverBytesView(
            bytes: _cover!,
            fit: BoxFit.cover,
            animate: true,
            playing: true,
            cacheWidth: 480,
            artworkPath: _coverChanged ? null : widget.track.path,
          );
    if (_coverShape == CoverShape.circle) {
      return ClipOval(child: art);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: art,
    );
  }

  Widget _shapeChoice({
    required CoverShape shape,
    required IconData icon,
    required String label,
  }) {
    final selected = _coverShape == shape;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF1C3A48) : const Color(0xFF0B1E28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? const Color(0xFF4D8FA8) : const Color(0xFF1C3A48)),
        ),
        child: InkWell(
          onTap: () => _setCoverShape(shape),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, size: 22, color: selected ? Colors.white : Colors.white54),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _haloModeChoice({
    required BeatHaloMode mode,
    required IconData icon,
    required String label,
  }) {
    final selected = context.watch<SettingsController>().beatHaloMode == mode;
    return Expanded(
      child: Material(
        color: selected ? const Color(0xFF1C3A48) : const Color(0xFF0B1E28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? const Color(0xFF4D8FA8) : const Color(0xFF1C3A48)),
        ),
        child: InkWell(
          onTap: () => context.read<SettingsController>().setBeatHaloMode(mode),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, size: 22, color: selected ? Colors.white : Colors.white54),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
