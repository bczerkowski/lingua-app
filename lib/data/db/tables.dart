import 'package:drift/drift.dart';

/// A catalogue / module the user organizes cards into (e.g. "Medical", "Travel").
class Catalogues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get color => text().nullable()(); // hex string for the UI chip
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A dictionary entry that becomes a study card when promoted (isCard = true).
/// Row class is named `Flashcard` to avoid clashing with Material's `Card`.
@DataClassName('Flashcard')
class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();

  // --- Target line ---
  TextColumn get polish => text().withLength(min: 1, max: 200)();
  TextColumn get english => text().withLength(min: 1, max: 200)();

  // --- Card body ---
  TextColumn get exampleSentence => text().nullable()();
  TextColumn get englishDefinition => text().nullable()();

  // Domain tags stored as a ';'-separated string (simple + portable).
  TextColumn get tags => text().withDefault(const Constant(''))();

  IntColumn get catalogueId => integer()
      .nullable()
      .references(Catalogues, #id, onDelete: KeyAction.setNull)();

  // --- Visual anchor: stored as bytes so it works offline on every platform ---
  BlobColumn get imageBytes => blob().nullable()();
  TextColumn get imageSource => text().nullable()(); // 'ai' | 'manual' | null

  // --- Lifecycle ---
  BoolColumn get isCard => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  // --- SRS state (modified SM-2) ---
  RealColumn get easeFactor => real().withDefault(const Constant(2.5))();
  IntColumn get intervalDays => integer().withDefault(const Constant(0))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get learningStep => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get suspended => boolean().withDefault(const Constant(false))();
}
