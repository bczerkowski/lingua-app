import 'package:flutter/material.dart';

import 'app_services.dart';
import 'data/db/database.dart';
import 'data/seed.dart';
import 'features/home/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  // Seed in the background so a slow/failed DB open never blocks first paint.
  final seeded = Seeder(db).seedIfNeeded();

  runApp(LinguaApp(services: AppServices(db: db), seeded: seeded));
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
