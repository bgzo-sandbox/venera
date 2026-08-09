import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:venera/foundation/log.dart';
import 'package:venera/super_resolution/models/super_resolution_output.dart';
import 'package:venera/super_resolution/super_resolution_processor.dart';
import 'package:venera/super_resolution/models/super_resolution_request.dart';

import 'anime4k_upscaler.dart';

/// Adapter that exposes Anime4K through the generic processor interface.
///
/// The module facade talks to this class instead of directly instantiating the
/// low-level upscaler. That keeps algorithm-specific decode/encode and isolate
/// dispatch details contained inside the implementation folder.
class Anime4KProcessor implements SuperResolutionProcessor {
  const Anime4KProcessor();

  @override
  /// Decodes, processes and re-encodes the image in a background isolate.
  Future<SuperResolutionOutput?> process(SuperResolutionRequest request) async {
    try {
      return await compute(
        _processAnime4KRequest,
        _Anime4KProcessorInput(
          imageBytes: request.imageBytes,
          scaleFactor: request.scaleFactor,
          pushStrength: request.pushStrength,
          pushGradStrength: request.pushGradStrength,
        ),
      );
    } catch (e) {
      Log.error('Anime4K', 'processing error: $e');
      return null;
    }
  }
}

/// Serializable payload passed into the background isolate.
///
/// Keep this object limited to isolate-safe primitives and byte buffers.
class _Anime4KProcessorInput {
  const _Anime4KProcessorInput({
    required this.imageBytes,
    required this.scaleFactor,
    required this.pushStrength,
    required this.pushGradStrength,
  });

  final Uint8List imageBytes;
  final double scaleFactor;
  final double pushStrength;
  final double pushGradStrength;
}

/// Isolate entry point for Anime4K processing.
///
/// It stays top-level so Flutter's [compute] can invoke it safely.
SuperResolutionOutput? _processAnime4KRequest(_Anime4KProcessorInput input) {
  try {
    final sourceImage = img.decodeImage(input.imageBytes);
    if (sourceImage == null) {
      return null;
    }

    // Refuse to process sources that already exceed the output pixel cap:
    // the upscaler cannot downscale, so the result would stay oversized.
    if (sourceImage.width * sourceImage.height > kMaxOutputPixels) {
      Log.error(
        'Anime4K',
        'source image too large: ${sourceImage.width}x${sourceImage.height} > $kMaxOutputPixels pixels',
      );
      return null;
    }

    final upscaler = Anime4KUpscaler(
      pushStrength: input.pushStrength,
      pushGradStrength: input.pushGradStrength,
      scaleFactor: input.scaleFactor,
    );
    final result = upscaler.upscale(sourceImage);
    if (_isPng(input.imageBytes)) {
      return SuperResolutionOutput(
        bytes: Uint8List.fromList(img.encodePng(result)),
        fileExtension: 'png',
      );
    }
    return SuperResolutionOutput(
      bytes: Uint8List.fromList(img.encodeJpg(result, quality: 90)),
      fileExtension: 'jpg',
    );
  } catch (e) {
    Log.error('Anime4K', 'processing error: $e');
    return null;
  }
}

/// Detects PNG input by its magic bytes (0x89 0x50 0x4E 0x47).
///
/// PNG keeps alpha and is lossless; everything else (JPEG, WebP, ...) is
/// re-encoded as JPEG to avoid bloating the cache with lossless re-encodes of
/// lossy sources.
bool _isPng(Uint8List bytes) {
  if (bytes.length < 4) {
    return false;
  }
  return bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47;
}
