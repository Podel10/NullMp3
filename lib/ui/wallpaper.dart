import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../theme/app_theme.dart';

/// Gallery wallpaper with a *cached* blur so ImageFilter does not re-run every frame.
class AppWallpaper extends StatelessWidget {
  const AppWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    if (settings.themeId != AppThemeId.gallery || !settings.hasWallpaper) {
      return child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _CachedBlurWallpaper(
            path: settings.wallpaperPath!,
            revision: settings.wallpaperRevision,
            blur: settings.wallpaperBlur,
          ),
        ),
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

class _CachedBlurWallpaper extends StatefulWidget {
  const _CachedBlurWallpaper({
    required this.path,
    required this.revision,
    required this.blur,
  });

  final String path;
  final int revision;
  final double blur;

  @override
  State<_CachedBlurWallpaper> createState() => _CachedBlurWallpaperState();
}

class _CachedBlurWallpaperState extends State<_CachedBlurWallpaper> {
  ui.Image? _image;
  Object? _token;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant _CachedBlurWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.revision != widget.revision ||
        (oldWidget.blur - widget.blur).abs() > 0.02) {
      _rebuild();
    }
  }

  @override
  void dispose() {
    _token = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _rebuild() async {
    final token = Object();
    _token = token;
    final path = widget.path;
    final blur = widget.blur.clamp(0.0, 1.0);
    try {
      final bytes = await File(path).readAsBytes();
      if (!identical(_token, token)) return;
      final codec = await ui.instantiateImageCodec(
        bytes,
        // Downscale before blur — huge GPU win on phones.
        targetWidth: blur > 0.05 ? 480 : 720,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!identical(_token, token)) {
        frame.image.dispose();
        return;
      }
      final src = frame.image;
      if (blur <= 0.02) {
        final previous = _image;
        _image = src;
        if (mounted) setState(() {});
        previous?.dispose();
        return;
      }
      // Soft blur once into an offscreen image (sigma capped well below live *80).
      final sigma = (blur * 14).clamp(0.5, 14.0);
      ui.Image? blurred;
      try {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final paint = Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);
        final scale = 1 + blur * 0.12;
        final w = src.width.toDouble();
        final h = src.height.toDouble();
        canvas.translate(w * (1 - scale) / 2, h * (1 - scale) / 2);
        canvas.scale(scale);
        canvas.drawImage(src, Offset.zero, paint);
        final picture = recorder.endRecording();
        blurred = await picture.toImage(src.width, src.height);
        picture.dispose();
      } catch (_) {
        blurred = null;
      }
      src.dispose();
      if (!identical(_token, token)) {
        blurred?.dispose();
        return;
      }
      final previous = _image;
      _image = blurred ?? previous;
      if (blurred != null && mounted) setState(() {});
      if (blurred != null) previous?.dispose();
    } catch (_) {
      if (!identical(_token, token)) return;
      final previous = _image;
      _image = null;
      if (mounted) setState(() {});
      previous?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return Image.file(
        File(widget.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: 720,
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: image.width.toDouble(),
        height: image.height.toDouble(),
        child: RawImage(image: image, fit: BoxFit.cover, filterQuality: FilterQuality.low),
      ),
    );
  }
}
