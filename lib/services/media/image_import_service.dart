import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:printing/printing.dart';

/// Result of an image-import attempt.
class ImageImportResult {
  final Uint8List? bytes;
  final String? error; // null on success or on user-cancel
  final bool cancelled;
  const ImageImportResult.success(this.bytes)
      : error = null,
        cancelled = false;
  const ImageImportResult.cancelled()
      : bytes = null,
        error = null,
        cancelled = true;
  const ImageImportResult.failure(this.error)
      : bytes = null,
        cancelled = false;
  bool get ok => bytes != null;
}

/// Imports the visual-anchor image from a file (PNG/JPG/PDF) or the clipboard
/// (e.g. a Print-Screen screenshot). PDFs are rasterized to a PNG.
class ImageImportService {
  /// Open a picker accepting PNG / JPG / PDF. PDFs are rendered to an image.
  Future<ImageImportResult> pickFromFile() async {
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
        withData: true, // ensure bytes are available on every platform
      );
    } catch (e) {
      return ImageImportResult.failure('Could not open file picker: $e');
    }
    if (picked == null || picked.files.isEmpty) {
      return const ImageImportResult.cancelled();
    }

    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return const ImageImportResult.failure('Could not read the selected file');
    }

    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'pdf') {
      return _rasterizePdf(bytes);
    }
    return ImageImportResult.success(bytes);
  }

  /// Paste an image directly from the clipboard (screenshot / copied image).
  Future<ImageImportResult> pasteFromClipboard() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null) {
        return const ImageImportResult.failure(
            'No image found on the clipboard. Copy or take a screenshot first.');
      }
      return ImageImportResult.success(bytes);
    } catch (e) {
      return ImageImportResult.failure('Clipboard read failed: $e');
    }
  }

  /// Render the first page of a PDF to a PNG.
  Future<ImageImportResult> _rasterizePdf(Uint8List pdfBytes) async {
    try {
      await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 150)) {
        final png = await page.toPng();
        return ImageImportResult.success(png);
      }
      return const ImageImportResult.failure('The PDF has no pages to import');
    } catch (e) {
      return ImageImportResult.failure('Could not read the PDF: $e');
    }
  }
}
