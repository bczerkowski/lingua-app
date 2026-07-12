import 'dart:typed_data';

/// Non-web fallback. On native platforms, prefer share/save plugins.
void downloadText(String filename, String content,
    {String mime = 'text/csv;charset=utf-8'}) {
  throw UnsupportedError('File download is only implemented on web.');
}

void downloadBytes(String filename, Uint8List bytes,
    {String mime = 'application/octet-stream'}) {
  throw UnsupportedError('File download is only implemented on web.');
}
