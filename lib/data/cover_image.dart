import 'dart:io';
import 'dart:math' as math;
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

Future<String?> playbackContentUri(String path) async {
  if (kIsWeb || !Platform.isAndroid || path.isEmpty || path.startsWith('content:')) {
    return path.startsWith('content:') ? path : null;
  }
  try {
    final uri = await _filesChannel.invokeMethod<String>('playbackUri', {
      'path': path,
    }).timeout(const Duration(seconds: 2));
    if (uri != null && uri.startsWith('content:')) return uri;
  } catch (_) {}
  return null;
}

/// Returns a file path ExoPlayer can actually open. Copies through MediaStore
/// when the original path exists but is unreadable.
Future<String?> openPlaybackFile(String path) async {
  if (path.isEmpty) return null;
  if (path.startsWith('content:')) return path;
  if (kIsWeb || !Platform.isAndroid) {
    return File(path).existsSync() ? path : null;
  }
  try {
    final opened = await _filesChannel.invokeMethod<String>('openPlayback', {
      'path': path,
    }).timeout(const Duration(seconds: 20));
    if (opened != null && opened.isNotEmpty) return opened;
  } catch (_) {}
  return null;
}

Future<Uint8List?> grabVideoPoster(String path, {int maxSide = 360}) async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    final data = await _filesChannel.invokeMethod<dynamic>('videoPoster', {
      'path': path,
      'maxSide': maxSide,
    }).timeout(const Duration(seconds: 12));
    final bytes = _asBytes(data);
    if (bytes != null && bytes.length > 32) return bytes;
  } catch (_) {}
  return null;
}

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
      if (data != null && data.isNotEmpty) {
        return await downscaleCover(normalizeCoverBytes(Uint8List.fromList(data)));
      }
    } catch (_) {}
    // Stay on the native picker path — do not fall through to FilePicker on Android.
    return null;
  }
  try {
    // Single-file pick — allowMultiple defaults to true on pickFiles and can
    // return a bad/empty first entry on a second open (especially on Windows).
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'mp4', 'webm'],
      compressionQuality: 0,
      windowsOptions: const WindowsOptions(lockParentWindow: true),
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return await downscaleCover(normalizeCoverBytes(Uint8List.fromList(bytes)));
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

/// Still JPEG/PNG for ID3. GIF/WebP/video become the first frame so the MP3 stays playable.
Future<Uint8List?> flattenCoverForEmbed(Uint8List bytes, {int maxSide = 512}) async {
  try {
    final still = !isAnimatedCover(bytes);
    final mime = mimeOfImage(bytes);
    if (still && (mime == 'image/jpeg' || mime == 'image/png') && bytes.lengthInBytes <= 280 * 1024) {
      return bytes;
    }
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxSide);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return still ? bytes : null;
    return data.buffer.asUint8List();
  } catch (_) {
    return isAnimatedCover(bytes) ? null : bytes;
  }
}

class CoverCropSource {
  const CoverCropSource({
    required this.size,
    required this.suggested,
  });

  final Size size;
  final Rect suggested;
}

Future<CoverCropSource?> inspectCoverForCrop(Uint8List bytes) async {
  if (isAnimatedCover(bytes)) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      if (size.width < 8 || size.height < 8) return null;
      var bounds = Offset.zero & size;
      if (image.width * image.height <= 4 * 1024 * 1024) {
        final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (pixels != null) {
          bounds = _letterboxBounds(pixels.buffer.asUint8List(), image.width, image.height) ?? bounds;
        }
      }
      return CoverCropSource(size: size, suggested: _largestSquare(bounds, size));
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

Rect _largestSquare(Rect bounds, Size image) {
  final side = math.min(bounds.width, bounds.height).clamp(1.0, math.min(image.width, image.height)).toDouble();
  final left = (bounds.left + (bounds.width - side) / 2).clamp(0.0, math.max(0.0, image.width - side)).toDouble();
  final top = (bounds.top + (bounds.height - side) / 2).clamp(0.0, math.max(0.0, image.height - side)).toDouble();
  return Rect.fromLTWH(left, top, side, side);
}

Rect? _letterboxBounds(Uint8List rgba, int width, int height) {
  bool dark(int x, int y) {
    final i = (y * width + x) * 4;
    return rgba[i] < 14 && rgba[i + 1] < 14 && rgba[i + 2] < 14;
  }

  bool rowDark(int y) {
    var darkCount = 0;
    var samples = 0;
    for (var x = 0; x < width; x += 4) {
      samples++;
      if (dark(x, y)) darkCount++;
    }
    return samples > 0 && darkCount / samples >= 0.92;
  }

  bool colDark(int x) {
    var darkCount = 0;
    var samples = 0;
    for (var y = 0; y < height; y += 4) {
      samples++;
      if (dark(x, y)) darkCount++;
    }
    return samples > 0 && darkCount / samples >= 0.92;
  }

  var top = 0;
  var bottom = height - 1;
  var left = 0;
  var right = width - 1;
  while (top < bottom && rowDark(top)) {
    top++;
  }
  while (bottom > top && rowDark(bottom)) {
    bottom--;
  }
  while (left < right && colDark(left)) {
    left++;
  }
  while (right > left && colDark(right)) {
    right--;
  }
  final bounds = Rect.fromLTRB(left.toDouble(), top.toDouble(), (right + 1).toDouble(), (bottom + 1).toDouble());
  if (bounds.width < width * 0.4 || bounds.height < height * 0.4) return null;
  return bounds;
}

/// Cuts a square out of still artwork. Animated covers are left unchanged.
Future<Uint8List?> cropCoverSquare(Uint8List bytes, Rect source) async {
  if (isAnimatedCover(bytes)) return bytes;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      if (width < 2 || height < 2) return bytes;
      final maxSide = math.min(width, height);
      var side = source.width.abs().clamp(1.0, maxSide).toDouble();
      side = math.max(side, math.min(32.0, maxSide));
      final left = source.left.clamp(0.0, width - side).toDouble();
      final top = source.top.clamp(0.0, height - side).toDouble();
      final outSide = math.min(900, math.max(side.round(), 64));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(left, top, side, side),
        Rect.fromLTWH(0, 0, outSide.toDouble(), outSide.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(outSide, outSide);
      picture.dispose();
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}
