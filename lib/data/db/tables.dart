import 'package:drift/drift.dart';

/// A catalogue / module the user organizes cards into (e.g. "Medical", "Travel").
class Catalogues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get color => text().nullable()(); // hex string for the UI chip
  TextColumn get icon => text().nullable()(); // a single emoji shown on the chip
  // A small custom image (picked from disk) used as the chip icon; takes
  // precedence over [icon] when set.
  BlobColumn get iconBytes => blob().nullable()();
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

  // Free-form personal note (mnemonics, usage tips, etc.). Shown subtly on the
  // study card.
  TextColumn get note => text().nullable()();

  // Domain tags stored as a ';'-separated string. By convention the first tag
  // is the part of speech (e.g. "noun") and the rest are topics ("animals").
  TextColumn get tags => text().withDefault(const Constant(''))();

  // Grammatical gender for nouns: 'm', 'f', 'n', or null.
  TextColumn get gender => text().nullable()();

  IntColumn get catalogueId => integer()
      .nullable()
      .references(Catalogues, #id, onDelete: KeyAction.setNull)();

  // --- Visual anchor ---
  // Bytes: the local copy (offline, instant). Url: the same image uploaded to
  // Supabase Storage, so it can sync to other devices without bloating the
  // deck JSON. A card may have bytes, a url, or both.
  BlobColumn get imageBytes => blob().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get imageSource => text().nullable()(); // 'ai' | 'manual' | null

  // Whether the user has starred this entry as a favourite (shown in the
  // "Favourites" filter). Independent of isCard / SRS state.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

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

/// Additional meanings for a card, beyond the primary one stored inline on
/// [Cards]. A term can have any number of these (a one-to-many relationship).
class Meanings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();
  TextColumn get polishTranslation => text().withDefault(const Constant(''))();
  TextColumn get englishDefinition => text().nullable()();
  TextColumn get exampleSentence => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
