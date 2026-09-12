import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/player.dart';
import '../state/settings.dart';

const _kMinRate = 0.5;
const _kMaxRate = 1.5;
const _kRateStep = 0.05;

void showSpeedPitchSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    backgroundColor: const Color(0xFF0E2A38),
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => const SpeedPitchSheet(),
  );
}

double snapPlaybackRate(double value) {
  final clamped = value.clamp(_kMinRate, _kMaxRate);
  final steps = ((clamped - _kMinRate) / _kRateStep).round();
  return (50 + steps * 5) / 100.0;
}

String formatPlaybackRate(double value) {
  final hundredths = (snapPlaybackRate(value) * 100).round();
  if (hundredths % 10 == 0) {
    return (hundredths / 100).toStringAsFixed(1);
  }
  return (hundredths / 100).toStringAsFixed(2);
}

class SpeedPitchSheet extends StatefulWidget {
  const SpeedPitchSheet({super.key});

  @override
  State<SpeedPitchSheet> createState() => _SpeedPitchSheetState();
}

class _SpeedPitchSheetState extends State<SpeedPitchSheet> {
  late double _speed;
  late double _pitch;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _speed = snapPlaybackRate(settings.speed);
    _pitch = snapPlaybackRate(settings.pitch);
  }

  @override
  Widget build(BuildContext context) {
    const divisions = 20;
    final s = context.s;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RateControl(
              title: s.playbackSpeedValue(formatPlaybackRate(_speed)),
              value: _speed,
              divisions: divisions,
              onChanged: (value) {
                setState(() => _speed = value);
                context.read<PlayerController>().setSpeed(value, persist: false);
              },
              onChangeEnd: (value) => context.read<PlayerController>().setSpeed(value),
              onReset: () async {
                setState(() => _speed = 1);
                await context.read<PlayerController>().setSpeed(1);
              },
            ),
            const SizedBox(height: 22),
            _RateControl(
              title: s.playbackPitchValue(formatPlaybackRate(_pitch)),
              value: _pitch,
              divisions: divisions,
              onChanged: (value) {
                setState(() => _pitch = value);
                context.read<PlayerController>().setPitch(value, persist: false);
              },
              onChangeEnd: (value) => context.read<PlayerController>().setPitch(value),
              onReset: () async {
                setState(() => _pitch = 1);
                await context.read<PlayerController>().setPitch(1);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RateControl extends StatelessWidget {
  const _RateControl({
    required this.title,
    required this.value,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });

  final String title;
  final double value;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              child: Text(context.s.reset, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            min: _kMinRate,
            max: _kMaxRate,
            divisions: divisions,
            value: value.clamp(_kMinRate, _kMaxRate),
            onChanged: (value) => onChanged(snapPlaybackRate(value)),
            onChangeEnd: (value) => onChangeEnd(snapPlaybackRate(value)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(context.s.slow, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              Expanded(
                child: Text(
                  context.s.normal,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              Text(context.s.fast, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
