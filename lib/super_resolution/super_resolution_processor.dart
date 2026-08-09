import 'package:venera/super_resolution/models/super_resolution_output.dart';
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
  /// The returned [SuperResolutionOutput] carries the actual encoding so the
  /// cache layer can store the result with a format-accurate extension.
  Future<SuperResolutionOutput?> process(SuperResolutionRequest request);
}
