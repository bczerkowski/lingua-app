import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../theme.dart';
import '../../widgets/card_image.dart';

/// A simple cram drill over today's hand-picked lesson set. Unlike the SRS
/// study screen, this just cycles the chosen cards in one sitting: reveal the
/// answer, then "Umiem" (drop it from the rotation) or "Jeszcze raz" (send it
/// to the back). It never touches SRS scheduling or the lesson membership —
/// clearing the lesson is an explicit action on the finish screen.
class LessonDrillScreen extends StatefulWidget {
  const LessonDrillScreen({super.key});

  @override
  State<LessonDrillScreen> createState() => _LessonDrillScreenState();
}

class _LessonDrillScreenState extends State<LessonDrillScreen> {
  final List<Flashcard> _queue = [];
  int _total = 0;
  int _done = 0;
  bool _revealed = false;
  bool _loading = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final db = AppServices.of(context).db;
    final cards = await db.lessonCards();
    cards.shuffle();
    if (!mounted) return;
    setState(() {
      _queue
        ..clear()
        ..addAll(cards);
      _total = cards.length;
      _done = 0;
      _revealed = false;
      _loading = false;
    });
  }

  Flashcard? get _current => _queue.isEmpty ? null : _queue.first;

  void _again() {
    if (_queue.isEmpty) return;
    setState(() {
      final c = _queue.removeAt(0);
      _queue.add(c); // back of the line — comes round again
      _revealed = false;
    });
  }

  void _know() {
    if (_queue.isEmpty) return;
    setState(() {
      _queue.removeAt(0);
      _done++;
      _revealed = false;
    });
  }

  Future<void> _clearAndExit() async {
    final db = AppServices.of(context).db;
    await db.clearLesson();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final done = !_loading && _queue.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lekcja dnia'),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _total == 0
              ? _empty('Lekcja jest pusta.\nDodaj karty ikoną 🎓 w słowniku.')
              : done
                  ? _finished()
                  : _drill(services),
    );
  }

  Widget _empty(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 56, color: AppTheme.coral),
              const SizedBox(height: 12),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Wróć'),
              ),
            ],
          ),
        ),
      );

  Widget _finished() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.celebration_rounded,
                  size: 60, color: AppTheme.coral),
              const SizedBox(height: 14),
              Text('Zapamiętane! 🎉',
                  style: GoogleFonts.sourceSerif4(
                      fontSize: 26, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Przećwiczyłeś wszystkie $_total fiszki z lekcji.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: AppTheme.muted)),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _load, // reshuffle and go again
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text('Powtórz jeszcze raz'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _clearAndExit,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Wyczyść lekcję (gotowe na dziś)'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Zostaw lekcję i wróć'),
              ),
            ],
          ),
        ),
      );

  Widget _drill(AppServices services) {
    final c = _current!;
    final screenW = MediaQuery.of(context).size.width;
    final maxW = screenW < 620 ? screenW : 560.0;
    return Column(
      children: [
        LinearProgressIndicator(
          value: _total == 0 ? 0 : _done / _total,
          minHeight: 6,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('${_done + 1} / $_total  ·  zostało ${_queue.length}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: () => setState(() => _revealed = true),
                  child: _card(services, c),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _revealed
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _again,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Jeszcze raz'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _know,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Umiem'),
                        ),
                      ),
                    ],
                  )
                : FilledButton(
                    onPressed: () => setState(() => _revealed = true),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Pokaż odpowiedź'),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _card(AppServices services, Flashcard c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(c.english,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.sourceSerif4(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.black)),
              ),
              IconButton(
                icon: const Icon(Icons.volume_up_rounded, color: AppTheme.muted),
                tooltip: 'Posłuchaj',
                onPressed: () => services.tts.speak(c.english, 'en-US'),
              ),
            ],
          ),
          if (!_revealed) ...[
            const SizedBox(height: 14),
            const Text('Stuknij, aby zobaczyć tłumaczenie',
                style: TextStyle(color: AppTheme.muted, fontSize: 13)),
          ],
          if (_revealed) ...[
            const Divider(height: 30),
            Text(c.polish,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.coralDark)),
            if (c.exampleSentence != null &&
                c.exampleSentence!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('“${c.exampleSentence!.trim()}”',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                      height: 1.35,
                      color: Color(0xFF55524B))),
            ],
            if (c.englishDefinition != null &&
                c.englishDefinition!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(c.englishDefinition!.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.35)),
            ],
            if (c.imageBytes != null ||
                (c.imageUrl != null && c.imageUrl!.isNotEmpty)) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    color: AppTheme.sand,
                    child: CardImage(
                        bytes: c.imageBytes,
                        url: c.imageUrl,
                        fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
