import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../data/db/database.dart';

/// Renders the whole entry list into one tall PNG (so it can be saved/shared as
/// a single full-page image — browser full-page screenshot tools can't capture
/// a Flutter canvas app). Deterministic canvas drawing, no off-screen widgets.
Future<Uint8List> renderEntriesPng(List<Flashcard> entries) async {
  const width = 860.0;
  const outer = 30.0;
  const cardPad = 20.0;
  const gap = 12.0;
  const headerH = 56.0;
  final contentWidth = width - 2 * outer - 2 * cardPad;

  const bg = Color(0xFFF0EEE6);
  const surface = Color(0xFFFFFFFF);
  const border = Color(0xFFE6E2D9);
  const ink = Color(0xFF1A1A1A);

  TextPainter tp(InlineSpan span, {double? maxWidth}) {
    final p = TextPainter(
        text: span, textDirection: TextDirection.ltr, maxLines: null);
    p.layout(maxWidth: maxWidth ?? contentWidth);
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
              fontSize: 21, fontWeight: FontWeight.w500, color: Color(0xFF3A3833))),
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

  final totalHeight = headerH +
      rows.fold<double>(0, (a, r) => a + r.height + gap) +
      outer;

  final recorder = ui.PictureRecorder();
  // Keep the output under browser canvas limits (~32767px) while staying crisp.
  final scale = (28000 / totalHeight).clamp(1.0, 2.0).toDouble();
  final canvas = ui.Canvas(recorder)..scale(scale);

  canvas.drawRect(
      Rect.fromLTWH(0, 0, width, totalHeight), Paint()..color = bg);

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

  var y = headerH;
  for (final r in rows) {
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(outer, y, width - 2 * outer, r.height),
        const Radius.circular(14));
    canvas.drawRRect(rect, fill);
    canvas.drawRRect(rect, stroke);

    var ty = y + cardPad;
    r.title.paint(canvas, Offset(outer + cardPad, ty));
    ty += r.title.height;
    if (r.example != null) {
      ty += 9;
      r.example!.paint(canvas, Offset(outer + cardPad, ty));
      ty += r.example!.height;
    }
    if (r.tags != null) {
      ty += 9;
      r.tags!.paint(canvas, Offset(outer + cardPad, ty));
    }
    y += r.height + gap;
  }

  final picture = recorder.endRecording();
  final img = await picture.toImage(
      (width * scale).round(), (totalHeight * scale).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class _Row {
  final TextPainter title;
  final TextPainter? example;
  final TextPainter? tags;
  final double height;
  _Row(this.title, this.example, this.tags, this.height);
}
