import 'package:flutter/material.dart';

import 'app_services.dart';
import 'data/db/database.dart';
import 'data/seed.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  // Seed in the background so a slow/failed DB open never blocks first paint.
  final seeded = Seeder(db).seedIfEmpty();

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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D5AFE)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        ),
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
