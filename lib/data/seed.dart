import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'db/database.dart';

/// Seeds the sample deck on the very first run only.
class Seeder {
  final AppDatabase db;
  Seeder(this.db);

  /// Seeds once, then never again. We use the presence of catalogues — which
  /// persist even after every card is deleted — as the "already initialized"
  /// marker, so the user's deletions are never undone by a re-seed.
  Future<void> seedIfNeeded() async {
    final cats = await db.select(db.catalogues).get();
    if (cats.isNotEmpty) return;

    final raw = await rootBundle.loadString('assets/sample_deck.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;

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
            dueDate: Value(isCard ? now : null),
          ),
        );
      }
    });
  }
}
