import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'storage_estimate.dart';

/// Reads navigator.storage.estimate() (usage/quota) and persisted().
Future<StorageInfo> storageEstimate() async {
  try {
    final storage = web.window.navigator.storage;
    final est = await storage.estimate().toDart;
    final persisted = (await storage.persisted().toDart).toDart;
    return StorageInfo(est.usage, est.quota, persisted);
  } catch (_) {
    return const StorageInfo(0, 0, false);
  }
}
