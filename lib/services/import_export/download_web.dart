import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Downloads [content] as a file named [filename] in the browser.
void downloadText(String filename, String content,
    {String mime = 'text/csv;charset=utf-8'}) {
  final blob =
      web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
