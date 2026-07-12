import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/db/database.dart';

/// Renders the whole entry list into one PNG (so it can be saved/shared as a
/// single full-page image — browser full-page screenshot tools can't capture a
/// Flutter canvas app). Deterministic canvas drawing, no off-screen widgets.
///
/// Long decks are laid out in multiple columns so the image never exceeds the
/// GPU's max texture size (~16384px), which would make the capture fail.
Future<Uint8List> renderEntriesPng(List<Flashcard> entries) async {
  const colWidth = 640.0;
  const outer = 30.0;
  const cardPad = 20.0;
  const gap = 12.0;
  const colGap = 24.0;
  const headerH = 56.0;
  // Keep every dimension well under typical GPU max texture size.
  const maxTexture = 16000.0;
  const colBudget = maxTexture - headerH - outer - 120;
  final contentWidth = colWidth - 2 * cardPad;

  const bg = Color(0xFFF0EEE6);
  const surface = Color(0xFFFFFFFF);
  const border = Color(0xFFE6E2D9);
  const ink = Color(0xFF1A1A1A);

  TextPainter tp(InlineSpan span) {
    final p = TextPainter(
        text: span, textDirection: TextDirection.ltr, maxLines: null)
      ..layout(maxWidth: contentWidth);
    return p;
  }

  final rows = <_Row>[];
  for (final c in entries) {
    final title = tp(TextSpan(children: [
      TextSpan(
          text: c.english,
          style: const TextStyle(
              fontSize: 23, fontWeight: FontWeight.w700, color: ink)),
      const TextSpan(
          text: '    ·    ',
          style: TextStyle(fontSize: 21, color: Color(0xFFC4BFB5))),
      TextSpan(
          text: c.polish,
          style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              color: Color(0xFF3A3833))),
    ]));

    TextPainter? example;
    final ex = c.exampleSentence;
    if (ex != null && ex.trim().isNotEmpty) {
      example = tp(TextSpan(
          text: '“${ex.trim()}”',
          style: const TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              height: 1.35,
              color: Color(0xFF6B6B6B))));
    }

    TextPainter? tags;
    final tagList = c.tags
        .split(';')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (tagList.isNotEmpty) {
      final label = [
        tagList.first.toUpperCase(),
        for (final t in tagList.skip(1)) '#$t',
      ].join('     ');
      tags = tp(TextSpan(
          text: label,
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: Color(0xFF8A857C))));
    }

    var h = cardPad + title.height + cardPad;
    if (example != null) h += 9 + example.height;
    if (tags != null) h += 9 + tags.height;
    rows.add(_Row(title, example, tags, h));
  }

  // Choose a column count that keeps each column under the texture budget, then
  // fill columns top-to-bottom (preserves the alphabetical reading order).
  final totalH = rows.fold<double>(0, (a, r) => a + r.height + gap);
  var columns = (totalH / colBudget).ceil();
  if (columns < 1) columns = 1;
  final target = totalH / columns;
  final cols = List.generate(columns, (_) => <_Row>[]);
  var ci = 0;
  var acc = 0.0;
  for (final r in rows) {
    if (acc > target && ci < columns - 1) {
      ci++;
      acc = 0;
    }
    cols[ci].add(r);
    acc += r.height + gap;
  }

  double colHeight(List<_Row> c) =>
      c.fold<double>(0, (a, r) => a + r.height + gap);
  final maxCol = cols.map(colHeight).fold<double>(0, (a, b) => a > b ? a : b);

  final width = outer * 2 + columns * colWidth + (columns - 1) * colGap;
  final height = headerH + maxCol + outer;

  final recorder = ui.PictureRecorder();
  final maxDim = width > height ? width : height;
  final scale = (maxTexture / maxDim).clamp(1.0, 2.0).toDouble();
  final canvas = ui.Canvas(recorder)..scale(scale);

  canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = bg);

  final header = TextPainter(
      text: TextSpan(
          text: 'Lexicon · ${entries.length} '
              '${entries.length == 1 ? 'entry' : 'entries'}',
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: ink)),
      textDirection: TextDirection.ltr)
    ..layout();
  header.paint(canvas, const Offset(outer, 18));

  final fill = Paint()..color = surface;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = border;

  for (var col = 0; col < columns; col++) {
    final x = outer + col * (colWidth + colGap);
    var y = headerH;
    for (final r in cols[col]) {
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, colWidth, r.height),
          const Radius.circular(14));
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, stroke);

      var ty = y + cardPad;
      r.title.paint(canvas, Offset(x + cardPad, ty));
      ty += r.title.height;
      if (r.example != null) {
        ty += 9;
        r.example!.paint(canvas, Offset(x + cardPad, ty));
        ty += r.example!.height;
      }
      if (r.tags != null) {
        ty += 9;
        r.tags!.paint(canvas, Offset(x + cardPad, ty));
      }
      y += r.height + gap;
    }
  }

  final picture = recorder.endRecording();
  final img = await picture.toImage(
      (width * scale).round(), (height * scale).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  picture.dispose();
  if (data == null) {
    throw 'The list is too large to render as one image on this device.';
  }
  return data.buffer.asUint8List();
}

class _Row {
  final TextPainter title;
  final TextPainter? example;
  final TextPainter? tags;
  final double height;
  _Row(this.title, this.example, this.tags, this.height);
}
