import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_services.dart';
import 'data/db/database.dart';
import 'data/seed.dart';
import 'features/home/home_screen.dart';
import 'services/sync/supabase_config.dart';
import 'services/sync/sync_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Friendly fallback instead of a red/blank screen if a widget ever throws.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: const Color(0xFFF0EEE6),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.refresh, size: 40, color: Color(0xFF73706A)),
            const SizedBox(height: 12),
            Text(
              'Something went wrong on this screen.\nPlease reload the app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, color: Colors.black.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  };

  final db = AppDatabase();
  // Seed in the background so a slow/failed DB open never blocks first paint.
  final seeded = Seeder(db).seedIfNeeded();

  final sync = SyncService(db);

  // Draw the app immediately. Cloud sync is brought up in the BACKGROUND so a
  // slow/hanging Supabase init can never block first paint (which left a blank
  // screen). The app is fully usable offline; sync activates once it connects.
  runApp(LinguaApp(services: AppServices(db: db, sync: sync), seeded: seeded));

  if (SupabaseConfig.isConfigured) {
    Future(() async {
      try {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          // ignore: deprecated_member_use
          anonKey: SupabaseConfig.anonKey,
        );
        sync.init();
      } catch (_) {/* offline / misconfigured -> stay local-only */}
    });
  }
}

class LinguaApp extends StatelessWidget {
  final AppServices services;
  final Future<void> seeded;
  const LinguaApp({super.key, required this.services, required this.seeded});

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: services,
      child: MaterialApp(
        title: 'Lingua — PL/EN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // Scale all text up ~30% for easier reading (on top of any system setting).
        builder: (context, child) {
          final factor = MediaQuery.textScalerOf(context).scale(1) * 1.3;
          return MediaQuery.withClampedTextScaling(
            minScaleFactor: factor,
            maxScaleFactor: factor,
            child: child!,
          );
        },
        // Gate the UI on the seed future so screens query a populated DB,
        // while still showing a spinner instead of a blank screen.
        home: FutureBuilder<void>(
          future: seeded,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Database error: ${snap.error}'),
                  ),
                ),
              );
            }
            return const HomeScreen();
          },
        ),
      ),
    );
  }
}
