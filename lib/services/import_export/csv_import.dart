import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../../data/db/database.dart';

/// One parsed entry from a CSV/XLSX before insertion.
class ParsedEntry {
  final String english;
  final String polish;
  final String? example;
  final String? definition;
  final String? note;
  const ParsedEntry(
      this.english, this.polish, this.example, this.definition, this.note);
}

/// Parses CSV or XLSX bytes into entries.
///
/// Recognized headers (case-insensitive): `question` (English), `answer`
/// (Polish), `question/answer example`, `question/answer hint`, `note`.
/// Without a header row it falls back to column 0 = English, column 1 = Polish.
class CsvImporter {
  final AppDatabase db;
  CsvImporter(this.db);

  /// Parse CSV bytes.
  List<ParsedEntry> parse(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1); // strip UTF-8 BOM
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final raw = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(text);
    final rows = [
      for (final r in raw) [for (final c in r) c.toString()]
    ];
    return _parseRows(rows);
  }

  /// Parse an .xlsx workbook (first sheet). Reads shared- and inline-string
  /// cells directly from the zip, which is more robust than heavy xlsx
  /// libraries that choke on some exports.
  List<ParsedEntry> parseXlsx(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? file(String name) {
      for (final a in archive.files) {
        if (a.name == name) return a;
      }
      return null;
    }

    String content(ArchiveFile a) =>
        utf8.decode(a.content as List<int>, allowMalformed: true);

    // Shared strings table (optional — some files use inline strings instead).
    final shared = <String>[];
    final ss = file('xl/sharedStrings.xml');
    if (ss != null) {
      final xml = content(ss);
      for (final si in RegExp(r'<si>([\s\S]*?)</si>').allMatches(xml)) {
        final buf = StringBuffer();
        for (final t
            in RegExp(r'<t[^>]*>([\s\S]*?)</t>').allMatches(si.group(1)!)) {
          buf.write(_xmlUnescape(t.group(1)!));
        }
        shared.add(buf.toString());
      }
    }

    var sheet = file('xl/worksheets/sheet1.xml');
    sheet ??= archive.files
        .where((a) =>
            a.name.startsWith('xl/worksheets/') && a.name.endsWith('.xml'))
        .fold<ArchiveFile?>(null, (p, e) => p ?? e);
    if (sheet == null) return const [];
    final xml = content(sheet);

    final grid = <int, Map<int, String>>{};
    var maxCol = 0;
    for (final m in RegExp(r'<c r="([A-Z]+)(\d+)"([^>]*)>([\s\S]*?)</c>')
        .allMatches(xml)) {
      final col = _colIndex(m.group(1)!);
      final row = int.parse(m.group(2)!);
      final attrs = m.group(3)!;
      final body = m.group(4)!;
      String val = '';
      if (attrs.contains('t="inlineStr"')) {
        final buf = StringBuffer();
        for (final t in RegExp(r'<t[^>]*>([\s\S]*?)</t>').allMatches(body)) {
          buf.write(_xmlUnescape(t.group(1)!));
        }
        val = buf.toString();
      } else {
        final v = RegExp(r'<v>([\s\S]*?)</v>').firstMatch(body)?.group(1);
        if (v != null) {
          if (attrs.contains('t="s"')) {
            final i = int.tryParse(v.trim());
            val = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
          } else {
            val = _xmlUnescape(v);
          }
        }
      }
      grid.putIfAbsent(row, () => {})[col] = val;
      if (col > maxCol) maxCol = col;
    }

    final rowNums = grid.keys.toList()..sort();
    final rows = <List<String>>[
      for (final n in rowNums)
        [for (var c = 0; c <= maxCol; c++) grid[n]![c] ?? '']
    ];

    // Require a readable header so a garbled decode never creates junk cards.
    final header =
        rows.isEmpty ? const <String>[] : rows.first.map(_norm).toList();
    if (!header.contains('question') || !header.contains('answer')) {
      throw const FormatException(
          'Could not read the spreadsheet headers — save it as CSV UTF-8 and '
          'import that instead.');
    }
    return _parseRows(rows);
  }

  List<ParsedEntry> _parseRows(List<List<String>> rows) {
    if (rows.isEmpty) return const [];
    final header = rows.first.map(_norm).toList();
    int idx(String name) => header.indexOf(name);
    final qi = idx('question');
    final ai = idx('answer');
    final hasHeader = qi != -1 && ai != -1;

    final iEnglish = hasHeader ? qi : 0;
    final iPolish = hasHeader ? ai : 1;
    // Example/definition may sit on the question- or answer-side column.
    final iQEx = hasHeader ? idx('question example') : -1;
    final iAEx = hasHeader ? idx('answer example') : -1;
    final iQHint = hasHeader ? idx('question hint') : -1;
    final iAHint = hasHeader ? idx('answer hint') : -1;
    // Optional personal note (usage: formal/informal, top synonyms, etc.).
    final iNote = hasHeader ? idx('note') : -1;

    final dataRows = hasHeader ? rows.skip(1) : rows;
    final out = <ParsedEntry>[];
    for (final r in dataRows) {
      String cell(int i) => (i >= 0 && i < r.length) ? r[i].trim() : '';
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
        _nullIfEmpty(cell(iNote)),
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
            note: Value(e.note),
            catalogueId: Value(catalogueId),
            isCard: const Value(true),
            dueDate: Value(now),
          ),
        );
      }
    });
    return entries.length;
  }

  static String _norm(String s) => s.trim().toLowerCase();

  /// Spreadsheet column letters -> 0-based index (A=0, B=1, … AA=26).
  static int _colIndex(String s) {
    var n = 0;
    for (final code in s.codeUnits) {
      n = n * 26 + (code - 64);
    }
    return n - 1;
  }

  static String _xmlUnescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&amp;', '&');

  String? _nullIfEmpty(String s) => s.isEmpty ? null : s;
}
