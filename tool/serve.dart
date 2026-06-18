// Minimal static file server for build/web (no external dependencies).
// Used to preview the release web build reliably.
import 'dart:io';

const _types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 8099;
  final root = Directory('build/web').absolute;
  final server = await HttpServer.bind('127.0.0.1', port);
  stdout.writeln('Serving ${root.path} at http://127.0.0.1:$port');

  await for (final req in server) {
    try {
      var p = req.uri.path;
      if (p == '/' || p.isEmpty) p = '/index.html';
      var file = File('${root.path}$p');
      if (!await file.exists()) {
        // SPA fallback so client-side routes resolve.
        file = File('${root.path}/index.html');
      }
      final ext = p.contains('.') ? p.substring(p.lastIndexOf('.')) : '';
      req.response.headers
          .set('Content-Type', _types[ext] ?? 'application/octet-stream');
      await req.response.addStream(file.openRead());
    } catch (_) {
      req.response.statusCode = HttpStatus.internalServerError;
    }
    await req.response.close();
  }
}
