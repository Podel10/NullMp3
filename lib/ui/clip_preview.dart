import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

/// Plays only the selected range of an audio file or video clip.
class ClipPreviewController extends ChangeNotifier {
  ClipPreviewController();

  final AudioPlayer _audio = AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  VideoPlayerController? _video;
  StreamSubscription<Duration>? _audioPos;
  Timer? _tick;
  String? _audioPath;
  String? _videoPath;
  bool _ready = false;
  bool _alive = true;
  bool _stopping = false;
  Size? _lastVideoSize;
  bool playing = false;
  int positionMs = 0;
  int startMs = 0;
  int endMs = 1000;

  VideoPlayerController? get video => _video;
  bool get hasVideo => _video?.value.isInitialized == true;
  bool get ready => _ready;

  Future<bool> setAudioFile(String path) async {
    await _clearVideo();
    if (_audioPath == path && _ready) return true;
    _audioPath = path;
    _ready = false;
    try {
      if (path.startsWith('content:')) {
        await _audio.setAudioSource(AudioSource.uri(Uri.parse(path)));
      } else {
        await _audio.setFilePath(path);
      }
      _ready = true;
      await _audioPos?.cancel();
      _audioPos = _audio.positionStream.listen((pos) {
        if (!playing) return;
        _onPos(pos.inMilliseconds);
      });
    } catch (_) {
      _ready = false;
    }
    _emit();
    return _ready;
  }

  Future<void> setVideoFile(String path) async {
    if (_videoPath == path && hasVideo) return;
    await _audio.pause();
    await _clearVideo();
    _videoPath = path;
    _ready = false;
    playing = false;
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = path.startsWith('content:')
        ? VideoPlayerController.contentUri(Uri.parse(path), videoPlayerOptions: options)
        : VideoPlayerController.file(File(path), videoPlayerOptions: options);
    try {
      await controller.initialize();
      await controller.setLooping(false);
      controller.addListener(_onVideoTick);
      _video = controller;
      _ready = true;
      _emit();
      // Many Android surfaces stay black until the decoder actually runs.
      try {
        await controller.play();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await controller.pause();
      } catch (_) {}
      await controller.seekTo(Duration(milliseconds: startMs));
    } catch (_) {
      controller.removeListener(_onVideoTick);
      await controller.dispose();
      _ready = false;
    }
    _emit();
  }

  void setRange(int start, int end) {
    startMs = math.max(0, start);
    endMs = math.max(startMs + 200, end);
    if (positionMs < startMs || positionMs > endMs) {
      positionMs = startMs;
      if (!playing) unawaited(_seekEngine(startMs));
    }
    if (playing && positionMs >= endMs) unawaited(pause());
    _emit();
  }

  Future<void> seek(int ms) async {
    positionMs = ms.clamp(startMs, endMs);
    await _seekEngine(positionMs);
    _emit();
  }

  Future<void> skip(int deltaMs) => seek(positionMs + deltaMs);

  Future<void> toggle() async {
    if (playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (!_ready) return;
    if (positionMs < startMs || positionMs >= endMs - 80) {
      positionMs = startMs;
      await _seekEngine(startMs);
    }
    playing = true;
    _stopping = false;
    _emit();
    _startTick();
    if (_video != null) {
      try {
        await _video!.play();
      } catch (_) {
        playing = false;
        _tick?.cancel();
        _emit();
      }
      return;
    }
    unawaited(
      _audio.play().then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (!_alive || !playing) return;
          playing = false;
          _tick?.cancel();
          _emit();
        },
      ),
    );
  }

  Future<void> pause() async {
    _tick?.cancel();
    playing = false;
    _stopping = false;
    try {
      if (_video != null) {
        await _video!.pause();
      } else {
        await _audio.pause();
      }
    } catch (_) {}
    _emit();
  }

  Future<void> _seekEngine(int ms) async {
    final at = Duration(milliseconds: ms);
    try {
      if (_video != null) {
        await _video!.seekTo(at);
      } else if (_ready) {
        await _audio.seek(at);
      }
    } catch (_) {}
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!playing) return;
      if (_video != null) {
        _onPos(_video!.value.position.inMilliseconds);
      } else {
        _onPos(_audio.position.inMilliseconds);
      }
    });
  }

  void _onVideoTick() {
    if (!_alive || _video == null) return;
    final value = _video!.value;
    if (!playing) {
      if (value.size != _lastVideoSize) {
        _lastVideoSize = value.size;
        _emit();
      }
      return;
    }
    _onPos(value.position.inMilliseconds);
  }

  void _onPos(int ms) {
    if (!_alive || _stopping || !playing) return;
    if (ms >= endMs) {
      _stopping = true;
      unawaited(() async {
        await pause();
        if (!_alive) return;
        positionMs = startMs;
        await _seekEngine(startMs);
        _emit();
      }());
      return;
    }
    final next = ms.clamp(startMs, endMs);
    if (next == positionMs) return;
    positionMs = next;
    _emit();
  }

  Future<void> _clearVideo() async {
    _tick?.cancel();
    final old = _video;
    _video = null;
    _videoPath = null;
    _lastVideoSize = null;
    if (old == null) return;
    old.removeListener(_onVideoTick);
    try {
      await old.pause();
    } catch (_) {}
    await old.dispose();
  }

  void _emit() {
    if (_alive) notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    _tick?.cancel();
    _audioPos?.cancel();
    unawaited(_clearVideo());
    unawaited(_audio.dispose());
    super.dispose();
  }
}

class ClipPreviewButton extends StatelessWidget {
  const ClipPreviewButton({
    super.key,
    required this.playing,
    required this.onToggle,
    this.onBack,
    this.onForward,
    this.enabled = true,
  });

  final bool playing;
  final VoidCallback onToggle;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 32,
          onPressed: enabled ? onBack : null,
          icon: const Icon(Icons.replay_5_outlined),
        ),
        IconButton(
          iconSize: 64,
          color: accent,
          onPressed: enabled ? onToggle : null,
          icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded),
        ),
        IconButton(
          iconSize: 32,
          onPressed: enabled ? onForward : null,
          icon: const Icon(Icons.forward_5_outlined),
        ),
      ],
    );
  }
}

class ClipVideoView extends StatelessWidget {
  const ClipVideoView({super.key, required this.controller, this.aspectRatio, this.maxHeight = 280});

  final ClipPreviewController controller;
  final double? aspectRatio;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final player = controller.video;
    final raw = player?.value.size;
    final hasSize = raw != null && raw.width > 2 && raw.height > 2;
    final ratio = hasSize
        ? raw.width / raw.height
        : (aspectRatio != null && aspectRatio! > 0 ? aspectRatio! : 1.0);
    final ready = player != null && player.value.isInitialized && hasSize;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: AspectRatio(
            aspectRatio: ratio,
            child: ready
                ? FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: raw.width,
                      height: raw.height,
                      child: VideoPlayer(player),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }
}
