import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'db/database.dart';

/// First-run setup: a one-time cleanup of the old auto-created default
/// categories, plus seeding the sample deck exactly once.
class Seeder {
  final AppDatabase db;
  Seeder(this.db);

  static const _kClearedDefaultCats = 'clearedDefaultCategories_v1';
  static const _kSeededCards = 'seededSampleCards_v1';

  Future<void> seedIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    // One-time: remove the old default categories (and their duplicates) so the
    // user starts with a clean slate and only their own categories.
    if (!(prefs.getBool(_kClearedDefaultCats) ?? false)) {
      await db.deleteAllCatalogues();
      await prefs.setBool(_kClearedDefaultCats, true);
    }

    // Seed the sample cards exactly once (uncategorized).
    if (prefs.getBool(_kSeededCards) ?? false) return;
    final existing = await db.select(db.cards).get();
    if (existing.isEmpty) {
      await _insertSampleCards();
    }
    await prefs.setBool(_kSeededCards, true);
  }

  /// Wipes all data and re-seeds the sample deck (for the in-app reset).
  Future<void> reset() async {
    await db.wipeAll();
    await _insertSampleCards();
  }

  Future<void> _insertSampleCards() async {
    final raw = await rootBundle.loadString('assets/sample_deck.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
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
            isCard: Value(isCard),
            dueDate: Value(isCard ? now : null),
          ),
        );
      }
    });
  }
}
