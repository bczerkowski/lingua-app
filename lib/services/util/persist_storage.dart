// Asks the browser to make this origin's storage persistent, so the local
// database (IndexedDB/OPFS) is not silently evicted under storage pressure.
// Picks a platform implementation at compile time; non-web is a no-op.
export 'persist_storage_unsupported.dart'
    if (dart.library.js_interop) 'persist_storage_web.dart';
