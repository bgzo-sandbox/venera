import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/cache_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cache_manager_test');
    App.cachePath = tempDir.path;
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test(
    'clearRootCacheFiles deletes stray files but keeps subdirectories',
    () async {
      final subDir = Directory('${tempDir.path}/cache');
      await subDir.create(recursive: true);
      final nested = File('${tempDir.path}/sub/keep.png');
      await nested.create(recursive: true);
      final stray = File('${tempDir.path}/stray.png');
      await stray.writeAsBytes([1, 2, 3]);

      await CacheManager.clearRootCacheFiles();

      expect(
        await stray.exists(),
        isFalse,
        reason: 'stray root-level file must be removed',
      );
      expect(
        await subDir.exists(),
        isTrue,
        reason: 'subdirectories (managed caches) must survive',
      );
      expect(await nested.exists(), isTrue);
    },
  );
}
