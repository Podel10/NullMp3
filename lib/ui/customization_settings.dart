import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/settings.dart';

/// Windows-only: interactive cover + keyboard shortcut reference.
class CustomizationSettingsScreen extends StatelessWidget {
  const CustomizationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.customization)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.interactiveCover),
            subtitle: Text(s.interactiveCoverHint),
            value: settings.interactiveCover,
            onChanged: settings.setInteractiveCover,
          ),
          if (settings.interactiveCover) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CoverModeCard(
                    selected: settings.interactiveCoverMode == InteractiveCoverMode.horizontal,
                    title: s.interactiveCoverHorizontal,
                    hint: s.interactiveCoverHorizontalHint,
                    preview: const _HorizontalModePreview(),
                    onTap: () => settings.setInteractiveCoverMode(InteractiveCoverMode.horizontal),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CoverModeCard(
                    selected: settings.interactiveCoverMode == InteractiveCoverMode.vertical,
                    title: s.interactiveCoverVertical,
                    hint: s.interactiveCoverVerticalHint,
                    preview: const _VerticalModePreview(),
                    onTap: () => settings.setInteractiveCoverMode(InteractiveCoverMode.vertical),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          Text(s.hotkeys, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _HotkeyLine(s.hotkeyPlayPause),
          _HotkeyLine(s.hotkeySeek),
          _HotkeyLine(s.hotkeyVolume),
          _HotkeyLine(s.hotkeyMute),
        ],
      ),
    );
  }
}

class _HotkeyLine extends StatelessWidget {
  const _HotkeyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _CoverModeCard extends StatelessWidget {
  const _CoverModeCard({
    required this.selected,
    required this.title,
    required this.hint,
    required this.preview,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String hint;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = selected ? theme.colorScheme.primary : theme.dividerColor;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1.15, child: preview),
              const SizedBox(height: 10),
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(hint, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizontalModePreview extends StatelessWidget {
  const _HorizontalModePreview();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.white24),
                  FractionallySizedBox(
                    widthFactor: 0.62,
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(color: primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalModePreview extends StatelessWidget {
  const _VerticalModePreview();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 18,
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.62,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
