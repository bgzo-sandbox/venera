import 'dart:typed_data';

/// Structured result for file-oriented super resolution APIs.
///
/// The reader path still uses nullable bytes for the hot path, but higher-level
/// workflows can use this object when they need an explicit failure reason.
class SuperResolutionResult {
  const SuperResolutionResult._({
    required this.bytes,
    required this.failureReason,
  });

  const SuperResolutionResult.success(Uint8List bytes)
    : this._(bytes: bytes, failureReason: null);

  const SuperResolutionResult.failure(String failureReason)
    : this._(bytes: null, failureReason: failureReason);

  /// Processed image bytes when the operation succeeds.
  final Uint8List? bytes;

  /// Machine-readable failure reason when the operation fails.
  final String? failureReason;

  /// Whether the result contains usable output.
  bool get isSuccess => bytes != null && failureReason == null;
}
