import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../data/db/database.dart';
import '../../services/srs/srs_scheduler.dart';

/// Drives the study session: holds the in-memory queue and applies SM-2 grades.
class StudyController extends ChangeNotifier {
  final AppDatabase db;
  final SrsScheduler srs;
  StudyController(this.db, this.srs);

  final List<Flashcard> _queue = [];
  bool _loading = true;
  int _reviewed = 0;

  bool get loading => _loading;
  int get remaining => _queue.length;
  int get reviewed => _reviewed;
  Flashcard? get current => _queue.isEmpty ? null : _queue.first;

  Future<void> load({int? catalogueId}) async {
    _loading = true;
    notifyListeners();
    _queue
      ..clear()
      ..addAll(await db.dueCards(DateTime.now(), catalogueId: catalogueId));
    _reviewed = 0;
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

    _queue.removeAt(0);
    _reviewed++;
    // Card still due within the session (learning step in minutes) -> requeue.
    if (next.dueDate.difference(now).inMinutes < 20) {
      _queue.add(c);
    }
    notifyListeners();
  }
}
