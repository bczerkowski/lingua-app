import 'package:drift/drift.dart';

import 'connection/connection.dart';
import 'tables.dart';

part 'database.g.dart';

/// Aggregate counts for the study progress view.
class DeckStats {
  final int total;
  final int learned;
  final int difficult;
  final int dueToday;
  const DeckStats({
    required this.total,
    required this.learned,
    required this.difficult,
    required this.dueToday,
  });
}

@DriftDatabase(tables: [Catalogues, Cards, Meanings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  // Test constructor with an injectable executor (used by unit tests).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(cards, cards.gender);
          }
          if (from < 3) {
            await m.createTable(meanings);
          }
        },
        beforeOpen: (details) async {
          // Defensive: guarantee the `gender` column and the `meanings` table
          // exist even if a prior migration left the (web) DB inconsistent.
          final cols = await customSelect("PRAGMA table_info('cards')").get();
          final hasGender = cols.any((r) => r.read<String>('name') == 'gender');
          if (!hasGender) {
            await customStatement('ALTER TABLE cards ADD COLUMN gender TEXT');
          }
          final tbls = await customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='meanings'")
              .get();
          if (tbls.isEmpty) {
            await createMigrator().createTable(meanings);
          }
        },
      );

  // ---------------------------------------------------------------------------
  // Catalogues
  // ---------------------------------------------------------------------------
  Stream<List<Catalogue>> watchCatalogues() => select(catalogues).watch();

  Future<int> createCatalogue(String name, {String? color}) => into(catalogues)
      .insert(CataloguesCompanion.insert(name: name, color: Value(color)));

  Future<void> renameCatalogue(int id, String name) =>
      (update(catalogues)..where((t) => t.id.equals(id)))
          .write(CataloguesCompanion(name: Value(name.trim())));

  /// Delete a catalogue; any cards pointing at it become uncategorized.
  Future<void> deleteCatalogue(int id) async {
    await transaction(() async {
      await (update(cards)..where((t) => t.catalogueId.equals(id)))
          .write(const CardsCompanion(catalogueId: Value(null)));
      await (delete(catalogues)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Remove every catalogue and uncategorize all cards.
  Future<void> deleteAllCatalogues() async {
    await transaction(() async {
      await update(cards).write(const CardsCompanion(catalogueId: Value(null)));
      await delete(catalogues).go();
    });
  }

  /// How many cards are filed under each catalogue (for the manage screen).
  Stream<Map<int, int>> watchCatalogueCounts() {
    final count = cards.id.count();
    final q = selectOnly(cards)
      ..addColumns([cards.catalogueId, count])
      ..where(cards.catalogueId.isNotNull())
      ..groupBy([cards.catalogueId]);
    return q.map((r) => MapEntry(r.read(cards.catalogueId)!, r.read(count) ?? 0))
        .watch()
        .map((rows) => {for (final e in rows) e.key: e.value});
  }

  // ---------------------------------------------------------------------------
  // Dictionary
  // ---------------------------------------------------------------------------

  /// Lightning-fast bidirectional lookup. (For 10k+ rows, swap to FTS5.)
  Stream<List<Flashcard>> searchEntries(String query) {
    final q = query.trim();
    final sel = select(cards)
      ..orderBy([(t) => OrderingTerm(expression: t.english)])
      ..limit(80);
    if (q.isNotEmpty) {
      final like = '%$q%';
      sel.where((t) => t.polish.like(like) | t.english.like(like));
    }
    return sel.watch();
  }

  // ---------------------------------------------------------------------------
  // Study queue
  // ---------------------------------------------------------------------------

  /// Due, active study cards ordered by due date (nulls = brand new, first).
  Future<List<Flashcard>> dueCards(DateTime now, {int? catalogueId, int limit = 200}) {
    final q = select(cards)
      ..where((t) =>
          t.isCard.equals(true) &
          t.suspended.equals(false) &
          (t.dueDate.isSmallerOrEqualValue(now) | t.dueDate.isNull()))
      ..orderBy([
        (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.asc),
      ])
      ..limit(limit);
    if (catalogueId != null) q.where((t) => t.catalogueId.equals(catalogueId));
    return q.get();
  }

  /// Live count of cards currently due for study.
  Stream<int> watchDueCount() {
    final now = DateTime.now();
    final c = countAll();
    final q = selectOnly(cards)
      ..addColumns([c])
      ..where(cards.isCard.equals(true) &
          cards.suspended.equals(false) &
          (cards.dueDate.isSmallerOrEqualValue(now) | cards.dueDate.isNull()));
    return q.map((r) => r.read(c) ?? 0).watchSingle();
  }

  Future<int> countCards() async {
    final c = countAll();
    final row = await (selectOnly(cards)
          ..where(cards.isCard.equals(true))
          ..addColumns([c]))
        .getSingle();
    return row.read(c) ?? 0;
  }

  Future<int> _count(Expression<bool> filter) async {
    final c = countAll();
    final row =
        await (selectOnly(cards)..addColumns([c])..where(filter)).getSingle();
    return row.read(c) ?? 0;
  }

  /// Aggregate study stats for the progress view.
  Future<DeckStats> deckStats() async {
    final now = DateTime.now();
    final base = cards.isCard.equals(true);
    final total = await _count(base);
    final learned = await _count(base & cards.repetitions.isBiggerThanValue(0));
    final difficult = await _count(base & cards.lapses.isBiggerThanValue(0));
    final dueToday = await _count(base &
        cards.suspended.equals(false) &
        (cards.dueDate.isSmallerOrEqualValue(now) | cards.dueDate.isNull()));
    return DeckStats(
        total: total,
        learned: learned,
        difficult: difficult,
        dueToday: dueToday);
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  Future<void> promoteToCard(int id) =>
      (update(cards)..where((t) => t.id.equals(id))).write(
        CardsCompanion(isCard: const Value(true), dueDate: Value(DateTime.now())),
      );

  Future<void> recategorize(int id, int? catalogueId) =>
      (update(cards)..where((t) => t.id.equals(id)))
          .write(CardsCompanion(catalogueId: Value(catalogueId)));

  Future<void> setImage(int id, Uint8List? bytes, String? source) =>
      (update(cards)..where((t) => t.id.equals(id))).write(
        CardsCompanion(imageBytes: Value(bytes), imageSource: Value(source)),
      );

  Future<void> deleteCard(int id) =>
      (delete(cards)..where((t) => t.id.equals(id))).go();

  /// Delete every card (keeps catalogues, so the deck is not auto-reseeded).
  Future<int> clearAllCards() => delete(cards).go();

  /// Wipe everything (cards + catalogues) — used by "Reset to sample deck".
  Future<void> wipeAll() async {
    await transaction(() async {
      await delete(cards).go();
      await delete(catalogues).go();
    });
  }

  /// Fetch full rows for the given ids (used to snapshot before a bulk delete).
  Future<List<Flashcard>> getCards(List<int> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(cards)..where((t) => t.id.isIn(ids))).get();
  }

  /// Bulk delete by id (used by the dictionary's multi-select mode).
  Future<int> deleteCards(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return (delete(cards)..where((t) => t.id.isIn(ids))).go();
  }

  /// Re-insert previously deleted rows (with their original ids) for undo.
  Future<void> restoreCards(List<Flashcard> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      for (final r in rows) {
        b.insert(cards, r.toCompanion(false), mode: InsertMode.insertOrReplace);
      }
    });
  }

  Future<Flashcard?> getCard(int id) =>
      (select(cards)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ---------------------------------------------------------------------------
  // Meanings (additional, beyond the primary meaning stored on the card)
  // ---------------------------------------------------------------------------
  Future<List<Meaning>> meaningsFor(int cardId) =>
      (select(meanings)
            ..where((m) => m.cardId.equals(cardId))
            ..orderBy([(m) => OrderingTerm(expression: m.sortOrder)]))
          .get();

  /// Replace all additional meanings for a card with [items] (each is a
  /// {polish, definition, example} record). Empty entries are skipped.
  Future<void> replaceMeanings(
      int cardId, List<({String polish, String? definition, String? example})> items) async {
    await transaction(() async {
      await (delete(meanings)..where((m) => m.cardId.equals(cardId))).go();
      var order = 0;
      for (final it in items) {
        if (it.polish.trim().isEmpty &&
            (it.definition?.trim().isEmpty ?? true) &&
            (it.example?.trim().isEmpty ?? true)) {
          continue;
        }
        await into(meanings).insert(MeaningsCompanion.insert(
          cardId: cardId,
          polishTranslation: Value(it.polish.trim()),
          englishDefinition: Value(it.definition?.trim()),
          exampleSentence: Value(it.example?.trim()),
          sortOrder: Value(order++),
        ));
      }
    });
  }
}
