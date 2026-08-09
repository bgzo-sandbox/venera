import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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

  static const int _defaultLimitSize = 2 * 1024 * 1024 * 1024;

  String? _cacheDir;

  /// Hard cap for the cache in bytes. Oldest files are evicted on write once
  /// the total size exceeds this limit.
  int _limitSize = _defaultLimitSize;

  /// Current total size of cached files in bytes.
  int _currentSize = 0;

  String? get cacheDirectory => _cacheDir;

  int get currentSize => _currentSize;

  /// Sets the cache size limit in megabytes, mirroring [CacheManager.setLimitSize].
  void setLimitSize(int mb) {
    _limitSize = mb * 1024 * 1024;
  }

  /// Resolves and creates the temporary cache directory at startup.
  Future<void> init() async {
    try {
      final dir = await getTemporaryDirectory();
      _cacheDir = path.join(dir.path, _cacheDirectoryName);
      final cacheDirectory = Directory(_cacheDir!);
      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }
      _currentSize = await getCacheSize();
      Log.info('SuperResolution', 'cache initialized at $_cacheDir');
    } catch (e) {
      Log.error('SuperResolution', 'cache init error: $e');
    }
  }

  /// Maps a logical cache key to a file path on disk.
  ///
  /// The MD5 hashed filename avoids leaking raw source paths, keeps file names
  /// short even when the upstream cache key contains long request metadata, and
  /// matches the hashing convention used by the rest of the app
  /// ([CacheManager], image favorites). The extension mirrors the actual
  /// encoding of the stored bytes so the file can be inspected directly.
  String? getCachePath(String key, {required String extension}) {
    if (_cacheDir == null) {
      return null;
    }
    final name = md5.convert(key.codeUnits).toString();
    return path.join(_cacheDir!, '$name.$extension');
  }

  /// Reads cached bytes for a previously processed request.
  Future<Uint8List?> read(String key, {required String extension}) async {
    final cachePath = getCachePath(key, extension: extension);
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
  Future<void> write(
    String key,
    Uint8List data, {
    required String extension,
  }) async {
    final cachePath = getCachePath(key, extension: extension);
    if (cachePath == null) {
      return;
    }
    try {
      final file = File(cachePath);
      await file.writeAsBytes(data);
      _currentSize += data.length;
      await _evictIfNeeded();
    } catch (e) {
      Log.error('SuperResolution', 'cache write error: $e');
    }
  }

  /// Evicts the oldest cached files until the total size is under the limit.
  Future<void> _evictIfNeeded() async {
    if (_currentSize <= _limitSize || _cacheDir == null) {
      return;
    }
    try {
      final dir = Directory(_cacheDir!);
      final files = dir.listSync().whereType<File>().toList()
        ..sort((a, b) {
          final timeComparison = a.lastModifiedSync().compareTo(
            b.lastModifiedSync(),
          );
          // Break ties deterministically: filesystems with coarse timestamp
          // granularity can report identical mtimes for distinct files.
          if (timeComparison != 0) {
            return timeComparison;
          }
          return a.path.compareTo(b.path);
        });
      for (final file in files) {
        if (_currentSize <= _limitSize) {
          break;
        }
        final size = await file.length();
        await file.delete();
        _currentSize -= size;
        if (_currentSize < 0) {
          _currentSize = 0;
        }
      }
    } catch (e) {
      Log.error('SuperResolution', 'cache eviction error: $e');
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
      _currentSize = 0;
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
      _currentSize = totalSize;
      return totalSize;
    } catch (e) {
      Log.error('SuperResolution', 'cache size error: $e');
      return 0;
    }
  }
}
