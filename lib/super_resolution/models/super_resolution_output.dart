import 'dart:typed_data';

/// Processed output produced by a [SuperResolutionProcessor].
///
/// Bundles the encoded image bytes with the file extension that matches the
/// actual encoding, so the cache layer can store and serve the result under a
/// format-accurate filename instead of assuming PNG everywhere.
class SuperResolutionOutput {
  const SuperResolutionOutput({
    required this.bytes,
    required this.fileExtension,
  });

  /// Encoded image bytes ready to be written to disk.
  final Uint8List bytes;

  /// File extension matching the encoding of [bytes], e.g. `png` or `jpg`.
  final String fileExtension;
}
