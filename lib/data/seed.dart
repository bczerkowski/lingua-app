import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'db/database.dart';

/// Seeds the database from `assets/sample_deck.json` on first run, and enriches
/// already-seeded rows when the sample data gains new fields (e.g. gender).
class Seeder {
  final AppDatabase db;
  Seeder(this.db);

  Future<List<Map<String, dynamic>>> _loadCards() async {
    final raw = await rootBundle.loadString('assets/sample_deck.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (data['cards'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> seedIfEmpty() async {
    final existing = await db.select(db.cards).get();
    if (existing.isNotEmpty) {
      await _backfill();
      return;
    }

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
            gender: Value(c['gender'] as String?),
            catalogueId: Value(catIds[c['catalogue']]),
            isCard: Value(isCard),
            dueDate: Value(isCard ? now : null),
          ),
        );
      }
    });
  }

  /// Non-destructive: updates existing sample rows (matched by Polish term) with
  /// the newer gender + tag data so the upgraded UI has something to show.
  /// Best-effort — never let a backfill problem block app launch.
  Future<void> _backfill() async {
    try {
      final cards = await _loadCards();
      for (final c in cards) {
        final polish = c['polish'] as String;
        await (db.update(db.cards)..where((t) => t.polish.equals(polish)))
            .write(
          CardsCompanion(
            gender: Value(c['gender'] as String?),
            tags: Value((c['tags'] as String?) ?? ''),
            exampleSentence: Value(c['example'] as String?),
          ),
        );
      }
    } catch (_) {
      // Ignore: the app works fine without the enrichment.
    }
  }
}
