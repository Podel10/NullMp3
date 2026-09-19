import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'l10n/app_language.dart';
import 'state/library.dart';
import 'state/player.dart';
import 'state/settings.dart';
import 'theme/app_theme.dart';
import 'ui/home.dart';
import 'ui/wallpaper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    JustAudioMediaKit.ensureInitialized();
  }

  final settings = SettingsController();
  final library = LibraryController();
  final player = PlayerController(library: library, settings: settings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: player),
      ],
      child: const NullMp3App(),
    ),
  );
}

class NullMp3App extends StatelessWidget {
  const NullMp3App({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final custom = settings.themeId == AppThemeId.custom;
    final gallery = settings.themeId == AppThemeId.gallery;
    final customDark = settings.customBackground.computeLuminance() < 0.45;
    final customTheme = AppTheme.data(
      AppThemeId.custom,
      settings.accent,
      customBackground: settings.customBackground,
    );
    final galleryTheme = AppTheme.data(AppThemeId.gallery, settings.accent);
    return MaterialApp(
      title: 'Null MP3',
      debugShowCheckedModeBanner: false,
      locale: settings.language.locale,
      supportedLocales: AppLanguage.all.map((item) => item.locale).toList(growable: false),
      localeResolutionCallback: (locale, supported) {
        final selected = settings.language.locale;
        for (final item in supported) {
          if (item.languageCode == selected.languageCode &&
              item.countryCode == selected.countryCode) {
            return item;
          }
        }
        for (final item in supported) {
          if (item.languageCode == selected.languageCode) return item;
        }
        return const Locale('en');
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: gallery
          ? ThemeMode.dark
          : custom
              ? (customDark ? ThemeMode.dark : ThemeMode.light)
              : settings.themeMode,
      theme: custom && !customDark
          ? customTheme
          : AppTheme.data(
              settings.themeId == AppThemeId.sand ? AppThemeId.sand : AppThemeId.light,
              settings.accent,
            ),
      darkTheme: gallery
          ? galleryTheme
          : custom && customDark
              ? customTheme
              : AppTheme.data(
                  switch (settings.themeId) {
                    AppThemeId.black => AppThemeId.black,
                    AppThemeId.midnight => AppThemeId.midnight,
                    _ => AppThemeId.dark,
                  },
                  settings.accent,
                ),
      builder: (context, child) => AppWallpaper(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}
