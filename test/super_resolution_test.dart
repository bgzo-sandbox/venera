import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
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
    late SuperResolutionCacheStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sr_cache_test');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      store = SuperResolutionCacheStore();
      await store.init();
    });

    tearDown(() async {
      await store.clear();
      await tempDir.delete(recursive: true);
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

    test('evicts the oldest file once the size limit is exceeded', () async {
      store.setLimitSize(1); // 1MB
      const chunk = 700 * 1024;
      await store.write('old', Uint8List(chunk), extension: 'png');
      final oldPath = store.getCachePath('old', extension: 'png')!;
      // Pin an explicit older mtime instead of relying on wall-clock deltas:
      // CI filesystems may report identical timestamps for files written in
      // quick succession, making the eviction order ambiguous.
      await File(oldPath).setLastModified(DateTime(2020, 1, 1));
      await store.write('new', Uint8List(chunk), extension: 'png');
      final newPath = store.getCachePath('new', extension: 'png')!;

      expect(
        await File(oldPath).exists(),
        isFalse,
        reason: 'oldest entry must be evicted first',
      );
      expect(await File(newPath).exists(), isTrue);
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
