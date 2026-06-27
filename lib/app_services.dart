import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'data/db/database.dart';
import 'services/ai/image_gen_service.dart';
import 'services/srs/srs_scheduler.dart';
import 'services/sync/sync_service.dart';
import 'services/tts/tts_service.dart';

/// Backend endpoint for AI image generation. Empty = demo mode (manual image
/// only). Set it at build/run time without touching code, e.g.:
///   flutter run --dart-define=IMAGE_BACKEND=https://api.yourapp.com/image
const String kImageBackendEndpoint =
    String.fromEnvironment('IMAGE_BACKEND', defaultValue: '');

/// Minimal composition root, exposed to the widget tree via [InheritedWidget].
class AppServices {
  final AppDatabase db;
  final SrsScheduler srs;
  final TtsService tts;
  final ImageGenProvider imageGen;
  final SyncService sync;

  AppServices({
    required this.db,
    required this.sync,
    SrsScheduler? srs,
    TtsService? tts,
    ImageGenProvider? imageGen,
  })  : srs = srs ?? SrsScheduler(),
        tts = tts ?? TtsService(),
        imageGen = imageGen ?? _defaultImageGen();

  /// Uses the real backend when [kImageBackendEndpoint] is configured,
  /// otherwise the demo provider that always fails into the manual flow.
  static ImageGenProvider _defaultImageGen() {
    if (kImageBackendEndpoint.isEmpty) return DisabledImageGenProvider();
    return ProxyImageGenProvider(Dio(), endpoint: kImageBackendEndpoint);
  }

  static AppServices of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<_ServicesScope>();
    assert(w != null, 'AppServices not found in widget tree');
    return w!.services;
  }
}

class ServicesScope extends InheritedWidget {
  final AppServices services;
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  @override
  bool updateShouldNotify(covariant ServicesScope oldWidget) =>
      oldWidget.services != services;
}

// Private alias so AppServices.of can find the concrete type.
typedef _ServicesScope = ServicesScope;
