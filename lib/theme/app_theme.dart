import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

enum AppThemeId { system, dark, black, midnight, light, sand, custom, gallery }

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.preview,
  });

  final AppThemeId id;
  final String label;
  final Color preview;
}

class Accents {
  static const colors = <Color>[
    Color(0xFFFFC933),
    Color(0xFFFF5722),
    Color(0xFFFF8A00),
    Color(0xFFE91E63),
    Color(0xFF7C4DFF),
    Color(0xFF2979FF),
    Color(0xFF00BFA5),
    Color(0xFF00C853),
  ];

  static const labels = <String>[
    'Yellow',
    'Orange',
    'Amber',
    'Pink',
    'Purple',
    'Blue',
    'Teal',
    'Green',
  ];
}

class AppTheme {
  static const presets = <ThemePreset>[
    ThemePreset(id: AppThemeId.system, label: 'System', preview: Color(0xFF9E9E9E)),
    ThemePreset(id: AppThemeId.dark, label: 'Dark', preview: Color(0xFF121212)),
    ThemePreset(id: AppThemeId.black, label: 'Black', preview: Color(0xFF000000)),
    ThemePreset(id: AppThemeId.midnight, label: 'Midnight', preview: Color(0xFF0B1C24)),
    ThemePreset(id: AppThemeId.light, label: 'Light', preview: Color(0xFFF6F3F0)),
    ThemePreset(id: AppThemeId.sand, label: 'Sand', preview: Color(0xFFEFE4D4)),
    ThemePreset(id: AppThemeId.custom, label: 'Custom', preview: Color(0xFF5C4D7A)),
    ThemePreset(id: AppThemeId.gallery, label: 'Gallery', preview: Color(0xFF2A2A2A)),
  ];

  static ThemeData data(AppThemeId id, Color accent, {Color? customBackground}) {
    final wallpaper = id == AppThemeId.gallery;
    final scaffold = switch (id) {
      AppThemeId.black => const Color(0xFF000000),
      AppThemeId.midnight => const Color(0xFF0B1C24),
      AppThemeId.sand => const Color(0xFFEFE4D4),
      AppThemeId.light => const Color(0xFFF6F3F0),
      AppThemeId.custom => customBackground ?? const Color(0xFF1B1428),
      AppThemeId.gallery => const Color(0x00000000),
      AppThemeId.system || AppThemeId.dark => const Color(0xFF121212),
    };
    final brightness = switch (id) {
      AppThemeId.light || AppThemeId.sand => Brightness.light,
      AppThemeId.custom => scaffold.computeLuminance() < 0.45 ? Brightness.dark : Brightness.light,
      _ => Brightness.dark,
    };
    final isDark = brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: accent.computeLuminance() > 0.55 ? const Color(0xFF1A1A1A) : Colors.white,
      secondary: accent,
      onSecondary: accent.computeLuminance() > 0.55 ? const Color(0xFF1A1A1A) : Colors.white,
      surface: scaffold,
      onSurface: onSurface,
      error: isDark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F),
      onError: Colors.white,
    );
    return _base(scheme, accent, brightness, scaffold, wallpaper: wallpaper);
  }

  static Color ambientFromArtwork(Color? source, {required bool dark}) {
    if (source == null) {
      return dark ? const Color(0xFF121212) : const Color(0xFFF3EEE8);
    }
    final hsl = HSLColor.fromColor(source);
    if (dark) {
      return hsl
          .withSaturation((hsl.saturation * 0.42).clamp(0.06, 0.32))
          .withLightness(0.12)
          .toColor();
    }
    return hsl
        .withSaturation((hsl.saturation * 0.28).clamp(0.04, 0.22))
        .withLightness(0.90)
        .toColor();
  }

  static ThemeData _base(
    ColorScheme scheme,
    Color accent,
    Brightness brightness,
    Color scaffold, {
    bool wallpaper = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final textTheme = GoogleFonts.outfitTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ).apply(
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'Noto Sans SC',
        'PingFang SC',
        'sans-serif',
      ],
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: accent,
        labelColor: accent,
        unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.55),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        tabAlignment: TabAlignment.start,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.15),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.16),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Color.lerp(scaffold, isDark ? Colors.white : Colors.black, isDark ? 0.06 : 0.04),
        indicatorColor: accent.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: wallpaper
            ? const Color(0xCC141414)
            : Color.lerp(scaffold, isDark ? Colors.white : Colors.black, isDark ? 0.05 : 0.03),
      ),
      dividerColor: scheme.onSurface.withValues(alpha: 0.08),
      bottomSheetTheme: BottomSheetThemeData(
        dragHandleColor: scheme.onSurface.withValues(alpha: 0.28),
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurface.withValues(alpha: 0.7),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFF323232),
      ),
    );
  }
}
