import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/database.dart';
import '../../services/srs/srs_scheduler.dart';

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Daily new-card budget
//
// A "new" card is one that has never been reviewed (repetitions == 0). Reviews
// always flow through; new cards are rationed to [newPerDay] per calendar day
// so a big import can't flood the queue with hundreds of "due" cards at once.
// ---------------------------------------------------------------------------

const int kDefaultNewPerDay = 20;
const String _kNewPerDay = 'new_per_day';
const String _kNewIntroPrefix = 'newintro_'; // + yyyy-mm-dd

/// How many new cards the user allows per day (defaults to 20; 0 = none).
Future<int> readNewPerDay() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt(_kNewPerDay) ?? kDefaultNewPerDay;
}

Future<void> writeNewPerDay(int n) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kNewPerDay, n < 0 ? 0 : n);
}

Future<int> _introducedToday() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt('$_kNewIntroPrefix${_ymd(DateTime.now())}') ?? 0;
}

Future<void> _addIntroducedToday(int delta) async {
  final p = await SharedPreferences.getInstance();
  final key = '$_kNewIntroPrefix${_ymd(DateTime.now())}';
  final next = (p.getInt(key) ?? 0) + delta;
  await p.setInt(key, next < 0 ? 0 : next);
}

/// New cards still allowed today (never negative).
Future<int> remainingNewToday() async {
  final per = await readNewPerDay();
  if (per <= 0) return 0;
  final left = per - await _introducedToday();
  return left < 0 ? 0 : left;
}

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
  // New cards available but held back today by the daily limit (for a hint on
  // the "done" screen). Lets the user choose to learn a few more.
  int _lockedNew = 0;
  // New cards already counted against today's budget in this controller's life,
  // so a re-queued (graded "Again") new card is never double-counted.
  final Set<int> _introducedSession = {};

  // One level of undo for the last grade.
  Flashcard? _undoSnapshot; // card row before the last grade
  bool _undoRequeued = false; // whether the last grade re-queued the card

  bool get loading => _loading;
  int get remaining => _queue.length;
  int get reviewed => _reviewed;
  int get lockedNew => _lockedNew;
  bool get canUndo => _undoSnapshot != null;
  Flashcard? get current => _queue.isEmpty ? null : _queue.first;

  /// Extra Polish translations for a card (empty if none / not loaded).
  List<Meaning> meaningsOf(int cardId) => _meanings[cardId] ?? const [];

  Future<void> load({int? catalogueId}) async {
    _loading = true;
    notifyListeners();
    final now = DateTime.now();
    // Reviews always flow through; new cards are capped by today's remaining
    // budget so a large import can't dump hundreds of "due" cards at once.
    final allowance = await remainingNewToday();
    final reviews = await db.dueReviewCards(now, catalogueId: catalogueId);
    final news = await db.newStudyCards(now,
        catalogueId: catalogueId, limit: allowance);
    final newAvail = await db.countNewAvailable(now, catalogueId: catalogueId);
    _lockedNew = newAvail - news.length;
    if (_lockedNew < 0) _lockedNew = 0;
    final due = [...reviews, ...news];
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

  /// Pull [n] more brand-new cards into the queue, ignoring today's limit.
  /// Used by the "learn more" action on the finished screen.
  Future<void> learnMoreNew(int n, {int? catalogueId}) async {
    if (n <= 0) return;
    final now = DateTime.now();
    final queued = _queue.map((c) => c.id).toSet()..addAll(_introducedSession);
    final more = await db.newStudyCards(now,
        catalogueId: catalogueId, limit: n + queued.length);
    final add = more.where((c) => !queued.contains(c.id)).take(n).toList();
    if (add.isEmpty) return;
    final extra = await db.meaningsForCards([for (final c in add) c.id]);
    _meanings.addAll(extra);
    _queue.addAll(add);
    _lockedNew -= add.length;
    if (_lockedNew < 0) _lockedNew = 0;
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
    // A brand-new card being seen for the first time spends one of today's
    // new-card budget slots (counted once, even if it's re-queued as "Again").
    if (c.repetitions == 0 && _introducedSession.add(c.id)) {
      await _addIntroducedToday(1);
    }
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
    // Give back the new-card budget slot if this was a new card's first grade.
    if (snap.repetitions == 0 && _introducedSession.remove(snap.id)) {
      await _addIntroducedToday(-1);
    }
    _queue.insert(0, snap);
    if (_reviewed > 0) _reviewed--;
    _undoSnapshot = null;
    notifyListeners();
  }
}
