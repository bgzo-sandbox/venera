import 'dart:typed_data';

import 'super_resolution_algorithm.dart';

/// Immutable request object for one super resolution operation.
///
/// The request intentionally bundles algorithm choice and tuning parameters so
/// callers do not need a growing list of positional arguments as the module
/// expands.
class SuperResolutionRequest {
  const SuperResolutionRequest({
    required this.cacheKey,
    required this.imageBytes,
    this.algorithm = SuperResolutionAlgorithm.anime4k,
    this.scaleFactor = 2.0,
    this.pushStrength = 0.31,
    this.pushGradStrength = 1.0,
  });

  /// Stable logical identity of the source image from the caller's perspective.
  final String cacheKey;

  /// Original image bytes to process.
  final Uint8List imageBytes;

  /// Selected processing algorithm.
  final SuperResolutionAlgorithm algorithm;

  /// Requested output scaling factor.
  final double scaleFactor;

  /// Anime4K-specific line sharpening strength.
  final double pushStrength;

  /// Anime4K-specific gradient refinement strength.
  final double pushGradStrength;

  /// Full cache key including algorithm and tuning knobs.
  ///
  /// This prevents different parameter combinations from accidentally sharing
  /// the same cached output.
  String get effectiveCacheKey =>
      '${algorithm.name}|$cacheKey|$scaleFactor|$pushStrength|$pushGradStrength';
}
