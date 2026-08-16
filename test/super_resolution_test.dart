import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/super_resolution/cache/super_resolution_cache_store.dart';
import 'package:venera/super_resolution/implementations/anime4k/anime4k_processor.dart';
import 'package:venera/super_resolution/implementations/anime4k/anime4k_upscaler.dart';
import 'package:venera/super_resolution/runtime/super_resolution_task_scheduler.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tempDir);

  final String tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

void main() {
  group('isPngBytes', () {
    test('detects PNG magic bytes', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      expect(isPngBytes(png), isTrue);
    });

    test('rejects JPEG magic bytes', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
      expect(isPngBytes(jpeg), isFalse);
    });

    test('rejects short buffers', () {
      expect(isPngBytes(Uint8List(3)), isFalse);
    });
  });

  group('Anime4KUpscaler pixel cap', () {
    test('clamps scale so output stays within 8MP', () {
      // 1000x1000 = 1MP source with an extreme scale factor: the output cap
      // must clamp the effective scale to sqrt(8) instead of using 8x.
      final source = img.Image(width: 1000, height: 1000);
      final upscaler = Anime4KUpscaler(scaleFactor: 8.0);
      final result = upscaler.upscale(source);
      final pixels = result.width * result.height;
      expect(pixels, lessThanOrEqualTo(kMaxOutputPixels));
      expect(pixels, greaterThanOrEqualTo(1000 * 1000));
    });

    test('returns the source untouched when it exceeds the cap', () {
      // 3000x4000 = 12MP source already exceeds the 8MP output cap.
      final source = img.Image(width: 3000, height: 4000);
      final upscaler = Anime4KUpscaler(scaleFactor: 1.0);
      expect(identical(upscaler.upscale(source), source), isTrue);
    });

    test('8MP boundary: 2828x2828 processes, 2829x2829 skips', () {
      final inside = img.Image(width: 2828, height: 2828);
      expect(inside.width * inside.height, lessThanOrEqualTo(kMaxOutputPixels));

      final outside = img.Image(width: 2829, height: 2829);
      expect(outside.width * outside.height, greaterThan(kMaxOutputPixels));
      final upscaler = Anime4KUpscaler(scaleFactor: 1.0);
      expect(identical(upscaler.upscale(outside), outside), isTrue);
    });
  });

  group('SuperResolutionCacheStore', () {
    late Directory tempDir;
    late Directory legacyTempDir;
    late SuperResolutionCacheStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sr_cache_test');
      legacyTempDir = await Directory.systemTemp.createTemp(
        'sr_cache_test_legacy',
      );
      PathProviderPlatform.instance = _FakePathProvider(legacyTempDir.path);
      App.cachePath = tempDir.path;
      store = SuperResolutionCacheStore();
      await store.init();
    });

    tearDown(() async {
      await store.clear();
      await tempDir.delete(recursive: true);
      await legacyTempDir.delete(recursive: true);
    });

    test('stores files under the app cache directory', () {
      final cachePath = store.getCachePath('key-a', extension: 'png')!;
      expect(
        cachePath,
        startsWith(path.join(tempDir.path, 'super_resolution_cache')),
      );
    });

    test('migrates files from the legacy temporary directory', () async {
      // Simulate an older build that stored outputs under getTemporaryDirectory().
      final legacyDir = Directory(
        path.join(legacyTempDir.path, 'super_resolution_cache'),
      );
      await legacyDir.create(recursive: true);
      final legacyFile = File(path.join(legacyDir.path, 'legacy.png'));
      await legacyFile.writeAsBytes([1, 2, 3, 4]);

      final migrated = SuperResolutionCacheStore();
      await migrated.init();

      final newPath = path.join(
        path.join(App.cachePath, 'super_resolution_cache'),
        'legacy.png',
      );
      expect(await File(newPath).exists(), isTrue);
      expect(await File(newPath).readAsBytes(), [1, 2, 3, 4]);
      expect(await legacyDir.exists(), isFalse);
      expect(await migrated.getCacheSize(), 4);
    });

    test('writes and reads files with format-accurate extensions', () async {
      await store.write(
        'key-a',
        Uint8List.fromList([1, 2, 3]),
        extension: 'png',
      );
      await store.write('key-b', Uint8List.fromList([4, 5]), extension: 'jpg');

      final pngPath = store.getCachePath('key-a', extension: 'png')!;
      final jpgPath = store.getCachePath('key-b', extension: 'jpg')!;
      expect(await File(pngPath).exists(), isTrue);
      expect(await File(jpgPath).exists(), isTrue);
      expect(pngPath, isNot(jpgPath));

      expect(await store.read('key-a', extension: 'png'), [1, 2, 3]);
      expect(await store.read('key-b', extension: 'jpg'), [4, 5]);
      expect(await store.read('key-a', extension: 'jpg'), isNull);
    });

    test('evicts the oldest files down to half the size limit', () async {
      await store.setLimitSize(2); // 2MB limit, 1MB half-limit target
      const chunk = 300 * 1024;
      const names = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final paths = <String, String>{};
      for (var i = 0; i < names.length; i++) {
        final name = names[i];
        await store.write(name, Uint8List(chunk), extension: 'png');
        final p = store.getCachePath(name, extension: 'png')!;
        paths[name] = p;
        // Pin strictly increasing mtimes (oldest = 'a') instead of relying on
        // wall-clock deltas: CI filesystems may report identical timestamps for
        // files written in quick succession, making the eviction order ambiguous.
        await File(p).setLastModified(DateTime(2020, 1, i + 1));
      }
      // 7 * 300KB = 2.1MB > 2MB limit, so eviction runs to the 1MB target.
      // Oldest-first deletion: a,b,c,d removed (1.2MB), leaving 900KB <= 1MB.
      expect(
        await File(paths['a']!).exists(),
        isFalse,
        reason: 'oldest entry must be evicted first',
      );
      for (final name in ['b', 'c', 'd']) {
        expect(
          await File(paths[name]!).exists(),
          isFalse,
          reason: '$name is older and must be evicted before newer files',
        );
      }
      for (final name in ['e', 'f', 'g']) {
        expect(
          await File(paths[name]!).exists(),
          isTrue,
          reason: '$name must survive the eviction',
        );
      }
      expect(await store.getCacheSize(), lessThanOrEqualTo(1024 * 1024));
    });

    test('clear removes all files and resets the size', () async {
      await store.write('a', Uint8List(100), extension: 'png');
      expect(await store.getCacheSize(), 100);
      await store.clear();
      expect(await store.getCacheSize(), 0);
      final aPath = store.getCachePath('a', extension: 'png')!;
      expect(await File(aPath).exists(), isFalse);
    });

    test('overwriting the same key does not double-count the size', () async {
      await store.write('a', Uint8List(100), extension: 'png');
      await store.write('a', Uint8List(200), extension: 'png');
      expect(
        await store.getCacheSize(),
        200,
        reason: 're-processing the same key must replace, not accumulate',
      );
    });

    test(
      'currentSize stays consistent with disk across a racing eviction',
      () async {
        await store.setLimitSize(1); // 1MB limit, 500KB half-limit target
        const chunk = 400 * 1024;
        // Two 400KB writes (800KB) are still under the 1MB limit, so this first
        // write does not yet trigger eviction.
        await store.write('a', Uint8List(chunk), extension: 'png');
        await store.write('b', Uint8List(chunk), extension: 'png');

        // The third write pushes total to 1.2MB > 1MB and starts an eviction pass
        // in the background. Do not await it so the following write can land
        // while the isolate may still be scanning.
        final evictFuture = store.write(
          'c',
          Uint8List(chunk),
          extension: 'png',
        );
        await store.write('d', Uint8List(100), extension: 'png');
        await evictFuture;

        // After all writes and the eviction settle, the tracked size must match
        // what is actually on disk. The overwrite bug set _currentSize from a
        // stale isolate total and would fail this equality.
        expect(store.currentSize, await store.getCacheSize());
      },
    );

    test('lowering the limit evicts entries immediately', () async {
      await store.setLimitSize(2); // 2MB limit, 1MB half-limit target
      const chunk = 400 * 1024;
      const names = ['a', 'b', 'c'];
      final paths = <String, String>{};
      for (var i = 0; i < names.length; i++) {
        final name = names[i];
        await store.write(name, Uint8List(chunk), extension: 'png');
        final p = store.getCachePath(name, extension: 'png')!;
        paths[name] = p;
        await File(p).setLastModified(DateTime(2020, 1, i + 1));
      }
      // 3 * 400KB = 1.2MB <= 2MB, so no eviction yet.
      expect(await store.getCacheSize(), 1200 * 1024);

      await store.setLimitSize(
        1,
      ); // 1MB limit, 500KB target, applied without a write

      // Oldest-first to the 500KB target: a (400KB) and b (400KB) evicted,
      // leaving c (400KB) <= 500KB.
      expect(await File(paths['a']!).exists(), isFalse);
      expect(await File(paths['b']!).exists(), isFalse);
      expect(await File(paths['c']!).exists(), isTrue);
      expect(await store.getCacheSize(), lessThanOrEqualTo(500 * 1024));
    });
  });

  group('SuperResolutionTaskScheduler', () {
    test('replays in-flight null result without casting errors', () async {
      final scheduler = SuperResolutionTaskScheduler();
      var runs = 0;

      Future<Uint8List?> task() async {
        runs++;
        return null;
      }

      final first = scheduler.schedule<Uint8List?>('key', task);
      final second = scheduler.schedule<Uint8List?>('key', task);

      expect(await first, isNull);
      expect(await second, isNull);
      expect(runs, 1, reason: 'duplicate key must reuse the in-flight task');
    });

    test('does not start a new task while at max concurrency', () async {
      final scheduler = SuperResolutionTaskScheduler(maxConcurrentTasks: 1);
      var completed = 0;

      Future<int> slowTask() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        completed++;
        return completed;
      }

      final first = scheduler.schedule<int>('a', slowTask);
      final second = scheduler.schedule<int>('b', slowTask);
      final third = scheduler.schedule<int>('c', slowTask);

      final results = await Future.wait([first, second, third]);
      expect(results, [1, 2, 3]);
    });
  });
}
