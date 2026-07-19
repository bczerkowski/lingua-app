import 'package:csv/csv.dart';

import '../../data/db/database.dart';

/// Serializes cards to a CSV string in the same column layout the importer
/// reads back (question = English, answer = Polish, plus example/hint/note).
/// Written with a UTF-8 BOM + CRLF so Excel opens the diacritics correctly.
String cardsToCsv(List<Flashcard> cards) {
  final rows = <List<String>>[
    ['question', 'answer', 'question example', 'question hint', 'note'],
    for (final c in cards)
      [
        c.english,
        c.polish,
        c.exampleSentence ?? '',
        c.englishDefinition ?? '',
        c.note ?? '',
      ],
  ];
  final csv = const ListToCsvConverter(eol: '\r\n').convert(rows);
  return '﻿$csv';
}
