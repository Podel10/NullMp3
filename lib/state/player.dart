import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/artwork.dart';
import '../data/cover_image.dart';
import '../data/playback_file.dart';
import '../models/models.dart';
import 'library.dart';
import 'settings.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({required this.library, required this.settings}) {
    player.playingStream.listen((value) {
      playing = value;
      notifyListeners();
      _pushSession();
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed &&
          !_loading &&
          _fileEdit == null &&
          !_handlingComplete &&
          _isNearEnd()) {
        unawaited(_onCompleted());
      }
    });

    player.errorStream.listen((_) {
      if (_loading || _fileEdit != null || _errorSkips >= 8) return;
      _errorSkips++;
      unawaited(next());
    });
  }

  final LibraryController library;
  final SettingsController settings;

  // Created synchronously so the UI can bind streams immediately.
  // Interruptions are handled below: keep playing when another app takes
  // media focus, but still pause for phone calls and unplugged headphones.
  final AudioPlayer player = AudioPlayer(
    handleInterruptions: false,
    maxSkipsOnError: 8,
    androidAudioOffloadPreferences: const AndroidAudioOffloadPreferences(
      audioOffloadMode: AndroidAudioOffloadMode.disabled,
    ),
  );
  AndroidEqualizer? _equalizer;

  List<Track> queue = [];
  int index = 0;
  bool playing = false;
  bool shuffle = false;
  RepeatKind repeat = RepeatKind.off;
  Color? artworkColor;
  SleepKind sleepKind = SleepKind.off;
  DateTime? sleepUntil;
  Timer? _sleepTimer;
  bool _stopAfterTrack = false;
  String? _lastCountedPath;
  int _fadeGen = 0;
  int _loadGen = 0;
  bool _inited = false;
  bool _loading = false;
  bool _handlingComplete = false;
  String? _loadedPath;
  _FileEditHold? _fileEdit;
  final List<int> _history = [];
  int _errorSkips = 0;
  bool _resumeAfterInterruption = false;
  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptSub;
  static const _session = MethodChannel('com.nullmp3.nullmp3/session');

  Track? get current {
    if (queue.isEmpty || index < 0 || index >= queue.length) return null;
    return queue[index];
  }

  bool get hasTrack => current != null;
  bool isFavorite(Track? track) => track != null && library.favorites.contains(track.path);

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    await player.setVolume(settings.volume);
    await player.setSpeed(settings.speed);
    try {
      await player.setPitch(settings.pitch);
    } catch (_) {}
    await _configureAudioSession();
    _session.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          if (!playing) await playPause();
        case 'pause':
          if (playing) await playPause();
        case 'next':
          await next();
        case 'previous':
          await previous();
      }
    });
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await Permission.notification.request();
      } catch (_) {}
    }
    _pushSession();
  }

  void _pushSession() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final track = current;
    if (track == null) {
      unawaited(_session.invokeMethod('clear'));
      return;
    }
    unawaited(
      _session.invokeMethod('update', {
        'playing': playing,
        'title': track.title,
        'artist': track.artist,
        'durationMs': track.durationMs,
        'positionMs': player.position.inMilliseconds,
      }),
    );
  }

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: false,
        ),
      );
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        _resumeAfterInterruption = false;
        if (playing) unawaited(player.pause());
      });
      _interruptSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          // Transient loss is a call / alarm. Permanent loss is another
          // media app — keep playing so both can overlap.
          if (event.type == AudioInterruptionType.pause && playing) {
            _resumeAfterInterruption = true;
            unawaited(player.pause());
          }
          return;
        }
        if (event.type == AudioInterruptionType.pause && _resumeAfterInterruption) {
          _resumeAfterInterruption = false;
          unawaited(player.play());
        }
      });
    } catch (_) {}
  }

  Future<void> playTracks(List<Track> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return;
    queue = List<Track>.from(tracks);
    index = start.clamp(0, queue.length - 1);
    _history.clear();
    notifyListeners();
    await _loadCurrent(play: true);
  }

  /// Keep the current song loaded, but use the library as the skip queue.
  void ensureBrowsableQueue() {
    if (queue.length > 1) return;
    final songs = library.songs;
    if (songs.length <= 1) return;
    final path = current?.path;
    final start = path == null ? 0 : songs.indexWhere((track) => track.path == path);
    queue = List<Track>.from(songs);
    index = start >= 0 ? start : 0;
    notifyListeners();
  }

  bool _isNearEnd() {
    final duration = player.duration;
    final position = player.position;
    if (duration == null || duration.inMilliseconds <= 0) {
      return position.inMilliseconds > 1500;
    }
    return position >= duration - const Duration(milliseconds: 1200);
  }

  Future<void> playPause() async {
    _resumeAfterInterruption = false;
    if (!hasTrack) return;
    final isPlaying = playing || player.playing;
    if (isPlaying) {
      if (settings.pauseFade) {
        await _fadeVolume(0, const Duration(milliseconds: 300));
        await player.pause();
        await player.setVolume(settings.volume);
      } else {
        await player.pause();
      }
      return;
    }
    if (_loadedPath != current!.path) {
      await _loadCurrent(play: true);
      return;
    }
    if (player.processingState == ProcessingState.completed) {
      if (_isNearEnd()) {
        await _loadCurrent(play: true);
      } else {
        try {
          await player.seek(player.position);
        } catch (_) {}
        await player.play();
      }
      return;
    }
    if (settings.pauseFade) {
      await player.setVolume(0);
      await player.play();
      await _fadeVolume(settings.volume, const Duration(milliseconds: 300));
      return;
    }
    await player.play();
  }

  Future<void> next() => _skipTo(_nextIndex());

  Future<void> previous() async {
    if (_history.isNotEmpty) {
      await _loadIndex(_history.removeLast(), play: playing || _loadedPath != null, recordHistory: false);
      return;
    }
    await _skipTo(_previousIndex());
  }

  Future<void> _skipTo(int? nextIndex) async {
    if (nextIndex == null) return;
    if (settings.crossfade && playing) {
      await _fadeVolume(0, const Duration(milliseconds: 400));
      await _loadIndex(nextIndex, play: true);
      await player.setVolume(0);
      await player.play();
      await _fadeVolume(settings.volume, const Duration(milliseconds: 400));
      return;
    }
    await _loadIndex(nextIndex, play: playing || _loadedPath != null);
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> playNext(Track track) async {
    if (!hasTrack) {
      await playTracks([track]);
      return;
    }
    final insertAt = index + 1;
    queue = [...queue.sublist(0, insertAt), track, ...queue.sublist(insertAt)];
    notifyListeners();
  }

  Future<void> addToQueue(Track track) async {
    if (!hasTrack) {
      await playTracks([track]);
      return;
    }
    queue = [...queue, track];
    notifyListeners();
  }

  Future<void> playAt(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    await _loadIndex(queueIndex, play: true);
  }

  Future<void> toggleShuffle() async {
    shuffle = !shuffle;
    notifyListeners();
    unawaited(_persistSession());
  }

  Future<void> cycleRepeat() async {
    repeat = repeat == RepeatKind.one ? RepeatKind.off : RepeatKind.one;
    notifyListeners();
    unawaited(_persistSession());
    if (player.processingState != ProcessingState.completed) return;
    if (repeat == RepeatKind.one) {
      await _loadCurrent(play: true);
    } else {
      await _skipTo(_nextIndex());
    }
  }

  Future<void> setVolume(double value) async {
    _fadeGen++;
    await settings.setVolume(value);
    await player.setVolume(value);
  }

  Future<void> setSpeed(double value, {bool persist = true}) async {
    await settings.setSpeed(value, persist: persist);
    await player.setSpeed(settings.speed);
  }

  Future<void> setPitch(double value, {bool persist = true}) async {
    await settings.setPitch(value, persist: persist);
    try {
      await player.setPitch(settings.pitch);
    } catch (_) {}
  }

  /// Release the file so tags can be rewritten without killing playback.
  Future<void> beginFileEdit(String path) async {
    if (_loadedPath != path && current?.path != path) return;
    _fileEdit = _FileEditHold(
      playing: playing,
      position: player.position,
      path: path,
    );
    _loading = true;
    try {
      await player.stop().timeout(const Duration(milliseconds: 400));
    } catch (_) {}
    _loadedPath = null;
  }

  Future<void> endFileEdit(Track updated, {String? fromPath}) async {
    final hold = _fileEdit;
    _fileEdit = null;
    replaceQueuedTrack(updated, fromPath: fromPath ?? hold?.path ?? updated.path);
    if (hold == null || current?.path != updated.path) {
      _loading = false;
      notifyListeners();
      return;
    }
    await _loadCurrent(play: hold.playing, position: hold.position);
  }

  Future<void> cancelFileEdit() async {
    final hold = _fileEdit;
    _fileEdit = null;
    if (hold == null) {
      _loading = false;
      return;
    }
    if (current?.path != hold.path) {
      _loading = false;
      notifyListeners();
      return;
    }
    await _loadCurrent(play: hold.playing, position: hold.position);
  }

  void replaceQueuedTrack(Track updated, {String? fromPath}) {
    final oldPath = fromPath ?? updated.path;
    queue = [
      for (final track in queue)
        if (track.path == oldPath) updated else track,
    ];
    if (_loadedPath == oldPath) _loadedPath = updated.path;
    if (_lastCountedPath == oldPath) _lastCountedPath = updated.path;
    notifyListeners();
    _pushSession();
  }

  Future<void> retargetQueuedTrack(
    String oldPath,
    Track updated, {
    required bool play,
    Duration position = Duration.zero,
  }) async {
    replaceQueuedTrack(updated, fromPath: oldPath);
    if (current?.path != updated.path) return;
    await _loadCurrent(play: play, position: position);
  }

  Future<void> removePath(String path) async {
    final at = queue.indexWhere((track) => track.path == path);
    if (at < 0) return;
    if (queue.length == 1) {
      await player.stop();
      queue = [];
      index = 0;
      _loadedPath = null;
      notifyListeners();
      return;
    }
    final wasCurrent = at == index;
    queue = [...queue]..removeAt(at);
    if (index > at) {
      index--;
    } else if (index >= queue.length) {
      index = queue.length - 1;
    }
    _history.removeWhere((item) => item == at);
    _history.replaceRange(
      0,
      _history.length,
      [
        for (final item in _history)
          if (item > at) item - 1 else item,
      ],
    );
    notifyListeners();
    if (wasCurrent) {
      await _loadCurrent(play: playing);
    }
  }

  Future<void> toggleFavorite() async {
    final track = current;
    if (track == null) return;
    await library.toggleFavorite(track.path);
    notifyListeners();
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _stopAfterTrack = false;
    sleepKind = SleepKind.timer;
    sleepUntil = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      await player.pause();
      clearSleep();
    });
    notifyListeners();
  }

  void setSleepEndOfTrack() {
    _sleepTimer?.cancel();
    sleepUntil = null;
    sleepKind = SleepKind.endOfTrack;
    _stopAfterTrack = true;
    notifyListeners();
  }

  void clearSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepUntil = null;
    sleepKind = SleepKind.off;
    _stopAfterTrack = false;
    notifyListeners();
  }

  Future<void> applyEqualizer() => _applyEqualizer();

  Future<void> restoreSession() async {
    if (hasTrack) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sessionQueue');
    if (raw == null) return;
    final paths = List<String>.from(jsonDecode(raw) as List);
    final byPath = {for (final track in library.allTracks) track.path: track};
    final restored = [for (final path in paths) if (byPath[path] != null) byPath[path]!];
    if (restored.isEmpty) return;
    queue = restored;
    index = (prefs.getInt('sessionIndex') ?? 0).clamp(0, queue.length - 1);
    shuffle = prefs.getBool('sessionShuffle') ?? false;
    final storedRepeat = prefs.getInt('sessionRepeat') ?? 0;
    repeat = storedRepeat == 2 || storedRepeat == RepeatKind.one.index ? RepeatKind.one : RepeatKind.off;
    notifyListeners();
    unawaited(_extractColor());
  }

  Future<void> _loadIndex(int nextIndex, {required bool play, bool recordHistory = true}) async {
    if (nextIndex < 0 || nextIndex >= queue.length) return;
    if (recordHistory && nextIndex != index) {
      _history.add(index);
      if (_history.length > 80) _history.removeAt(0);
    }
    index = nextIndex;
    notifyListeners();
    await _loadCurrent(play: play);
  }

  Future<void> _loadCurrent({required bool play, Duration position = Duration.zero}) async {
    final track = current;
    if (track == null) return;
    final gen = ++_loadGen;
    _loading = true;
    try {
      String playPath = track.path;
      try {
        repairDamagedAudioFile(track.path);
      } catch (_) {}
      var cache = PlaybackCache.dir;
      if (cache == null) {
        await PlaybackCache.init();
        cache = PlaybackCache.dir;
      }
      if (cache != null) {
        final args = {'path': track.path, 'cache': cache};
        try {
          playPath = await compute(preparePlaybackPath, args).timeout(const Duration(seconds: 20));
        } catch (_) {
          try {
            playPath = preparePlaybackPath(args);
          } catch (_) {
            playPath = track.path;
          }
        }
      }
      Future<Duration?> setSource(String path) {
        return player.setAudioSource(
          path.startsWith('content:')
              ? AudioSource.uri(Uri.parse(path), tag: track)
              : AudioSource.file(path, tag: track),
          preload: true,
        );
      }

      try {
        await setSource(playPath).timeout(const Duration(seconds: 8));
      } catch (error) {
        debugPrint('setAudioSource failed for $playPath: $error');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (gen != _loadGen) return;
        await setSource(playPath).timeout(const Duration(seconds: 8));
      }
      if (gen != _loadGen) return;
      _loadedPath = track.path;
      _errorSkips = 0;
      try {
        await player.setLoopMode(LoopMode.off).timeout(const Duration(milliseconds: 250));
      } catch (_) {}
      await player.setSpeed(settings.speed);
      try {
        await player.setPitch(settings.pitch);
      } catch (_) {}
      await player.setVolume(settings.volume);
      if (position > const Duration(milliseconds: 400)) {
        try {
          if (player.processingState != ProcessingState.ready) {
            await player.processingStateStream
                .firstWhere((state) => state == ProcessingState.ready)
                .timeout(const Duration(seconds: 2));
          }
        } catch (_) {}
        if (gen != _loadGen) return;
        try {
          await player.seek(position).timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      if (play) await player.play().timeout(const Duration(seconds: 3));
    } catch (_) {
      if (gen != _loadGen) return;
      _loadedPath = null;
    } finally {
      if (gen == _loadGen) _loading = false;
    }
    if (gen != _loadGen) return;
    if (track.path != _lastCountedPath) {
      _lastCountedPath = track.path;
      unawaited(library.markPlayed(track.path));
    }
    unawaited(_extractColor());
    unawaited(_persistSession());
    _pushSession();
    notifyListeners();
  }

  int? _nextIndex() {
    if (queue.isEmpty) return null;
    if (shuffle && queue.length > 1) {
      var next = math.Random().nextInt(queue.length);
      if (next == index) next = (next + 1) % queue.length;
      return next;
    }
    final next = index + 1;
    if (next < queue.length) return next;
    return 0;
  }

  int? _previousIndex() {
    if (queue.length <= 1) return null;
    if (shuffle) {
      var prev = math.Random().nextInt(queue.length);
      if (prev == index) prev = (prev + queue.length - 1) % queue.length;
      return prev;
    }
    if (index > 0) return index - 1;
    return queue.length - 1;
  }

  Future<void> _onCompleted() async {
    if (_handlingComplete || _loading || _fileEdit != null) return;
    _handlingComplete = true;
    try {
      if (_stopAfterTrack) {
        _stopAfterTrack = false;
        sleepKind = SleepKind.off;
        await player.pause();
        notifyListeners();
        return;
      }
      if (repeat == RepeatKind.one) {
        try {
          await player.seek(Duration.zero).timeout(const Duration(milliseconds: 400));
          await player.play().timeout(const Duration(milliseconds: 400));
          if (player.processingState != ProcessingState.completed) return;
        } catch (_) {}
        try {
          await player.stop().timeout(const Duration(milliseconds: 300));
        } catch (_) {}
        await _loadCurrent(play: true);
        return;
      }
      final nextIndex = _nextIndex();
      if (nextIndex == null) {
        await player.pause();
        notifyListeners();
        return;
      }
      await _loadIndex(nextIndex, play: true);
    } finally {
      _handlingComplete = false;
    }
  }

  Future<void> _persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sessionQueue', jsonEncode([for (final t in queue) t.path]));
    await prefs.setInt('sessionIndex', index);
    await prefs.setInt('sessionPosition', player.position.inMilliseconds);
    await prefs.setBool('sessionShuffle', shuffle);
    await prefs.setInt('sessionRepeat', repeat.index);
  }

  Future<void> _extractColor() async {
    final track = current;
    final gen = _loadGen;
    if (track == null) {
      artworkColor = null;
      notifyListeners();
      return;
    }
    final bytes = await ArtworkStore.instance.get(track.path);
    if (gen != _loadGen) return;
    if (bytes == null || bytes.isEmpty) {
      artworkColor = null;
      notifyListeners();
      return;
    }
    // GIF and WebP decode to their first frame, so only video has no colour.
    if (isVideoBytes(bytes)) {
      artworkColor = const Color(0xFF5E656C);
      notifyListeners();
      return;
    }
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 8,
        size: const Size(72, 72),
      );
      if (gen != _loadGen) return;
      artworkColor = _pickArtworkColor(palette);
      notifyListeners();
    } catch (_) {}
  }

  Color? _pickArtworkColor(PaletteGenerator palette) {
    bool usable(Color color) {
      final luminance = color.computeLuminance();
      if (luminance <= 0.045 || luminance >= 0.92) return false;
      final maxC = math.max(color.r, math.max(color.g, color.b));
      final minC = math.min(color.r, math.min(color.g, color.b));
      return maxC - minC > 0.08;
    }

    for (final color in [
      palette.dominantColor?.color,
      palette.vibrantColor?.color,
      palette.mutedColor?.color,
      palette.darkMutedColor?.color,
      palette.lightVibrantColor?.color,
      palette.lightMutedColor?.color,
    ]) {
      if (color != null && usable(color)) return color;
    }
    return palette.dominantColor?.color;
  }

  Future<void> refreshArtwork() => _extractColor();

  Future<void> _applyEqualizer() async {
    final eq = _equalizer;
    if (eq == null) return;
    try {
      await eq.setEnabled(settings.eqEnabled);
      final params = await eq.parameters.timeout(const Duration(milliseconds: 1500));
      for (var i = 0; i < params.bands.length; i++) {
        final band = params.bands[i];
        final value = settings.eqBands[i.clamp(0, settings.eqBands.length - 1)];
        final min = params.minDecibels;
        final max = params.maxDecibels;
        final gain = value.clamp(min, max);
        await band.setGain(gain);
      }
    } catch (_) {}
  }

  Future<void> _fadeVolume(double target, Duration duration) async {
    final gen = ++_fadeGen;
    final start = player.volume;
    if (duration.inMilliseconds <= 0 || (start - target).abs() < 0.02) {
      await player.setVolume(target);
      return;
    }
    const steps = 8;
    final step = Duration(milliseconds: (duration.inMilliseconds / steps).round().clamp(16, 80));
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(step);
      if (gen != _fadeGen) return;
      await player.setVolume(start + (target - start) * (i / steps));
    }
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    unawaited(_noisySub?.cancel());
    unawaited(_interruptSub?.cancel());
    player.dispose();
    super.dispose();
  }
}

class _FileEditHold {
  const _FileEditHold({
    required this.playing,
    required this.position,
    required this.path,
  });

  final bool playing;
  final Duration position;
  final String path;
}
