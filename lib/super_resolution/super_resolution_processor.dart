import 'dart:typed_data';

import 'package:venera/super_resolution/models/super_resolution_request.dart';

/// Algorithm-specific processing contract used by the module facade.
///
/// Implementations should only care about converting a typed request into a
/// processed image result. Cache policy, request dedupe and algorithm selection
/// stay outside this interface in [SuperResolutionService].
abstract class SuperResolutionProcessor {
  /// Runs a single super resolution request.
  ///
  /// Returning `null` means the algorithm did not produce usable output.
  Future<Uint8List?> process(SuperResolutionRequest request);
}
