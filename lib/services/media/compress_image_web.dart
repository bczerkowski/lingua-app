import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downscale [input] so its longest side is <= [maxDim] and re-encode it as a
/// JPEG at [quality]. Uses the browser's own decoder/encoder (createImageBitmap
/// + OffscreenCanvas), which keeps memory low and produces small files. Falls
/// back to the original bytes on any failure.
Future<Uint8List> compressImage(Uint8List input,
    {int maxDim = 512, double quality = 0.6}) async {
  try {
    final blob = web.Blob([input.toJS].toJS);
    final bitmap = await web.window.createImageBitmap(blob).toDart;
    final w = bitmap.width;
    final h = bitmap.height;
    final longest = w > h ? w : h;
    final scale = longest > maxDim ? maxDim / longest : 1.0;
    final tw = (w * scale).round().clamp(1, maxDim);
    final th = (h * scale).round().clamp(1, maxDim);

    final canvas = web.OffscreenCanvas(tw, th);
    final ctx =
        canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
    if (ctx == null) {
      bitmap.close();
      return input;
    }
    ctx.drawImage(bitmap, 0, 0, tw.toDouble(), th.toDouble());
    bitmap.close();

    final outBlob = await canvas
        .convertToBlob(web.ImageEncodeOptions(
            type: 'image/jpeg', quality: quality))
        .toDart;
    final buf = await outBlob.arrayBuffer().toDart;
    final bytes = buf.toDart.asUint8List();
    // If compression somehow grew the file, keep the smaller original.
    return bytes.lengthInBytes < input.lengthInBytes ? bytes : input;
  } catch (_) {
    return input;
  }
}
