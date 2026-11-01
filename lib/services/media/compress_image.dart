import 'dart:typed_data';

/// Downscale + re-encode an image to a small JPEG so the local database stays
/// small (full-size images bloated it to ~1.6 GB and broke saving). Picks a
/// platform implementation at compile time; non-web returns the input as-is.
export 'compress_image_unsupported.dart'
    if (dart.library.js_interop) 'compress_image_web.dart';

/// Shared signature for callers:
/// `compressImage(bytes, {maxDim = 512, quality = 0.6})` returns small JPEG
/// bytes (or the input unchanged on non-web / failure).
typedef CompressImage = Future<Uint8List> Function(Uint8List input,
    {int maxDim, double quality});
