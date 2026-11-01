/// Reports how much browser storage the app is using vs the quota, and whether
/// storage is persistent. Used by the storage diagnostic to spot the case where
/// the local database has hit the browser's quota and can no longer save.
/// Non-web returns zeros / persisted=true (desktop keeps a real file).
export 'storage_estimate_unsupported.dart'
    if (dart.library.js_interop) 'storage_estimate_web.dart';

class StorageInfo {
  final int usageBytes;
  final int quotaBytes;
  final bool persisted;
  const StorageInfo(this.usageBytes, this.quotaBytes, this.persisted);
}
