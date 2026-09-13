import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

const _filesChannel = MethodChannel('com.nullmp3.nullmp3/files');

const _imageFtypBrands = {
  'heic',
  'heix',
  'hevc',
  'hevx',
  'mif1',
  'msf1',
  'avif',
  'avis',
};

Uint8List? _asBytes(dynamic data) {
  if (data is Uint8List) return data;
  if (data is List<int>) return Uint8List.fromList(data);
  return null;
}

int? _findBytes(Uint8List bytes, List<int> needle, {int? maxStart}) {
  if (bytes.length < needle.length) return null;
  final last = (bytes.length - needle.length).clamp(0, maxStart ?? (bytes.length - needle.length));
  for (var i = 0; i <= last; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return null;
}

int? _gifOffset(Uint8List bytes) =>
    _findBytes(bytes, const [0x47, 0x49, 0x46, 0x38], maxStart: 64);

int? _webpOffset(Uint8List bytes) {
  final riff = _findBytes(bytes, const [0x52, 0x49, 0x46, 0x46], maxStart: 16);
  if (riff == null || riff + 12 > bytes.length) return null;
  if (bytes[riff + 8] == 0x57 &&
      bytes[riff + 9] == 0x45 &&
      bytes[riff + 10] == 0x42 &&
      bytes[riff + 11] == 0x50) {
    return riff;
  }
  return null;
}

int? _ftypOffset(Uint8List bytes, {int maxStart = 64}) =>
    _findBytes(bytes, const [0x66, 0x74, 0x79, 0x70], maxStart: maxStart);

String? _ftypBrand(Uint8List bytes, int ftyp) {
  if (ftyp + 8 > bytes.length) return null;
  return String.fromCharCodes(bytes.sublist(ftyp + 4, ftyp + 8)).toLowerCase();
}

bool isGifBytes(Uint8List bytes) => _gifOffset(bytes) != null;

bool isWebpBytes(Uint8List bytes) => _webpOffset(bytes) != null;

bool isVideoBytes(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x1A &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xDF &&
      bytes[3] == 0xA3) {
    return true;
  }
  final ftyp = _ftypOffset(bytes);
  if (ftyp == null) return false;
  final brand = _ftypBrand(bytes, ftyp);
  if (brand != null && _imageFtypBrands.contains(brand)) return false;
  return true;
}

bool isAnimatedCover(Uint8List bytes) => isGifBytes(bytes) || isWebpBytes(bytes) || isVideoBytes(bytes);

Uint8List? _embeddedVideo(Uint8List bytes) {
  if (bytes.length < 128 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  final ftyp = _findBytes(bytes, const [0x66, 0x74, 0x79, 0x70], maxStart: bytes.length - 8);
  if (ftyp == null || ftyp < 32) return null;
  final brand = _ftypBrand(bytes, ftyp);
  if (brand != null && _imageFtypBrands.contains(brand)) return null;
  final start = ftyp - 4;
  if (start <= 0) return null;
  return bytes.sublist(start);
}

Uint8List normalizeCoverBytes(Uint8List bytes) {
  final gif = _gifOffset(bytes);
  if (gif != null && gif > 0) return bytes.sublist(gif);
  final webp = _webpOffset(bytes);
  if (webp != null && webp > 0) return bytes.sublist(webp);
  final video = _embeddedVideo(bytes);
  if (video != null) return video;
  return bytes;
}

String artworkExtension(Uint8List bytes) {
  if (isGifBytes(bytes)) return 'gif';
  if (isWebpBytes(bytes)) return 'webp';
  if (isVideoBytes(bytes)) {
    if (bytes[0] == 0x1A) return 'webm';
    return 'mp4';
  }
  return 'bin';
}

String mimeOfImage(Uint8List bytes, [String? hint]) {
  if (isGifBytes(bytes)) return 'image/gif';
  if (isWebpBytes(bytes)) return 'image/webp';
  if (isVideoBytes(bytes)) return bytes[0] == 0x1A ? 'video/webm' : 'video/mp4';
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
  if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
  final ext = (hint ?? '').toLowerCase();
  if (ext.endsWith('.png')) return 'image/png';
  if (ext.endsWith('.webp')) return 'image/webp';
  if (ext.endsWith('.gif')) return 'image/gif';
  if (ext.endsWith('.mp4')) return 'video/mp4';
  return 'image/jpeg';
}

Image memoryCoverImage(
  Uint8List bytes, {
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  FilterQuality filterQuality = FilterQuality.low,
  ImageErrorWidgetBuilder? errorBuilder,
}) {
  final animated = isGifBytes(bytes) || isWebpBytes(bytes);
  return Image.memory(
    bytes,
    key: ValueKey<int>(identityHashCode(bytes)),
    fit: fit,
    gaplessPlayback: true,
    filterQuality: animated ? FilterQuality.medium : filterQuality,
    cacheWidth: animated ? null : cacheWidth,
    errorBuilder: errorBuilder,
  );
}

Future<Uint8List?> pickCoverBytes() async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await Permission.photos.request();
    } catch (_) {}
    try {
      await Permission.videos.request();
    } catch (_) {}
    try {
      await Permission.accessMediaLocation.request();
    } catch (_) {}
    try {
      final data = _asBytes(await _filesChannel.invokeMethod<dynamic>('pickImage'));
      if (data != null && data.isNotEmpty) return await downscaleCover(normalizeCoverBytes(data));
      return null;
    } catch (_) {}
  }
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'mp4', 'webm'],
      compressionQuality: 0,
    );
    for (final file in result) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return await downscaleCover(normalizeCoverBytes(bytes));
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Shrinks still album art. GIF / WebP / MP4 stay as-is so motion is kept.
Future<Uint8List> downscaleCover(Uint8List bytes, {int maxSide = 512}) async {
  if (isAnimatedCover(bytes)) return bytes;
  if (bytes.lengthInBytes <= 140 * 1024) return bytes;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    image.dispose();
    if (width <= maxSide && height <= maxSide && bytes.lengthInBytes <= 220 * 1024) {
      return bytes;
    }
    final landscape = width >= height;
    final resized = await ui.instantiateImageCodec(
      bytes,
      targetWidth: landscape ? maxSide : null,
      targetHeight: landscape ? null : maxSide,
    );
    final next = await resized.getNextFrame();
    final data = await next.image.toByteData(format: ui.ImageByteFormat.png);
    next.image.dispose();
    if (data == null) return bytes;
    return data.buffer.asUint8List();
  } catch (_) {
    return bytes;
  }
}
