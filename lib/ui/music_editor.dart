import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/audio_edit.dart';
import '../data/scanner.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/settings.dart';
import 'clip_preview.dart';

class MusicEditorScreen extends StatefulWidget {
  const MusicEditorScreen({super.key, required this.track});

  final Track track;

  @override
  State<MusicEditorScreen> createState() => _MusicEditorScreenState();
}

class _MusicEditorScreenState extends State<MusicEditorScreen> {
  static const _minMs = 500;
  static const _nudgeMs = 500;

  List<double> _peaks = List<double>.generate(160, (i) => 0.12 + (i % 7) * 0.03);
  int _durationMs = 0;
  int _startMs = 0;
  int _endMs = 0;
  int _playheadMs = 0;
  double _zoom = 1;
  int _sampleRate = 44100;
  int _bitrateKbps = 128;
  String _format = 'MP3';
  bool _saving = false;
  String? _localCopy;
  Future<String?>? _copyFuture;
  Timer? _saveWatchdog;
  late final ClipPreviewController _preview;

  Track get track => widget.track;
  bool get _previewPlaying => _preview.playing;

  @override
  void initState() {
    super.initState();
    _durationMs = math.max(track.durationMs, 1000);
    _endMs = _durationMs;
    _preview = ClipPreviewController()
      ..setRange(_startMs, _endMs)
      ..addListener(_onPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _onPreview() {
    if (!mounted) return;
    setState(() => _playheadMs = _preview.positionMs);
  }

  Future<void> _boot() async {
    try {
      final main = context.read<PlayerController>();
      if (main.playing) await main.playPause();
    } catch (_) {}
    _copyFuture = () async {
      try {
        final path = await materializeAudioFile(track.path);
        _localCopy = path;
        return path;
      } catch (_) {
        return null;
      }
    }();
    try {
      // The original path is often unreadable directly, so decode the copy.
      final source = await _copyFuture ?? track.path;
      final wave = await loadAudioWaveform(source, durationMs: track.durationMs);
      if (!mounted) return;
      setState(() {
        _peaks = wave.peaks;
        if (wave.durationMs > 0) _durationMs = wave.durationMs;
        _sampleRate = wave.sampleRate;
        _bitrateKbps = wave.bitrateKbps == 0 ? 128 : wave.bitrateKbps;
        _format = wave.formatLabel;
        if (_endMs <= _minMs || _endMs > _durationMs) _endMs = _durationMs;
        _preview.setRange(_startMs, _endMs);
      });
      unawaited(() async {
        final ok = await _preview.setAudioFile(source);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.s.previewFailed)));
        }
      }());
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveWatchdog?.cancel();
    _preview
      ..removeListener(_onPreview)
      ..dispose();
    super.dispose();
  }

  int get _selectedMs => math.max(0, _endMs - _startMs);

  String _clock(int ms) {
    final d = Duration(milliseconds: ms.clamp(0, 24 * 60 * 60 * 1000));
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _setStart(int value) {
    final next = value.clamp(0, _endMs - _minMs);
    setState(() {
      _startMs = next;
      if (_playheadMs < _startMs) _playheadMs = _startMs;
    });
    _preview.setRange(_startMs, _endMs);
  }

  void _setEnd(int value) {
    final next = value.clamp(_startMs + _minMs, _durationMs);
    setState(() {
      _endMs = next;
      if (_playheadMs > _endMs) _playheadMs = _endMs;
    });
    _preview.setRange(_startMs, _endMs);
  }

  Future<void> _togglePlay() async {
    try {
      await context.read<PlayerController>().player.pause();
    } catch (_) {}
    await _preview.toggle();
  }

  Future<void> _seekWithin(int ms) async {
    final clamped = ms.clamp(_startMs, _endMs);
    setState(() => _playheadMs = clamped);
    await _preview.seek(clamped);
  }

  Future<void> _save() async {
    if (_saving) return;
    final s = S(context.read<SettingsController>().language);
    final library = context.read<LibraryController>();
    final settings = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final title = cutDisplayTitle(track.title);
    setState(() => _saving = true);
    unawaited(_preview.pause());
    _saveWatchdog?.cancel();
    _saveWatchdog = Timer(const Duration(seconds: 55), () {
      if (!mounted || !_saving) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(s.cutFailed)));
    });
    try {
      final source = _localCopy ??
          await _copyFuture?.timeout(const Duration(seconds: 12)) ??
          track.path;
      final path = await cutAudioFile(
        path: source,
        sourceExt: p.extension(track.path),
        startMs: _startMs,
        endMs: _endMs,
        durationMs: _durationMs,
        title: title,
        artist: track.artist,
        album: track.album,
      ).timeout(const Duration(seconds: 50));
      // Trust the saved file rather than the selection, so a cut that silently
      // kept everything cannot show up in the library with a made up length.
      var savedMs = _selectedMs;
      try {
        final probed = await probeAudioDurationMs(path);
        if (probed > 0) savedMs = probed;
      } catch (_) {}
      await settings.rememberFiles([path]);
      await library.addLocalTrack(
        trackFromPathFast(path, durationMs: savedMs).copyWith(
          title: title,
          artist: track.artist,
          album: track.album,
          tagsEdited: true,
        ),
      );
      if (!mounted) return;
      _saveWatchdog?.cancel();
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.cutSaved(title))));
    } catch (_) {
      _saveWatchdog?.cancel();
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(s.cutFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final selectedSec = _selectedMs / 1000;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.musicEditor),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: _WaveformEditor(
                peaks: _peaks,
                durationMs: _durationMs,
                startMs: _startMs,
                endMs: _endMs,
                playheadMs: _playheadMs,
                zoom: _zoom,
                color: accent,
                onStart: _setStart,
                onEnd: _setEnd,
                onSeek: _seekWithin,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _zoom <= 1 ? null : () => setState(() => _zoom = (_zoom / 1.5).clamp(1, 12)),
                  icon: const Icon(Icons.zoom_out),
                ),
                Expanded(
                  child: Text(
                    s.selectionMeta(selectedSec, _format, _sampleRate, _bitrateKbps),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                ),
                IconButton(
                  onPressed: _zoom >= 12 ? null : () => setState(() => _zoom = (_zoom * 1.5).clamp(1, 12)),
                  icon: const Icon(Icons.zoom_in),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Column(
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  s.displayArtist(track.artist),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(
              children: [
                _NudgeColumn(
                  label: _clock(_startMs),
                  onMinus: () => _setStart(_startMs - _nudgeMs),
                  onPlus: () => _setStart(_startMs + _nudgeMs),
                ),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: math.max(1, _selectedMs).toDouble(),
                    value: (_playheadMs - _startMs).clamp(0, _selectedMs).toDouble(),
                    onChanged: (value) => _seekWithin(_startMs + value.round()),
                  ),
                ),
                _NudgeColumn(
                  label: _clock(_endMs),
                  onMinus: () => _setEnd(_endMs - _nudgeMs),
                  onPlus: () => _setEnd(_endMs + _nudgeMs),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  ClipPreviewButton(
                    playing: _previewPlaying,
                    enabled: _preview.ready && !_saving,
                    onToggle: _togglePlay,
                    onBack: () => _seekWithin(_playheadMs - 5000),
                    onForward: () => _seekWithin(_playheadMs + 5000),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '…' : s.save),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NudgeColumn extends StatelessWidget {
  const _NudgeColumn({
    required this.label,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(onPressed: onPlus, icon: const Icon(Icons.add), visualDensity: VisualDensity.compact),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        IconButton(onPressed: onMinus, icon: const Icon(Icons.remove), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

class _WaveformEditor extends StatefulWidget {
  const _WaveformEditor({
    required this.peaks,
    required this.durationMs,
    required this.startMs,
    required this.endMs,
    required this.playheadMs,
    required this.zoom,
    required this.color,
    required this.onStart,
    required this.onEnd,
    required this.onSeek,
  });

  final List<double> peaks;
  final int durationMs;
  final int startMs;
  final int endMs;
  final int playheadMs;
  final double zoom;
  final Color color;
  final ValueChanged<int> onStart;
  final ValueChanged<int> onEnd;
  final ValueChanged<int> onSeek;

  @override
  State<_WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<_WaveformEditor> {
  static const _handleW = 28.0;
  _DragKind? _drag;

  int get _visibleMs {
    final duration = math.max(widget.durationMs, 1);
    return math.max(1000, (duration / widget.zoom).round());
  }

  int get _viewStart {
    final duration = math.max(widget.durationMs, 1);
    final visible = _visibleMs;
    final center = ((widget.startMs + widget.endMs) / 2).round();
    return (center - visible ~/ 2).clamp(0, math.max(0, duration - visible));
  }

  double _xFor(int ms, double width) {
    final visible = _visibleMs;
    return (ms - _viewStart) / visible * width;
  }

  int _msFor(double x, double width) {
    final visible = _visibleMs;
    return (_viewStart + (x / width) * visible).round().clamp(0, widget.durationMs);
  }

  void _onDown(Offset local, double width) {
    final startX = _xFor(widget.startMs, width);
    final endX = _xFor(widget.endMs, width);
    if ((local.dx - startX).abs() <= _handleW) {
      _drag = _DragKind.start;
    } else if ((local.dx - endX).abs() <= _handleW) {
      _drag = _DragKind.end;
    } else {
      _drag = _DragKind.seek;
      widget.onSeek(_msFor(local.dx, width));
    }
  }

  void _onUpdate(Offset local, double width) {
    final ms = _msFor(local.dx, width);
    switch (_drag) {
      case _DragKind.start:
        widget.onStart(ms);
      case _DragKind.end:
        widget.onEnd(ms);
      case _DragKind.seek:
        widget.onSeek(ms.clamp(widget.startMs, widget.endMs));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final startX = _xFor(widget.startMs, width);
        final endX = _xFor(widget.endMs, width);
        return GestureDetector(
          onPanStart: (d) => _onDown(d.localPosition, width),
          onPanUpdate: (d) => _onUpdate(d.localPosition, width),
          onPanEnd: (_) => _drag = null,
          onTapDown: (d) => widget.onSeek(_msFor(d.localPosition.dx, width).clamp(widget.startMs, widget.endMs)),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WaveformPainter(
                    peaks: widget.peaks,
                    durationMs: widget.durationMs,
                    viewStartMs: _viewStart,
                    visibleMs: _visibleMs,
                    startMs: widget.startMs,
                    endMs: widget.endMs,
                    playheadMs: widget.playheadMs,
                    color: widget.color,
                    onSurface: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              _Handle(left: startX - _handleW / 2, top: 18, color: widget.color),
              _Handle(left: endX - _handleW / 2, top: constraints.maxHeight / 2 - 16, color: widget.color),
            ],
          ),
        );
      },
    );
  }
}

enum _DragKind { start, end, seek }

class _Handle extends StatelessWidget {
  const _Handle({required this.left, required this.top, required this.color});

  final double left;
  final double top;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left.clamp(-4, MediaQuery.sizeOf(context).width),
      top: top,
      child: IgnorePointer(
        child: Container(
          width: 28,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFF9AA7B2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(Icons.code, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.peaks,
    required this.durationMs,
    required this.viewStartMs,
    required this.visibleMs,
    required this.startMs,
    required this.endMs,
    required this.playheadMs,
    required this.color,
    required this.onSurface,
  });

  final List<double> peaks;
  final int durationMs;
  final int viewStartMs;
  final int visibleMs;
  final int startMs;
  final int endMs;
  final int playheadMs;
  final Color color;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    final duration = math.max(durationMs, 1);
    final visible = math.max(visibleMs, 1);
    final mid = size.height / 2;
    final wave = Paint()
      ..color = color.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.38);
    if (peaks.isEmpty) {
      canvas.drawRect(Offset.zero & size, Paint()..color = onSurface.withValues(alpha: 0.06));
    } else {
      final barW = size.width / math.max(peaks.length * visible / duration, 1);
      final startBar = ((viewStartMs / duration) * peaks.length).floor().clamp(0, math.max(0, peaks.length - 1)).toInt();
      final endBar = (((viewStartMs + visible) / duration) * peaks.length).ceil().clamp(0, peaks.length).toInt();
      for (var i = startBar; i < endBar; i++) {
        final t = i / peaks.length * duration;
        final x = (t - viewStartMs) / visible * size.width;
        final h = (peaks[i].clamp(0.04, 1.0) * (size.height * 0.9)).clamp(2.0, size.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, mid), width: math.max(1.1, barW * 0.62), height: h),
            const Radius.circular(0.8),
          ),
          wave,
        );
      }
    }

    final startX = (startMs - viewStartMs) / visible * size.width;
    final endX = (endMs - viewStartMs) / visible * size.width;
    if (startX > 0) canvas.drawRect(Rect.fromLTRB(0, 0, startX, size.height), dim);
    if (endX < size.width) canvas.drawRect(Rect.fromLTRB(endX, 0, size.width, size.height), dim);

    final tickPaint = Paint()
      ..color = onSurface.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: onSurface.withValues(alpha: 0.55), fontSize: 11);
    final step = _tickStep(visible);
    final first = (viewStartMs / step).ceil() * step;
    for (var t = first; t <= viewStartMs + visible; t += step) {
      final x = (t - viewStartMs) / visible * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, 10), tickPaint);
      final tp = TextPainter(
        text: TextSpan(text: _label(t), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 2, 2));
    }

    final playX = (playheadMs - viewStartMs) / visible * size.width;
    final playPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(playX, 0), Offset(playX, size.height), playPaint);

    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), edge);
    canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), edge);
  }

  int _tickStep(int visible) {
    if (visible <= 8000) return 1000;
    if (visible <= 20000) return 2000;
    if (visible <= 60000) return 5000;
    if (visible <= 180000) return 15000;
    return 30000;
  }

  String _label(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '${d.inMinutes}:$s';
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) {
    return old.peaks != peaks ||
        old.startMs != startMs ||
        old.endMs != endMs ||
        old.playheadMs != playheadMs ||
        old.viewStartMs != viewStartMs ||
        old.visibleMs != visibleMs ||
        old.color != color;
  }
}
