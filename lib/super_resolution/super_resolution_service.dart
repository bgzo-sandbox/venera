import 'dart:io';
import 'dart:typed_data';

import 'package:venera/foundation/log.dart';
import 'package:venera/super_resolution/cache/super_resolution_cache_store.dart';
import 'package:venera/super_resolution/implementations/anime4k/anime4k_processor.dart';
import 'package:venera/super_resolution/models/super_resolution_algorithm.dart';
import 'package:venera/super_resolution/models/super_resolution_request.dart';
import 'package:venera/super_resolution/models/super_resolution_result.dart';
import 'package:venera/super_resolution/super_resolution_processor.dart';
import 'package:venera/super_resolution/runtime/super_resolution_task_scheduler.dart';

/// Super resolution module facade.
///
/// External callers should depend on this class instead of talking to a
/// concrete algorithm implementation directly. That keeps cache behavior,
/// in-flight dedupe, logging and future algorithm selection in one place.
///
/// When the project adds new upscalers later, the normal path is:
/// 1. add a new value in [SuperResolutionAlgorithm]
/// 2. add a matching [SuperResolutionProcessor] implementation
/// 3. route it in [_selectProcessor]
class SuperResolutionService {
  SuperResolutionService._();

  static final SuperResolutionService instance = SuperResolutionService._();

  /// Persistent cache for processed outputs.
  final SuperResolutionCacheStore cacheStore = SuperResolutionCacheStore();

  /// Shared scheduler used to cap concurrency and dedupe repeated requests.
  final SuperResolutionTaskScheduler scheduler = SuperResolutionTaskScheduler();

  /// Current Anime4K-backed processor.
  final Anime4KProcessor _anime4KProcessor = const Anime4KProcessor();

  /// Initializes module infrastructure that depends on runtime directories.
  Future<void> init() {
    return cacheStore.init();
  }

  /// Sets the cache size limit in megabytes, mirroring the app-wide cache
  /// limit so processed outputs cannot accumulate unboundedly.
  void setCacheLimitSize(int mb) {
    cacheStore.setLimitSize(mb);
  }

  /// Processes raw image bytes and returns processed bytes when successful.
  ///
  /// This is the main entry used by the reader. The service first checks the
  /// cache, then schedules the processing task to avoid duplicate work.
  Future<Uint8List?> processImage(SuperResolutionRequest request) {
    return _processImage(request);
  }

  /// Convenience API for non-reader call sites that start from a file path.
  ///
  /// Unlike [processImage], this returns a structured result so callers can
  /// distinguish "nothing produced" from explicit failure reasons.
  Future<SuperResolutionResult> processFile({
    required String filePath,
    SuperResolutionAlgorithm algorithm = SuperResolutionAlgorithm.anime4k,
    double scaleFactor = 2.0,
    double pushStrength = 0.31,
    double pushGradStrength = 1.0,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Log.error('SuperResolution', 'file not found: $filePath');
        return const SuperResolutionResult.failure('file_not_found');
      }

      final imageBytes = await file.readAsBytes();
      final result = await processImage(
        SuperResolutionRequest(
          cacheKey: filePath,
          imageBytes: imageBytes,
          algorithm: algorithm,
          scaleFactor: scaleFactor,
          pushStrength: pushStrength,
          pushGradStrength: pushGradStrength,
        ),
      );
      if (result == null) {
        Log.error('SuperResolution', 'processing failed for file: $filePath');
        return const SuperResolutionResult.failure('processing_failed');
      }
      Log.info(
        'SuperResolution',
        'processed file: path=$filePath bytes=${result.length}',
      );
      return SuperResolutionResult.success(result);
    } catch (e) {
      Log.error('SuperResolution', 'file processing error: $e');
      return SuperResolutionResult.failure('file_processing_error: $e');
    }
  }

  Future<void> clearCache() {
    return cacheStore.clear();
  }

  Future<int> getCacheSize() {
    return cacheStore.getCacheSize();
  }

  /// Internal processing pipeline: cache lookup -> scheduled execution ->
  /// cache writeback.
  ///
  /// The second cache lookup inside the scheduler closes the race where two
  /// near-simultaneous callers miss the first read before one of them finishes
  /// processing and writes the result.
  /// Attempts a cache read for any encoding the processors may have produced.
  Future<Uint8List?> _readCache(String key) async {
    for (final extension in const ['png', 'jpg']) {
      final cached = await cacheStore.read(key, extension: extension);
      if (cached != null) {
        return cached;
      }
    }
    return null;
  }

  Future<Uint8List?> _processImage(SuperResolutionRequest request) async {
    final cached = await _readCache(request.effectiveCacheKey);
    if (cached != null) {
      Log.info(
        'SuperResolution',
        'cache hit: algorithm=${request.algorithm.name} cacheKey=${request.cacheKey} bytes=${cached.length}',
      );
      return cached;
    }

    return scheduler.schedule<Uint8List?>(request.effectiveCacheKey, () async {
      final cachedResult = await _readCache(request.effectiveCacheKey);
      if (cachedResult != null) {
        Log.info(
          'SuperResolution',
          'cache hit in scheduler: algorithm=${request.algorithm.name} cacheKey=${request.cacheKey} bytes=${cachedResult.length}',
        );
        return cachedResult;
      }

      Log.info(
        'SuperResolution',
        'processing start: algorithm=${request.algorithm.name} cacheKey=${request.cacheKey} scale=${request.scaleFactor} push=${request.pushStrength} grad=${request.pushGradStrength} queued=${scheduler.queuedTasks} running=${scheduler.runningTasks}',
      );
      final output = await _selectProcessor(request.algorithm).process(request);
      if (output != null) {
        await cacheStore.write(
          request.effectiveCacheKey,
          output.bytes,
          extension: output.fileExtension,
        );
        Log.info(
          'SuperResolution',
          'processing complete: algorithm=${request.algorithm.name} cacheKey=${request.cacheKey} bytes=${output.bytes.length}',
        );
        return output.bytes;
      } else {
        Log.error(
          'SuperResolution',
          'processing returned null: algorithm=${request.algorithm.name} cacheKey=${request.cacheKey}',
        );
      }
      return null;
    });
  }

  /// Central extension point for algorithm routing.
  ///
  /// Keep algorithm selection here so UI and reader code never need to know
  /// which concrete processor class is responsible for a request.
  SuperResolutionProcessor _selectProcessor(
    SuperResolutionAlgorithm algorithm,
  ) {
    switch (algorithm) {
      case SuperResolutionAlgorithm.anime4k:
        return _anime4KProcessor;
    }
  }
}
