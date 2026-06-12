import 'package:drift/drift.dart';

import 'connection/connection.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Catalogues, Cards])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  // Test constructor with an injectable executor (used by unit tests).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  // ---------------------------------------------------------------------------
  // Catalogues
  // ---------------------------------------------------------------------------
  Stream<List<Catalogue>> watchCatalogues() => select(catalogues).watch();

  Future<int> createCatalogue(String name, {String? color}) => into(catalogues)
      .insert(CataloguesCompanion.insert(name: name, color: Value(color)));

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

  Future<int> countCards() async {
    final c = countAll();
    final row = await (selectOnly(cards)
          ..where(cards.isCard.equals(true))
          ..addColumns([c]))
        .getSingle();
    return row.read(c) ?? 0;
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

  Future<Flashcard?> getCard(int id) =>
      (select(cards)..where((t) => t.id.equals(id))).getSingleOrNull();
}
