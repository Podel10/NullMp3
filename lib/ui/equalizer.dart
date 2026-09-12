import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../state/player.dart';
import '../state/settings.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  late List<double> _bands;
  late bool _enabled;
  late String _preset;
  static const labels = ['60Hz', '230Hz', '910Hz', '4kHz', '14kHz'];

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsController>();
    _bands = List<double>.from(settings.eqBands);
    _enabled = settings.eqEnabled;
    _preset = settings.eqPreset;
  }

  Future<void> _commit({String? preset}) async {
    final settings = context.read<SettingsController>();
    final player = context.read<PlayerController>();
    await settings.setEq(bands: _bands, enabled: _enabled, preset: preset ?? 'Custom');
    await player.applyEqualizer();
    if (!mounted) return;
    setState(() => _preset = preset ?? 'Custom');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.equalizer)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            value: _enabled,
            title: Text(s.enableEqualizer),
            subtitle: Text(s.equalizerHint),
            onChanged: (value) async {
              setState(() => _enabled = value);
              await _commit(preset: _preset);
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in EqPreset.presets)
                ChoiceChip(
                  label: Text(s.eqPreset(preset.name)),
                  selected: _preset == preset.name,
                  onSelected: (_) {
                    setState(() {
                      _preset = preset.name;
                      _bands = List<double>.from(preset.bands);
                    });
                    _commit(preset: preset.name);
                  },
                ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 260,
            child: Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: -1,
                            child: Slider(
                              min: -15,
                              max: 15,
                              value: _bands[i].clamp(-15, 15),
                              onChanged: (value) {
                                setState(() => _bands[i] = value);
                              },
                              onChangeEnd: (_) => _commit(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(labels[i], style: theme.textTheme.labelSmall),
                        Text(_bands[i].toStringAsFixed(1), style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
