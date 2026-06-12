// Picks the right database executor at compile time per platform.
export 'unsupported.dart'
    if (dart.library.io) 'native.dart'
    if (dart.library.html) 'web.dart';
