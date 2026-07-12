import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Downloads [content] as a file named [filename] in the browser.
void downloadText(String filename, String content,
    {String mime = 'text/csv;charset=utf-8'}) {
  final blob =
      web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mime));
  _saveBlob(blob, filename);
}

/// Downloads raw [bytes] (e.g. a PNG) as a file named [filename].
void downloadBytes(String filename, Uint8List bytes,
    {String mime = 'application/octet-stream'}) {
  final blob =
      web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  _saveBlob(blob, filename);
}

void _saveBlob(web.Blob blob, String filename) {
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
