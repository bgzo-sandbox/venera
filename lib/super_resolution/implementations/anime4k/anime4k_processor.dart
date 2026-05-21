import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:venera/foundation/log.dart';
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
  Future<Uint8List?> process(SuperResolutionRequest request) async {
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
Uint8List? _processAnime4KRequest(_Anime4KProcessorInput input) {
  try {
    final sourceImage = img.decodeImage(input.imageBytes);
    if (sourceImage == null) {
      return null;
    }

    final upscaler = Anime4KUpscaler(
      pushStrength: input.pushStrength,
      pushGradStrength: input.pushGradStrength,
      scaleFactor: input.scaleFactor,
    );
    final result = upscaler.upscale(sourceImage);
    return Uint8List.fromList(img.encodePng(result));
  } catch (_) {
    return null;
  }
}
