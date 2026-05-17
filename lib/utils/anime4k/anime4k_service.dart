import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:venera/foundation/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'anime4k_upscaler.dart';

class Anime4KService {
  Anime4KService._internal();
  static final Anime4KService _instance = Anime4KService._internal();
  factory Anime4KService() => _instance;
  static Anime4KService get instance => _instance;
  String? _cacheDir;
  final Map<String, Future<Uint8List?>> _inflightTasks = {};
  static const int _maxConcurrentTasks = 2;
  int _runningTasks = 0;
  final List<Function> _taskQueue = [];

  Future<void> init() async {
    try {
      final dir = await getTemporaryDirectory();
      _cacheDir = path.join(dir.path, 'anime4k_cache');
      final cacheDirectory = Directory(_cacheDir!);
      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }
      Log.info('Anime4K', 'cache initialized at $_cacheDir');
    } catch (e) {
      Log.error('Anime4K', 'Anime4K cache init error: $e');
    }
  }

  String? _getCachePath(String key) {
    if (_cacheDir == null) return null;
    return path.join(_cacheDir!, '${key.hashCode.abs()}.png');
  }

  Future<Uint8List?> _getFromCache(String key) async {
    final cachePath = _getCachePath(key);
    if (cachePath == null) return null;
    final file = File(cachePath);
    if (await file.exists()) {
      try {
        return await file.readAsBytes();
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Future<void> _saveToCache(String key, Uint8List data) async {
    final cachePath = _getCachePath(key);
    if (cachePath == null) return;
    try {
      final file = File(cachePath);
      await file.writeAsBytes(data);
    } catch (e) {
      Log.error('Anime4K', 'Anime4K cache save error: $e');
    }
  }

  Future<Uint8List?> processImage({
    required Uint8List imageBytes,
    required String cacheKey,
    double scaleFactor = 2.0,
    double pushStrength = 0.31,
    double pushGradStrength = 1.0,
  }) async {
    final fullKey =
        '${cacheKey}_${scaleFactor}_${pushStrength}_$pushGradStrength';
    Log.info(
      'Anime4K',
      'request received: cacheKey=$cacheKey bytes=${imageBytes.length} fullKeyHash=${fullKey.hashCode.abs()}',
    );
    final cached = await _getFromCache(fullKey);
    if (cached != null) {
      Log.info('Anime4K', 'cache hit for $cacheKey bytes=${cached.length}');
      return cached;
    }
    Log.info('Anime4K', 'cache miss for $cacheKey');
    final inflight = _inflightTasks[fullKey];
    if (inflight != null) {
      Log.info('Anime4K', 'join inflight task for $cacheKey');
      return inflight;
    }

    final future = _enqueueTask(() async {
      try {
        Log.info(
          'Anime4K',
          'processing image $cacheKey, scale: $scaleFactor, push: $pushStrength, grad: $pushGradStrength, running=$_runningTasks queue=${_taskQueue.length}',
        );
        final params = Anime4KParams(
          imageBytes: imageBytes,
          pushStrength: pushStrength,
          pushGradStrength: pushGradStrength,
          scaleFactor: scaleFactor,
        );
        final result = await Anime4KUpscaler.processInIsolate(params);
        if (result != null) {
          await _saveToCache(fullKey, result);
          Log.info(
            'Anime4K',
            'processing complete for $cacheKey outputBytes=${result.length}',
          );
        } else {
          Log.info('Anime4K', 'processing returned null for $cacheKey');
        }
        return result;
      } catch (e) {
        Log.error('Anime4K', 'Anime4K processing error: $e');
        return null;
      } finally {
        _inflightTasks.remove(fullKey);
      }
    });

    _inflightTasks[fullKey] = future;
    return future;
  }

  Future<T?> _enqueueTask<T>(Future<T?> Function() task) async {
    final completer = Completer<T?>();
    _taskQueue.add(() async {
      _runningTasks++;
      try {
        final result = await task();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      } finally {
        _runningTasks--;
        _nextTask();
      }
    });
    Log.info(
      'Anime4K',
      'task enqueued: running=$_runningTasks queue=${_taskQueue.length}',
    );
    _nextTask();
    return completer.future;
  }

  void _nextTask() {
    if (_runningTasks < _maxConcurrentTasks && _taskQueue.isNotEmpty) {
      Log.info(
        'Anime4K',
        'starting queued task: running=$_runningTasks queue=${_taskQueue.length}',
      );
      final task = _taskQueue.removeAt(0);
      task();
    }
  }

  Future<Uint8List?> processFile({
    required String filePath,
    double scaleFactor = 2.0,
    double pushStrength = 0.31,
    double pushGradStrength = 1.0,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final imageBytes = await file.readAsBytes();
      return processImage(
        imageBytes: imageBytes,
        cacheKey: filePath,
        scaleFactor: scaleFactor,
        pushStrength: pushStrength,
        pushGradStrength: pushGradStrength,
      );
    } catch (e) {
      Log.error('Anime4K', 'Anime4K file processing error: $e');
      return null;
    }
  }

  Future<void> clearCache() async {
    if (_cacheDir == null) return;
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
      Log.info('Anime4K', 'Anime4K: cache cleared');
    } catch (e) {
      Log.error('Anime4K', 'Anime4K cache clear error: $e');
    }
  }

  Future<int> getCacheSize() async {
    if (_cacheDir == null) return 0;
    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return 0;
      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}
