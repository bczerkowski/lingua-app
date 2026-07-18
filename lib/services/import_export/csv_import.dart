import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../../data/db/database.dart';

/// One parsed entry from a CSV before insertion.
class ParsedEntry {
  final String english;
  final String polish;
  final String? example;
  final String? definition;
  const ParsedEntry(this.english, this.polish, this.example, this.definition);
}

/// Parses CSV bytes (e.g. a Quizlet export) into entries.
///
/// Recognized headers (case-insensitive): `question`, `answer`,
/// `question example`, `question hint`. Falls back to:
/// column 0 = English term, column 1 = Polish translation.
class CsvImporter {
  final AppDatabase db;
  CsvImporter(this.db);

  List<ParsedEntry> parse(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // strip UTF-8 BOM
    }
    // Normalize CRLF/CR so a single eol works regardless of the source OS.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(text);
    if (rows.isEmpty) return const [];

    // Detect a header row and map columns by name.
    final header = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
    int idx(String name) => header.indexOf(name);
    final qi = idx('question');
    final ai = idx('answer');
    final hasHeader = qi != -1 && ai != -1;

    final iEnglish = hasHeader ? qi : 0;
    final iPolish = hasHeader ? ai : 1;
    // Accept the example/definition from either the question- or answer-side
    // column, so files that fill "answer example" / "answer hint" still work.
    final iQEx = hasHeader ? idx('question example') : -1;
    final iAEx = hasHeader ? idx('answer example') : -1;
    final iQHint = hasHeader ? idx('question hint') : -1;
    final iAHint = hasHeader ? idx('answer hint') : -1;

    final dataRows = hasHeader ? rows.skip(1) : rows;
    final out = <ParsedEntry>[];
    for (final r in dataRows) {
      String cell(int i) =>
          (i >= 0 && i < r.length) ? r[i].toString().trim() : '';
      String pick(int a, int b) {
        final va = cell(a);
        return va.isNotEmpty ? va : cell(b);
      }

      final english = cell(iEnglish);
      final polish = cell(iPolish);
      if (english.isEmpty || polish.isEmpty) continue;
      out.add(ParsedEntry(
        english,
        polish,
        _nullIfEmpty(pick(iQEx, iAEx)),
        _nullIfEmpty(pick(iQHint, iAHint)),
      ));
    }
    return out;
  }

  /// Inserts the entries as study cards, optionally under [catalogueId].
  Future<int> insertAll(List<ParsedEntry> entries, {int? catalogueId}) async {
    if (entries.isEmpty) return 0;
    final now = DateTime.now();
    await db.batch((b) {
      for (final e in entries) {
        b.insert(
          db.cards,
          CardsCompanion.insert(
            english: e.english,
            polish: e.polish,
            exampleSentence: Value(e.example),
            englishDefinition: Value(e.definition),
            catalogueId: Value(catalogueId),
            isCard: const Value(true),
            dueDate: Value(now),
          ),
        );
      }
    });
    return entries.length;
  }

  String? _nullIfEmpty(String s) => s.isEmpty ? null : s;
}
