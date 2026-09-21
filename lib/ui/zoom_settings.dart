import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/settings.dart';

class ZoomSettingsScreen extends StatelessWidget {
  const ZoomSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final s = context.s;
    final percent = (settings.uiScale * 100).round();
    final minP = (SettingsController.minUiScale * 100).round();
    final maxP = (SettingsController.maxUiScale * 100).round();
    return Scaffold(
      appBar: AppBar(title: Text(s.zoomSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.zoomLevel, style: Theme.of(context).textTheme.titleSmall),
              ),
              Text(
                '$percent%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            s.zoomHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(
                tooltip: s.zoomOut,
                onPressed: settings.uiScale > SettingsController.minUiScale
                    ? settings.zoomOut
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Slider(
                  min: SettingsController.minUiScale,
                  max: SettingsController.maxUiScale,
                  divisions: ((SettingsController.maxUiScale -
                              SettingsController.minUiScale) /
                          SettingsController.uiScaleStep)
                      .round(),
                  value: settings.uiScale.clamp(
                    SettingsController.minUiScale,
                    SettingsController.maxUiScale,
                  ),
                  label: '$percent%',
                  onChanged: settings.setUiScale,
                ),
              ),
              IconButton(
                tooltip: s.zoomIn,
                onPressed: settings.uiScale < SettingsController.maxUiScale
                    ? settings.zoomIn
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 52),
            child: Row(
              children: [
                Text('$minP%', style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                Text('$maxP%', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.refresh_rounded),
            title: Text(s.resetZoom),
            enabled: (settings.uiScale - 1.0).abs() >= 0.001,
            onTap: settings.resetUiScale,
          ),
        ],
      ),
    );
  }
}
