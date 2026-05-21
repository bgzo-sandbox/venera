import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:venera/foundation/log.dart';

/// File-backed cache for processed super resolution outputs.
///
/// The cache is intentionally generic: it stores final bytes keyed by the
/// request signature, without knowing which algorithm produced them. That lets
/// the facade swap or add algorithms while keeping one storage policy.
class SuperResolutionCacheStore {
  SuperResolutionCacheStore();

  static const String _cacheDirectoryName = 'super_resolution_cache';

  String? _cacheDir;

  String? get cacheDirectory => _cacheDir;

  /// Resolves and creates the temporary cache directory at startup.
  Future<void> init() async {
    try {
      final dir = await getTemporaryDirectory();
      _cacheDir = path.join(dir.path, _cacheDirectoryName);
      final cacheDirectory = Directory(_cacheDir!);
      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }
      Log.info('SuperResolution', 'cache initialized at $_cacheDir');
    } catch (e) {
      Log.error('SuperResolution', 'cache init error: $e');
    }
  }

  /// Maps a logical cache key to a file path on disk.
  ///
  /// The hashed filename avoids leaking raw source paths and keeps file names
  /// short even when the upstream cache key contains long request metadata.
  String? getCachePath(String key) {
    if (_cacheDir == null) {
      return null;
    }
    return path.join(_cacheDir!, '${key.hashCode.abs()}.png');
  }

  /// Reads cached bytes for a previously processed request.
  Future<Uint8List?> read(String key) async {
    final cachePath = getCachePath(key);
    if (cachePath == null) {
      return null;
    }
    final file = File(cachePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      return await file.readAsBytes();
    } catch (e) {
      Log.error('SuperResolution', 'cache read error: $e');
      return null;
    }
  }

  /// Writes processed bytes to disk for future reuse.
  Future<void> write(String key, Uint8List data) async {
    final cachePath = getCachePath(key);
    if (cachePath == null) {
      return;
    }
    try {
      final file = File(cachePath);
      await file.writeAsBytes(data);
    } catch (e) {
      Log.error('SuperResolution', 'cache write error: $e');
    }
  }

  /// Clears all cached outputs while keeping the cache directory reusable.
  Future<void> clear() async {
    if (_cacheDir == null) {
      return;
    }
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      Log.info('SuperResolution', 'cache cleared');
    } catch (e) {
      Log.error('SuperResolution', 'cache clear error: $e');
    }
  }

  /// Computes total cache usage in bytes for settings and diagnostics.
  Future<int> getCacheSize() async {
    if (_cacheDir == null) {
      return 0;
    }
    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        return 0;
      }

      var totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      Log.error('SuperResolution', 'cache size error: $e');
      return 0;
    }
  }
}
