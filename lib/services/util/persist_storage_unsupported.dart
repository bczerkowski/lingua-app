/// Non-web platforms keep their SQLite file on disk already — nothing to do.
Future<bool> requestPersistentStorage() async => true;
