import 'package:flutter_test/flutter_test.dart';
import 'package:ranepa_sync/format.dart';
import 'package:ranepa_sync/models.dart';
import 'package:ranepa_sync/services/demo.dart';
import 'package:ranepa_sync/services/sync.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  List<Lesson> lessonsAt(DateTime now) => parseLessons(demoResult(now).days);

  test('во вторник в 11:05 идёт вторая пара по обычной сетке', () {
    final now = DateTime(2026, 10, 13, 11, 5);
    final today = lessonsAt(now).where((l) => sameDay(l.start, now)).toList();
    expect(today.map((l) => hm(l.start)), ['09:00', '10:40', '12:20', '14:00']);
    expect(
      today.where((l) => !now.isBefore(l.start) && now.isBefore(l.end)),
      hasLength(1),
    );
  });

  test('в любое время сегодня есть пары и они не выходят за сутки', () {
    for (final hour in [0, 3, 8, 15, 21, 23]) {
      // Воскресенье: берётся расписание вторника.
      final now = DateTime(2026, 10, 18, hour, 50);
      final today = lessonsAt(now)
          .where((l) => sameDay(l.start, now) || sameDay(l.end, now))
          .toList();
      expect(today, isNotEmpty, reason: '$hour:50');
      for (final l in today) {
        expect(sameDay(l.start, now) && sameDay(l.end, now), isTrue);
      }
    }
  });

  test('месяц расписания с отменой, консультацией и зачётом', () {
    final now = DateTime(2026, 10, 13, 11, 5);
    final lessons = lessonsAt(now);
    final monday = mondayOf(now);
    expect(lessons.first.start.isAfter(monday), isTrue);
    expect(
      lessons.last.start.isBefore(
        monday.add(const Duration(days: 7 * fetchWeeks)),
      ),
      isTrue,
    );
    expect(lessons.where((l) => l.cancelled), hasLength(1));
    final kinds = lessons.map((l) => l.kind).toSet();
    expect(
      kinds,
      containsAll([
        'лекция',
        'семинар',
        'лабораторная',
        'физкультура',
        'консультация',
        'зачёт',
      ]),
    );
  });

  test('нечётная ревизия меняет аудиторию завтра', () {
    final now = DateTime(2026, 10, 13, 11, 5);
    final tomorrow = now.add(const Duration(days: 1));
    Lesson first(int revision) =>
        parseLessons(demoResult(now, revision: revision).days)
            .firstWhere((l) => sameDay(l.start, tomorrow));
    expect(first(1).room, isNot(first(0).room));
    expect(first(2).room, first(0).room);
  });
}
