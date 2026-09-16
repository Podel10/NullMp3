import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/video_gif.dart';
import '../l10n/strings.dart';
import '../state/player.dart';
import 'clip_preview.dart';

class VideoToGifScreen extends StatefulWidget {
  const VideoToGifScreen({super.key});

  @override
  State<VideoToGifScreen> createState() => _VideoToGifScreenState();
}

class _VideoToGifScreenState extends State<VideoToGifScreen> {
  static const _fpsChoices = [8, 12, 15];
  static const _widthChoices = [240, 320, 480, 576, 720];
  static const _maxSpanMs = 15000;

  String? _sourcePath;
  VideoClipInfo? _info;
  int _startMs = 0;
  int _spanMs = 3000;
  int _fps = 12;
  int? _width;
  bool _busy = false;
  GifResult? _result;
  GifStep? _step;
  StreamSubscription<GifStep>? _progress;
  late final ClipPreviewController _preview;

  @override
  void initState() {
    super.initState();
    _preview = ClipPreviewController()..addListener(_onPreview);
  }

  void _onPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _progress?.cancel();
    _preview
      ..removeListener(_onPreview)
      ..dispose();
    super.dispose();
  }

  int get _durationMs => _info?.durationMs ?? 0;

  int get _maxStart => (_durationMs - 500).clamp(0, _durationMs);

  int get _maxSpan {
    final left = _durationMs - _startMs;
    if (left <= 0) return 1000;
    return left.clamp(500, _maxSpanMs);
  }

  int get _sourceWidth => _info?.width ?? 0;

  List<int> get _widths {
    final src = _sourceWidth;
    final extra = src >= 80 && !_widthChoices.contains(src) ? [src] : const <int>[];
    return [..._widthChoices, ...extra]..sort();
  }

  int get _outputWidth {
    final src = _sourceWidth;
    if (_width == null) return src > 0 ? src.clamp(80, 1080) : 480;
    return _width!;
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.video);
    String? path;
    for (final file in picked) {
      path = file.path ?? file.uri.toString();
      if (path.isNotEmpty) break;
    }
    if (path == null || !mounted) return;
    setState(() {
      _sourcePath = path;
      _info = null;
      _result = null;
      _startMs = 0;
      _spanMs = 3000;
      _busy = true;
    });
    unawaited(_preview.pause());
    final loading = _preview.setVideoFile(path);
    try {
      final info = await readVideoInfo(path);
      if (!mounted) return;
      setState(() {
        _info = info;
        _spanMs = info.durationMs <= 0 ? 3000 : _spanMs.clamp(500, _maxSpan);
        _width = null;
        _busy = false;
      });
      _preview.setRange(_startMs, _startMs + _spanMs);
      await loading;
      if (!mounted) return;
      await _preview.seek(_startMs);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context.s.videoUnreadable);
    }
  }

  Future<void> _convert() async {
    final path = _sourcePath;
    if (path == null || _busy) return;
    unawaited(_preview.pause());
    setState(() {
      _busy = true;
      _result = null;
      _step = null;
    });
    _progress?.cancel();
    _progress = watchGifProgress().listen((step) {
      if (mounted && _busy) setState(() => _step = step);
    });
    try {
      final result = await convertVideoToGif(
        path: path,
        startMs: _startMs,
        endMs: _startMs + _spanMs,
        fps: _fps,
        width: _outputWidth,
        name: '${p.basenameWithoutExtension(path)}-gif',
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
        _step = null;
      });
      _toast(context.s.gifSaved(_sizeLabel(result.sizeBytes)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = null;
      });
      _toast(context.s.gifFailed);
    } finally {
      _progress?.cancel();
      _progress = null;
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _sizeLabel(int bytes) {
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  String _stageLabel(S s) {
    final step = _step;
    if (step == null) return s.converting;
    final label = step.stage == 'encode' ? s.gifBuilding : s.gifReading;
    final value = step.value;
    if (value == null || step.total < 2) return label;
    return '$label ${(value * 100).round()}%';
  }

  void _setStart(double value) {
    setState(() {
      _startMs = value.round();
      _spanMs = _spanMs.clamp(500, _maxSpan);
    });
    _preview.setRange(_startMs, _startMs + _spanMs);
    if (!_preview.playing) unawaited(_preview.seek(_startMs));
  }

  void _setSpan(double value) {
    setState(() => _spanMs = value.round());
    _preview.setRange(_startMs, _startMs + _spanMs);
  }

  Future<void> _togglePreview() async {
    try {
      await context.read<PlayerController>().player.pause();
    } catch (_) {}
    await _preview.toggle();
  }

  String _clock(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final info = _info;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(s.videoToGif)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(s.videoToGifHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(s.chooseVideo),
          ),
          const SizedBox(height: 8),
          Text(
            _sourcePath == null ? s.noVideoChosen : p.basename(_sourcePath!),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (info != null && info.hasSize)
            Text(
              '${info.width}×${info.height} · ${_clock(info.durationMs)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          if (info != null) ...[
            const SizedBox(height: 16),
            ClipVideoView(
              controller: _preview,
              aspectRatio: info.hasSize ? info.width / info.height : null,
            ),
            const SizedBox(height: 8),
            ClipPreviewButton(
              playing: _preview.playing,
              enabled: _preview.ready && !_busy,
              onToggle: _togglePreview,
              onBack: () => _preview.skip(-5000),
              onForward: () => _preview.skip(5000),
            ),
            Text(
              '${s.preview}  ${_clock(_preview.positionMs.clamp(_startMs, _startMs + _spanMs) - _startMs)} / ${_clock(_spanMs)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.gifStart),
              trailing: Text(_clock(_startMs), style: theme.textTheme.labelLarge),
            ),
            Slider(
              min: 0,
              max: _maxStart.toDouble().clamp(1, double.infinity),
              value: _startMs.toDouble().clamp(0, _maxStart.toDouble()),
              onChanged: _busy ? null : _setStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.gifLength),
              trailing: Text('${(_spanMs / 1000).toStringAsFixed(1)} s', style: theme.textTheme.labelLarge),
            ),
            Slider(
              min: 500,
              max: _maxSpan.toDouble().clamp(1000, _maxSpanMs.toDouble()),
              value: _spanMs.toDouble().clamp(500, _maxSpan.toDouble()),
              onChanged: _busy ? null : _setSpan,
            ),
            const SizedBox(height: 8),
            Text(s.gifFps, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final fps in _fpsChoices)
                  ChoiceChip(
                    label: Text('$fps'),
                    selected: _fps == fps,
                    onSelected: _busy ? null : (_) => setState(() => _fps = fps),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(s.gifWidth, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(info.hasSize ? '${s.gifAuto} (${info.width} px)' : s.gifAuto),
                  selected: _width == null,
                  onSelected: _busy ? null : (_) => setState(() => _width = null),
                ),
                for (final width in _widths)
                  ChoiceChip(
                    label: Text('$width px'),
                    selected: _width == width,
                    onSelected: _busy ? null : (_) => setState(() => _width = width),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _convert,
              child: Text(_busy ? s.converting : s.convert),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            Center(child: CircularProgressIndicator(value: _step?.value)),
            const SizedBox(height: 8),
            Center(child: Text(_stageLabel(s), style: theme.textTheme.bodySmall)),
          ],
          if (result != null) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(result.file), fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            Text(
              '${s.gifFrames(result.frames)} · ${_sizeLabel(result.sizeBytes)}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              result.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(result.file, mimeType: 'image/gif')]),
              ),
              icon: const Icon(Icons.share_outlined),
              label: Text(s.share),
            ),
          ],
        ],
      ),
    );
  }
}
