import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../theme/app_theme.dart';

class AppWallpaper extends StatelessWidget {
  const AppWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    if (settings.themeId != AppThemeId.gallery || !settings.hasWallpaper) {
      return child;
    }
    final sigma = settings.wallpaperBlur * 80;
    Widget image = Image.file(
      File(settings.wallpaperPath!),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: settings.wallpaperBlur > 0.05 ? FilterQuality.low : FilterQuality.medium,
    );
    if (sigma > 0.4) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
        child: Transform.scale(
          scale: 1 + settings.wallpaperBlur * 0.28,
          child: image,
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: image),
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.22 + settings.wallpaperBlur * 0.18),
          ),
        ),
        child,
      ],
    );
  }
}
