// Triggers a file download. Picks a platform implementation at compile time.
export 'download_unsupported.dart'
    if (dart.library.js_interop) 'download_web.dart';
