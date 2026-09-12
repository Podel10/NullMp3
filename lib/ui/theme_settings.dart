import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/settings.dart';
import '../theme/app_theme.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final s = context.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.themeSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [
              for (final preset in AppTheme.presets)
                _ThemeCard(
                  preset: preset,
                  preview: switch (preset.id) {
                    AppThemeId.custom => settings.customBackground,
                    _ => preset.preview,
                  },
                  selected: settings.themeId == preset.id,
                  onTap: () async {
                    if (preset.id == AppThemeId.gallery) {
                      if (!settings.hasWallpaper) {
                        await settings.pickWallpaper();
                      } else {
                        await settings.setThemeId(AppThemeId.gallery);
                      }
                      return;
                    }
                    await settings.setThemeId(preset.id);
                  },
                ),
            ],
          ),
          if (settings.themeId == AppThemeId.gallery) ...[
            const SizedBox(height: 24),
            Text(s.gallery, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_outlined),
              title: Text(settings.hasWallpaper ? s.changePicture : s.pickFromGallery),
              onTap: settings.pickWallpaper,
            ),
            const SizedBox(height: 4),
            Text(s.blur, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            Slider(
              min: 0,
              max: 1,
              value: settings.wallpaperBlur,
              onChanged: settings.setWallpaperBlur,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Text(s.none, style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  Text(s.full, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
          if (settings.themeId == AppThemeId.custom) ...[
            const SizedBox(height: 24),
            Text(s.customTheme, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            _ColorEditor(
              label: s.background,
              color: settings.customBackground,
              onChanged: settings.setCustomBackground,
            ),
          ],
          if (settings.themeId == AppThemeId.custom || settings.useCustomAccent) ...[
            const SizedBox(height: 16),
            _ColorEditor(
              label: s.accent,
              color: settings.useCustomAccent ? settings.customAccent : settings.accent,
              onChanged: settings.setCustomAccent,
            ),
          ],
          const SizedBox(height: 24),
          Text(s.accent, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < Accents.colors.length; i++)
                GestureDetector(
                  onTap: () => settings.setAccent(i),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Accents.colors[i],
                    child: !settings.useCustomAccent && settings.accentIndex == i
                        ? Icon(
                            Icons.check_rounded,
                            color: Accents.colors[i].computeLuminance() > 0.55 ? Colors.black : Colors.white,
                            size: 18,
                          )
                        : null,
                  ),
                ),
              GestureDetector(
                onTap: () => settings.setCustomAccent(settings.customAccent),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: settings.customAccent,
                  child: settings.useCustomAccent
                      ? Icon(
                          Icons.check_rounded,
                          color: settings.customAccent.computeLuminance() > 0.55 ? Colors.black : Colors.white,
                          size: 18,
                        )
                      : const Icon(Icons.tune_rounded, size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final Color preview;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onPreview = preview.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final border = selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor;
    return Material(
      color: preview,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: onPreview,
              ),
              const Spacer(),
              Text(
                context.s.themeLabel(preset.id),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onPreview),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorEditor extends StatelessWidget {
  const _ColorEditor({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        _HueSlider(
          value: hsv.hue,
          onChanged: (hue) => onChanged(hsv.withHue(hue).toColor()),
        ),
        _ToneSlider(
          value: hsv.saturation,
          color: hsv.withSaturation(1).withValue(1).toColor(),
          onChanged: (saturation) => onChanged(hsv.withSaturation(saturation).toColor()),
        ),
        _ToneSlider(
          value: hsv.value,
          color: hsv.withSaturation(0).withValue(1).toColor(),
          endColor: hsv.withValue(1).toColor(),
          onChanged: (value) => onChanged(hsv.withValue(value).toColor()),
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 8,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        min: 0,
        max: 359,
        value: value.clamp(0, 359),
        onChanged: onChanged,
      ),
    );
  }
}

class _ToneSlider extends StatelessWidget {
  const _ToneSlider({
    required this.value,
    required this.color,
    required this.onChanged,
    this.endColor,
  });

  final double value;
  final Color color;
  final Color? endColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: color,
        inactiveTrackColor: (endColor ?? Colors.white).withValues(alpha: 0.25),
        thumbColor: color,
        trackHeight: 8,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      child: Slider(
        min: 0,
        max: 1,
        value: value.clamp(0, 1),
        onChanged: onChanged,
      ),
    );
  }
}
