import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'db/database.dart';

/// Seeds the database from `assets/sample_deck.json` the first time the app runs.
class Seeder {
  final AppDatabase db;
  Seeder(this.db);

  Future<void> seedIfEmpty() async {
    final existing = await db.select(db.cards).get();
    if (existing.isNotEmpty) return;

    final raw = await rootBundle.loadString('assets/sample_deck.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;

    // Catalogues first, keep a name -> id map.
    final catNames = (data['catalogues'] as List).cast<String>();
    final catIds = <String, int>{};
    for (final name in catNames) {
      catIds[name] = await db.createCatalogue(name);
    }

    final now = DateTime.now();
    await db.batch((b) {
      for (final c in (data['cards'] as List).cast<Map<String, dynamic>>()) {
        final isCard = (c['isCard'] as bool?) ?? true;
        b.insert(
          db.cards,
          CardsCompanion.insert(
            polish: c['polish'] as String,
            english: c['english'] as String,
            exampleSentence: Value(c['example'] as String?),
            englishDefinition: Value(c['definition'] as String?),
            tags: Value((c['tags'] as String?) ?? ''),
            catalogueId: Value(catIds[c['catalogue']]),
            isCard: Value(isCard),
            // Stagger due dates slightly so the study queue has a natural order.
            dueDate: Value(isCard ? now : null),
          ),
        );
      }
    });
  }
}
