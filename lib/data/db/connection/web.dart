import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Web: SQLite compiled to WebAssembly, persisted in the browser (IndexedDB/OPFS).
/// Requires `web/sqlite3.wasm` and `web/drift_worker.js` to be present.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'lingua',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
