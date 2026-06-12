import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_app/services/srs/srs_scheduler.dart';

void main() {
  final srs = SrsScheduler();
  final now = DateTime(2026, 1, 1, 12);

  SrsState fresh() => SrsState(
        easeFactor: 2.5,
        intervalDays: 0,
        repetitions: 0,
        lapses: 0,
        learningStep: 0,
        dueDate: now,
      );

  test('new card + Good advances through learning steps (minutes)', () {
    final s = srs.review(fresh(), ReviewGrade.good, now);
    expect(s.dueDate.difference(now).inMinutes,
        SrsScheduler.learningStepsMin[1]); // 10 minutes
    expect(s.repetitions, 0); // not graduated yet
  });

  test('two Goods graduate the card to 1 day', () {
    var s = srs.review(fresh(), ReviewGrade.good, now);
    s = srs.review(s, ReviewGrade.good, now);
    expect(s.intervalDays, SrsScheduler.graduatingIntervalDays);
    expect(s.repetitions, 1);
  });

  test('Easy on a new card jumps straight out of learning', () {
    final s = srs.review(fresh(), ReviewGrade.easy, now);
    expect(s.intervalDays, SrsScheduler.easyIntervalDays);
    expect(s.repetitions, 1);
  });

  test('graduated card grows interval and Again causes a lapse', () {
    // Graduate first.
    var s = srs.review(fresh(), ReviewGrade.easy, now); // interval 4, reps 1
    final graduated = s;
    s = srs.review(graduated, ReviewGrade.good, now);
    expect(s.intervalDays, greaterThan(graduated.intervalDays));

    final lapsed = srs.review(s, ReviewGrade.again, now);
    expect(lapsed.lapses, 1);
    expect(lapsed.repetitions, 0);
    expect(lapsed.easeFactor, lessThan(s.easeFactor));
  });

  test('ease factor never drops below the floor', () {
    var s = srs.review(fresh(), ReviewGrade.easy, now);
    for (var i = 0; i < 20; i++) {
      s = srs.review(s, ReviewGrade.hard, now);
    }
    expect(s.easeFactor, greaterThanOrEqualTo(SrsScheduler.minEase));
  });
}
