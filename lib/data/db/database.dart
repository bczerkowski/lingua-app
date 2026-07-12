import 'dart:convert';

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
  int get schemaVersion => 5;

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
          if (from < 4) {
            await m.addColumn(cards, cards.note);
          }
          if (from < 5) {
            await m.addColumn(cards, cards.imageUrl);
          }
        },
        beforeOpen: (details) async {
          // Defensive: guarantee newer columns / tables exist even if a prior
          // migration left the (web) DB inconsistent.
          final cols = await customSelect("PRAGMA table_info('cards')").get();
          final names = cols.map((r) => r.read<String>('name')).toSet();
          if (!names.contains('gender')) {
            await customStatement('ALTER TABLE cards ADD COLUMN gender TEXT');
          }
          if (!names.contains('note')) {
            await customStatement('ALTER TABLE cards ADD COLUMN note TEXT');
          }
          if (!names.contains('image_url')) {
            await customStatement('ALTER TABLE cards ADD COLUMN image_url TEXT');
          }
          // Ensure the meanings table exists AND has the expected columns;
          // recreate it if missing or malformed (e.g. a half-applied migration).
          final mcols = await customSelect("PRAGMA table_info('meanings')").get();
          final mnames =
              mcols.map((r) => r.read<String>('name')).toSet();
          const needed = {
            'id',
            'card_id',
            'polish_translation',
            'english_definition',
            'example_sentence',
            'sort_order'
          };
          if (!needed.every(mnames.contains)) {
            await customStatement('DROP TABLE IF EXISTS meanings');
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
  ///
  /// [catalogueId] filters to one category at the DB level so the result is
  /// correct regardless of how the deck is sorted. The limit is a high safety
  /// ceiling — small enough to stay snappy, large enough that a personal deck
  /// is never silently truncated (the old limit of 80 hid newer entries).
  Stream<List<Flashcard>> searchEntries(String query, {int? catalogueId}) {
    final q = query.trim();
    final sel = select(cards)
      ..orderBy([(t) => OrderingTerm(expression: t.english)])
      ..limit(5000);
    if (q.isNotEmpty) {
      final like = '%$q%';
      sel.where((t) => t.polish.like(like) | t.english.like(like));
    }
    if (catalogueId != null) {
      sel.where((t) => t.catalogueId.equals(catalogueId));
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

  /// Cards with a local image but no cloud URL yet — the ones to upload.
  Future<List<Flashcard>> cardsNeedingImageUpload() => (select(cards)
        ..where((t) => t.imageBytes.isNotNull() & t.imageUrl.isNull()))
      .get();

  /// Records the Storage URL for a card after its image is uploaded.
  Future<void> setImageUrl(int id, String url) =>
      (update(cards)..where((t) => t.id.equals(id)))
          .write(CardsCompanion(imageUrl: Value(url)));

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

  /// Meanings for many cards at once, grouped by cardId (used to preload the
  /// study queue so the card view never depends on a per-build async query).
  Future<Map<int, List<Meaning>>> meaningsForCards(List<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (select(meanings)
          ..where((m) => m.cardId.isIn(ids))
          ..orderBy([(m) => OrderingTerm(expression: m.sortOrder)]))
        .get();
    final map = <int, List<Meaning>>{};
    for (final m in rows) {
      (map[m.cardId] ??= []).add(m);
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Backup: export / import the whole deck as one JSON document. Used to move a
  // deck between devices (e.g. computer -> phone) and as a full backup.
  // ---------------------------------------------------------------------------

  /// Serialize every catalogue, card (images included, base64-encoded) and
  /// extra meaning into a single JSON string.
  Future<String> exportDeck() async {
    final cats = await select(catalogues).get();
    final cardRows = await select(cards).get();
    final meaningRows = await select(meanings).get();
    final doc = {
      'app': 'lexicon',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'catalogues': [
        for (final c in cats)
          {
            'id': c.id,
            'name': c.name,
            'color': c.color,
            'createdAt': c.createdAt.millisecondsSinceEpoch,
          }
      ],
      'cards': [
        for (final c in cardRows)
          {
            'id': c.id,
            'polish': c.polish,
            'english': c.english,
            'exampleSentence': c.exampleSentence,
            'englishDefinition': c.englishDefinition,
            'note': c.note,
            'tags': c.tags,
            'gender': c.gender,
            'catalogueId': c.catalogueId,
            // Once an image is in Storage (imageUrl set) we sync only the URL,
            // never the heavy base64 — that's what keeps the deck JSON small.
            'imageBytes': c.imageUrl != null || c.imageBytes == null
                ? null
                : base64Encode(c.imageBytes!),
            'imageUrl': c.imageUrl,
            'imageSource': c.imageSource,
            'isCard': c.isCard,
            'createdAt': c.createdAt.millisecondsSinceEpoch,
            'updatedAt': c.updatedAt.millisecondsSinceEpoch,
            'easeFactor': c.easeFactor,
            'intervalDays': c.intervalDays,
            'repetitions': c.repetitions,
            'lapses': c.lapses,
            'learningStep': c.learningStep,
            'dueDate': c.dueDate?.millisecondsSinceEpoch,
            'suspended': c.suspended,
          }
      ],
      'meanings': [
        for (final m in meaningRows)
          {
            'id': m.id,
            'cardId': m.cardId,
            'polishTranslation': m.polishTranslation,
            'englishDefinition': m.englishDefinition,
            'exampleSentence': m.exampleSentence,
            'sortOrder': m.sortOrder,
          }
      ],
    };
    return jsonEncode(doc);
  }

  /// Replace the entire deck with the contents of a backup produced by
  /// [exportDeck]. Returns how many cards/catalogues were restored. Throws a
  /// [FormatException] on a file that isn't a Lexicon backup.
  Future<({int cards, int catalogues})> importDeck(String jsonStr) async {
    final dynamic parsed = jsonDecode(jsonStr);
    if (parsed is! Map<String, dynamic> || parsed['app'] != 'lexicon') {
      throw const FormatException('This file is not a Lexicon backup.');
    }
    final catList = (parsed['catalogues'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final cardList =
        (parsed['cards'] as List? ?? const []).cast<Map<String, dynamic>>();
    final meaningList =
        (parsed['meanings'] as List? ?? const []).cast<Map<String, dynamic>>();

    DateTime ms(Object? v) =>
        DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

    await transaction(() async {
      await delete(meanings).go();
      await delete(cards).go();
      await delete(catalogues).go();
      await batch((b) {
        for (final c in catList) {
          b.insert(
              catalogues,
              CataloguesCompanion(
                id: Value(c['id'] as int),
                name: Value(c['name'] as String),
                color: Value(c['color'] as String?),
                createdAt: Value(ms(c['createdAt'])),
              ),
              mode: InsertMode.insertOrReplace);
        }
        for (final c in cardList) {
          final img = c['imageBytes'] as String?;
          b.insert(
              cards,
              CardsCompanion(
                id: Value(c['id'] as int),
                polish: Value(c['polish'] as String),
                english: Value(c['english'] as String),
                exampleSentence: Value(c['exampleSentence'] as String?),
                englishDefinition: Value(c['englishDefinition'] as String?),
                note: Value(c['note'] as String?),
                tags: Value(c['tags'] as String? ?? ''),
                gender: Value(c['gender'] as String?),
                catalogueId: Value(c['catalogueId'] as int?),
                imageBytes: Value(img == null ? null : base64Decode(img)),
                imageUrl: Value(c['imageUrl'] as String?),
                imageSource: Value(c['imageSource'] as String?),
                isCard: Value(c['isCard'] as bool? ?? false),
                createdAt: Value(ms(c['createdAt'])),
                updatedAt: Value(ms(c['updatedAt'])),
                easeFactor: Value((c['easeFactor'] as num).toDouble()),
                intervalDays: Value((c['intervalDays'] as num).toInt()),
                repetitions: Value((c['repetitions'] as num).toInt()),
                lapses: Value((c['lapses'] as num).toInt()),
                learningStep: Value((c['learningStep'] as num).toInt()),
                dueDate:
                    Value(c['dueDate'] == null ? null : ms(c['dueDate'])),
                suspended: Value(c['suspended'] as bool? ?? false),
              ),
              mode: InsertMode.insertOrReplace);
        }
        for (final m in meaningList) {
          b.insert(
              meanings,
              MeaningsCompanion(
                id: Value(m['id'] as int),
                cardId: Value(m['cardId'] as int),
                polishTranslation:
                    Value(m['polishTranslation'] as String? ?? ''),
                englishDefinition: Value(m['englishDefinition'] as String?),
                exampleSentence: Value(m['exampleSentence'] as String?),
                sortOrder: Value((m['sortOrder'] as num?)?.toInt() ?? 0),
              ),
              mode: InsertMode.insertOrReplace);
        }
      });
    });
    return (cards: cardList.length, catalogues: catList.length);
  }

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
