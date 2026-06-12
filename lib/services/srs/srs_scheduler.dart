/// Modified SM-2 spaced-repetition scheduler (Anki-inspired).
///
/// Adds short "learning steps" (minutes) for new and lapsed cards on top of the
/// classic SM-2 ease/interval math. Pure logic — no DB or UI dependency, so it
/// is trivially unit-testable.
library;

enum ReviewGrade { again, hard, good, easy }

class SrsState {
  final double easeFactor;
  final int intervalDays;
  final int repetitions;
  final int lapses;
  final int learningStep;
  final DateTime dueDate;

  const SrsState({
    required this.easeFactor,
    required this.intervalDays,
    required this.repetitions,
    required this.lapses,
    required this.learningStep,
    required this.dueDate,
  });
}

class SrsScheduler {
  static const List<int> learningStepsMin = [1, 10];
  static const int graduatingIntervalDays = 1;
  static const int easyIntervalDays = 4;
  static const double minEase = 1.3;

  /// Given the current state, a grade, and the current time, return next state.
  SrsState review(SrsState s, ReviewGrade grade, DateTime now) {
    final inLearning =
        s.repetitions == 0 || s.learningStep < learningStepsMin.length;
    return inLearning
        ? _reviewLearning(s, grade, now)
        : _reviewGraduated(s, grade, now);
  }

  SrsState _reviewLearning(SrsState s, ReviewGrade grade, DateTime now) {
    switch (grade) {
      case ReviewGrade.again:
        return _copy(s,
            learningStep: 0,
            repetitions: 0,
            due: now.add(Duration(minutes: learningStepsMin.first)));
      case ReviewGrade.hard:
        final i = s.learningStep.clamp(0, learningStepsMin.length - 1);
        return _copy(s, due: now.add(Duration(minutes: learningStepsMin[i])));
      case ReviewGrade.good:
        final next = s.learningStep + 1;
        if (next >= learningStepsMin.length) {
          return _copy(s,
              learningStep: next,
              repetitions: 1,
              intervalDays: graduatingIntervalDays,
              due: now.add(const Duration(days: graduatingIntervalDays)));
        }
        return _copy(s,
            learningStep: next,
            due: now.add(Duration(minutes: learningStepsMin[next])));
      case ReviewGrade.easy:
        return _copy(s,
            learningStep: learningStepsMin.length,
            repetitions: 1,
            intervalDays: easyIntervalDays,
            due: now.add(const Duration(days: easyIntervalDays)));
    }
  }

  SrsState _reviewGraduated(SrsState s, ReviewGrade grade, DateTime now) {
    if (grade == ReviewGrade.again) {
      final ease = _clampEase(s.easeFactor - 0.20);
      return _copy(s,
          easeFactor: ease,
          repetitions: 0,
          lapses: s.lapses + 1,
          learningStep: 0,
          intervalDays: 0,
          due: now.add(Duration(minutes: learningStepsMin.first)));
    }

    final q = switch (grade) {
      ReviewGrade.hard => 3,
      ReviewGrade.good => 4,
      ReviewGrade.easy => 5,
      ReviewGrade.again => 0, // unreachable
    };

    final ease = _clampEase(
      s.easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)),
    );

    final factor = switch (grade) {
      ReviewGrade.hard => 1.2,
      ReviewGrade.good => ease,
      ReviewGrade.easy => ease * 1.3,
      ReviewGrade.again => ease,
    };

    final prev = s.intervalDays == 0 ? 1 : s.intervalDays;
    final next = (prev * factor).round().clamp(1, 36500);

    return _copy(s,
        easeFactor: ease,
        repetitions: s.repetitions + 1,
        intervalDays: next,
        due: now.add(Duration(days: next)));
  }

  double _clampEase(double e) => e < minEase ? minEase : e;

  SrsState _copy(
    SrsState s, {
    double? easeFactor,
    int? intervalDays,
    int? repetitions,
    int? lapses,
    int? learningStep,
    required DateTime due,
  }) {
    return SrsState(
      easeFactor: easeFactor ?? s.easeFactor,
      intervalDays: intervalDays ?? s.intervalDays,
      repetitions: repetitions ?? s.repetitions,
      lapses: lapses ?? s.lapses,
      learningStep: learningStep ?? s.learningStep,
      dueDate: due,
    );
  }
}

/// Human-readable preview of when each grade would schedule the card next.
String previewInterval(SrsScheduler s, SrsState state, ReviewGrade g, DateTime now) {
  final next = s.review(state, g, now);
  final d = next.dueDate.difference(now);
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}
