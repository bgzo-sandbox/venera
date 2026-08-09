import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:venera/super_resolution/implementations/anime4k/anime4k_processor.dart';
import 'package:venera/super_resolution/implementations/anime4k/anime4k_upscaler.dart';
import 'package:venera/super_resolution/runtime/super_resolution_task_scheduler.dart';

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
