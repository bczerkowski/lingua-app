import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Ask the browser to keep this origin's storage (IndexedDB/OPFS, where the
/// deck lives) durable so it isn't evicted between sessions. Returns whether
/// storage is persistent afterwards. Best-effort: any failure returns false
/// instead of throwing.
Future<bool> requestPersistentStorage() async {
  try {
    final storage = web.window.navigator.storage;
    // Already granted on a previous visit?
    final already = (await storage.persisted().toDart).toDart;
    if (already) return true;
    return (await storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}
