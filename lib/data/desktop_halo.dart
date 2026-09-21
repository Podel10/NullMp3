import 'dart:math' as math;

/// Builds reactive halo bands from a coarse file envelope (Windows / desktop).
/// Android still uses the system Visualizer; this is the PC fallback.
class DesktopHaloFrame {
  const DesktopHaloFrame({
    required this.peaks,
    required this.energy,
    required this.bass,
    required this.beat,
    required this.strength,
  });

  final List<double> peaks;
  final double energy;
  final double bass;
  final bool beat;
  final double strength;
}

class DesktopHalo {
  DesktopHalo._();

  static const bands = 32;

  /// Sample [envelope] (0..1 peaks along the track) at progress [t] in 0..1.
  static DesktopHaloFrame sample(List<double> envelope, double t, {double prevEnergy = 0}) {
    if (envelope.isEmpty) {
      return DesktopHaloFrame(
        peaks: List<double>.filled(bands, 0.08),
        energy: 0.08,
        bass: 0.06,
        beat: false,
        strength: 0,
      );
    }
    final n = envelope.length;
    final clamped = t.clamp(0.0, 1.0);
    final center = _at(envelope, clamped);
    final ahead = _at(envelope, (clamped + 0.012).clamp(0.0, 1.0));
    final behind = _at(envelope, (clamped - 0.012).clamp(0.0, 1.0));
    final rise = (center - behind).clamp(0.0, 1.0);
    final drop = (ahead - center);

    // Spread nearby envelope into 32 bands with a bass-heavy shape.
    final peaks = List<double>.filled(bands, 0);
    for (var i = 0; i < bands; i++) {
      final wobble = ((i / (bands - 1)) - 0.5) * 0.04;
      final local = _at(envelope, (clamped + wobble).clamp(0.0, 1.0));
      final weight = i < bands ~/ 4
          ? 1.15
          : i < bands ~/ 2
              ? 1.0
              : 0.72 + (i / bands) * 0.2;
      peaks[i] = (local * weight).clamp(0.04, 1.0);
    }

    var energy = _gain(center, 0.78);
    var bass = _gain((center * 0.65 + behind * 0.35), 0.55);
    // Flat compressed files get a soft playing pulse so the halo still moves.
    final mean = envelope.fold<double>(0, (a, b) => a + b) / n;
    if (mean < 0.18) {
      final phase = clamped * math.pi * 2 * 48; // ~tempo shimmer across track
      final pulse = 0.22 + 0.18 * (0.5 + 0.5 * math.sin(phase));
      energy = math.max(energy, pulse);
      bass = math.max(bass, pulse * 0.85);
      for (var i = 0; i < bands; i++) {
        final swirl = 0.5 + 0.5 * math.sin(phase + i * 0.35);
        peaks[i] = math.max(peaks[i], 0.12 + 0.28 * swirl * pulse);
      }
    }

    final beat = rise > 0.045 && drop <= 0.02 && center > prevEnergy + 0.02;
    final strength = beat ? (0.45 + rise * 3.2).clamp(0.0, 1.0) : rise.clamp(0.0, 1.0);

    return DesktopHaloFrame(
      peaks: peaks,
      energy: energy.clamp(0.0, 1.0),
      bass: bass.clamp(0.0, 1.0),
      beat: beat,
      strength: strength,
    );
  }

  static double _at(List<double> env, double t) {
    final n = env.length;
    if (n == 1) return env.first;
    final idx = t * (n - 1);
    final i0 = idx.floor().clamp(0, n - 1);
    final i1 = math.min(n - 1, i0 + 1);
    final frac = idx - i0;
    return env[i0] * (1 - frac) + env[i1] * frac;
  }

  static double _gain(double value, double curve) {
    final clamped = value.clamp(0.0, 1.0);
    return math.pow(clamped, curve).toDouble();
  }
}
