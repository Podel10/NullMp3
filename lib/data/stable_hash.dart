import 'dart:convert';

/// Content-stable FNV-1a 32-bit hex key. Survives Dart/Flutter upgrades
/// (unlike [Object.hashCode], which is not guaranteed across VMs).
String stablePathKey(String path) {
  final bytes = utf8.encode(path);
  var hash = 2166136261;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16);
}

String legacyPathKey(String path) => path.hashCode.toRadixString(16);
