import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/database.dart';
import '../../services/srs/srs_scheduler.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Records a study day and returns the current streak. Increments when studying
/// on a consecutive day, resets to 1 after a gap.
Future<int> recordStudyStreak() async {
  final p = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final today = _ymd(now);
  final last = p.getString('streak_last');
  var streak = p.getInt('streak_count') ?? 0;
  if (last == today) return streak;
  final yesterday = _ymd(now.subtract(const Duration(days: 1)));
  streak = (last == yesterday) ? streak + 1 : 1;
  await p.setInt('streak_count', streak);
  await p.setString('streak_last', today);
  return streak;
}

/// Reads the current streak, treating a gap of more than a day as broken.
Future<int> readStudyStreak() async {
  final p = await SharedPreferences.getInstance();
  final last = p.getString('streak_last');
  if (last == null) return 0;
  final now = DateTime.now();
  if (last == _ymd(now) || last == _ymd(now.subtract(const Duration(days: 1)))) {
    return p.getInt('streak_count') ?? 0;
  }
  return 0;
}

/// Which side of the card is shown on the front (what you recall).
enum StudyDirection { both, englishToPolish, polishToEnglish }

/// Drives the study session: holds the in-memory queue and applies SM-2 grades.
class StudyController extends ChangeNotifier {
  final AppDatabase db;
  final SrsScheduler srs;
  StudyController(this.db, this.srs);

  final List<Flashcard> _queue = [];
  // Extra Polish translations per card, preloaded with the queue so the study
  // view never has to run a per-build async query (which was racy / came back
  // empty right after revealing the card).
  Map<int, List<Meaning>> _meanings = {};
  bool _loading = true;
  int _reviewed = 0;

  // One level of undo for the last grade.
  Flashcard? _undoSnapshot; // card row before the last grade
  bool _undoRequeued = false; // whether the last grade re-queued the card

  bool get loading => _loading;
  int get remaining => _queue.length;
  int get reviewed => _reviewed;
  bool get canUndo => _undoSnapshot != null;
  Flashcard? get current => _queue.isEmpty ? null : _queue.first;

  /// Extra Polish translations for a card (empty if none / not loaded).
  List<Meaning> meaningsOf(int cardId) => _meanings[cardId] ?? const [];

  Future<void> load({int? catalogueId}) async {
    _loading = true;
    notifyListeners();
    final due = await db.dueCards(DateTime.now(), catalogueId: catalogueId);
    _queue
      ..clear()
      ..addAll(due);
    // Preload every queued card's extra meanings in one query.
    _meanings = await db.meaningsForCards([for (final c in due) c.id]);
    _reviewed = 0;
    _undoSnapshot = null;
    _loading = false;
    notifyListeners();
  }

  SrsState _stateOf(Flashcard c, DateTime now) => SrsState(
        easeFactor: c.easeFactor,
        intervalDays: c.intervalDays,
        repetitions: c.repetitions,
        lapses: c.lapses,
        learningStep: c.learningStep,
        dueDate: c.dueDate ?? now,
      );

  /// Preview label like "10m" / "1d" shown on each grade button.
  String previewFor(Flashcard c, ReviewGrade grade) {
    final now = DateTime.now();
    return previewInterval(srs, _stateOf(c, now), grade, now);
  }

  Future<void> grade(ReviewGrade grade) async {
    final c = current;
    if (c == null) return;
    final now = DateTime.now();
    final next = srs.review(_stateOf(c, now), grade, now);

    await (db.update(db.cards)..where((t) => t.id.equals(c.id))).write(
      CardsCompanion(
        easeFactor: Value(next.easeFactor),
        intervalDays: Value(next.intervalDays),
        repetitions: Value(next.repetitions),
        lapses: Value(next.lapses),
        learningStep: Value(next.learningStep),
        dueDate: Value(next.dueDate),
        updatedAt: Value(now),
      ),
    );

    recordStudyStreak(); // best-effort, fire-and-forget

    // Snapshot for undo (the state *before* this grade).
    _undoSnapshot = c;
    _queue.removeAt(0);
    _reviewed++;
    // Card still due within the session (learning step in minutes) -> requeue.
    _undoRequeued = next.dueDate.difference(now).inMinutes < 20;
    if (_undoRequeued) _queue.add(c);
    notifyListeners();
  }

  /// Reverse the last grade: restore the card's SRS state and put it back at
  /// the front of the queue.
  Future<void> undo() async {
    final snap = _undoSnapshot;
    if (snap == null) return;

    await (db.update(db.cards)..where((t) => t.id.equals(snap.id))).write(
      CardsCompanion(
        easeFactor: Value(snap.easeFactor),
        intervalDays: Value(snap.intervalDays),
        repetitions: Value(snap.repetitions),
        lapses: Value(snap.lapses),
        learningStep: Value(snap.learningStep),
        dueDate: Value(snap.dueDate),
      ),
    );

    // If the grade had re-queued the card, drop that requeued copy first.
    if (_undoRequeued) {
      final i = _queue.lastIndexWhere((e) => e.id == snap.id);
      if (i != -1) _queue.removeAt(i);
    }
    _queue.insert(0, snap);
    if (_reviewed > 0) _reviewed--;
    _undoSnapshot = null;
    notifyListeners();
  }
}
