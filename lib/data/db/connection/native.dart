import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native (Android / iOS / Windows / macOS / Linux): file-backed SQLite.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lingua.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
