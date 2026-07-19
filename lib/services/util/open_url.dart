// Opens a URL in a new browser tab. Picks a platform implementation at
// compile time (web uses window.open; other platforms are a no-op).
export 'open_url_unsupported.dart'
    if (dart.library.js_interop) 'open_url_web.dart';
