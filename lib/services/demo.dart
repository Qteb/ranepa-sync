import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../format.dart';
import '../ranepa_client.dart';
import 'sync.dart';

/// Демо-режим: Наташа Ростова и выдуманное расписание без обращений к ЛК.
/// Нужен для App Review (у проверяющего нет аккаунта в ЛК), скриншотов
/// и проверки без интернета. Включается долгим нажатием на логотип
/// на стартовом экране.
bool isDemo(SharedPreferences prefs) => prefs.getBool(Keys.demo) ?? false;

const demoGroup = 'ГМУ-ОБ25-03';
const demoProgram = 'Государственное и муниципальное управление';
const demoName = 'Ростова Наталья Ильинична';

/// Схематичный портрет вместо фото из ЛК.
const demoAvatarSvg =
    '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
    '<rect width="100" height="100" fill="#F3C6D3"/>'
    '<path d="M14 100c2-19 17-29 36-29s34 10 36 29z" fill="#D9637E"/>'
    '<path d="M29 44c0-15 9-25 21-25s21 10 21 25v28c-6 3-12 3-17 1V60H46'
    'v13c-5 2-11 2-17-1z" fill="#5A3A2B"/>'
    '<rect x="43" y="56" width="14" height="16" rx="6" fill="#E3AE8A"/>'
    '<circle cx="50" cy="44" r="19" fill="#F2C6A2"/>'
    '<path d="M31 43c0-13 8-21 19-21s19 8 19 21c-7-2-12-7-14-12'
    'c-5 6-14 10-24 12z" fill="#5A3A2B"/>'
    '<circle cx="43" cy="47" r="2" fill="#3A2A20"/>'
    '<circle cx="57" cy="47" r="2" fill="#3A2A20"/>'
    '<path d="M45 54q5 4 10 0" stroke="#3A2A20" stroke-width="2" '
    'fill="none" stroke-linecap="round"/>'
    '</svg>';

/// Пары в ЛК: 09:00–10:20, 10:40–12:00, …
const _slots = [(9, 0), (10, 40), (12, 20), (14, 0), (15, 40)];
const _pairLength = Duration(minutes: 80);

const _lecture = 'Лекция';
const _seminar = 'Практическое занятие';
const _lab = 'Лабораторная работа';

const _remote = 'СДО (дистанционно)';
const _rooms = [
  '5 - 201 (44) П+ПК (Вернадского, 82 - корпус 5)',
  '1 - 1112 (20) ТВ+ПК Блок 1B (Вернадского, 84 - корпус 1)',
  '1 - 2262 (24) П+ПК Блок 2F (Вернадского, 84 - корпус 1)',
  '1 - 2317 (24) ТВ+ПК Блок 2H (Вернадского, 84 - корпус 1)',
  'Спорткомплекс (Вернадского, 84 - корпус 9)',
];

/// Предмет, преподаватель, почта. Люди и адреса выдуманы.
const _subjects = [
  ('Теория управления', 'Соколова Мария Андреевна', 'sokolova-ma'),
  ('Экономическая теория', 'Лебедев Игорь Павлович', 'lebedev-ip'),
  // Без почты: так тоже бывает, и карточка выглядит чище на скриншотах.
  ('Иностранный язык (английский)', 'Морозова Ксения Олеговна', ''),
  (
    'Элективные дисциплины по физической культуре и спорту',
    'Васильев Денис Сергеевич',
    'vasilev-ds',
  ),
  ('Математика', 'Ершова Наталья Викторовна', 'ershova-nv'),
  (
    'Основы российской государственности',
    'Кузнецов Алексей Михайлович',
    'kuznetsov-am',
  ),
  (
    'Информационные технологии в управлении',
    'Тихонов Павел Андреевич',
    'tikhonov-pa',
  ),
  ('Правоведение', 'Белова Ольга Николаевна', 'belova-on'),
];

/// Неделя: день (1 — понедельник) → (пара, предмет, тип, аудитория).
/// Аудитория -1 — дистанционно.
const _week = {
  1: [(0, 5, _lecture, -1), (1, 1, _lecture, 0), (2, 1, _seminar, 2)],
  2: [
    (0, 0, _lecture, 0),
    (1, 2, _seminar, 3),
    (2, 3, _seminar, 4),
    (3, 6, _lab, 1),
  ],
  3: [(1, 4, _lecture, 0), (2, 4, _seminar, 2), (3, 7, _seminar, 3)],
  4: [(0, 7, _lecture, -1), (1, 0, _seminar, 1), (2, 2, _seminar, 3)],
  5: [(0, 6, _lecture, 0), (1, 1, _seminar, 2), (2, 3, _seminar, 4)],
  6: [(0, 5, _seminar, -1), (1, 4, _seminar, 1)],
};

/// Сдвиг сегодняшних пар: вторая идёт уже 25 минут, поэтому карточка
/// «Сейчас» видна в любое время. Кратен 5 минутам и не выходит за сутки.
/// С `DEMO_AT=…T11:05` сдвига нет.
Duration _todayShift(DateTime now) {
  final today = dateOnly(now);
  final secondStart = today.add(const Duration(hours: 10, minutes: 40));
  var shift = now.difference(secondStart) - const Duration(minutes: 25);
  shift = Duration(minutes: (shift.inMinutes / 5).round() * 5);
  // Отступ в 5 минут от полуночи с обеих сторон.
  final dayStart = today.add(const Duration(minutes: 5));
  final firstStart = today.add(const Duration(hours: 9)).add(shift);
  if (firstStart.isBefore(dayStart)) shift += dayStart.difference(firstStart);
  final lastEnd = today
      .add(const Duration(hours: 14))
      .add(_pairLength)
      .add(shift);
  final dayEnd = today.add(const Duration(hours: 23, minutes: 55));
  if (lastEnd.isAfter(dayEnd)) shift -= lastEnd.difference(dayEnd);
  return shift;
}

/// Расписание на [fetchWeeks] недель вокруг [now]. Сегодня — со сдвигом
/// [shift] (в воскресенье — расписание вторника). Нечётная [revision] меняет
/// аудиторию первой пары завтра — так видно уведомление об изменении.
FetchResult demoResult(DateTime now, {int revision = 0, Duration? shift}) {
  final today = dateOnly(now);
  final monday = mondayOf(now);
  final moscow = tz.getLocation('Europe/Moscow');
  String stamp(DateTime local) =>
      tz.TZDateTime.from(local, moscow).toIso8601String().substring(0, 19);
  shift ??= _todayShift(now);

  var nextDay = today.add(const Duration(days: 1));
  if (nextDay.weekday == DateTime.sunday) {
    nextDay = nextDay.add(const Duration(days: 1));
  }

  final days = <Map<String, dynamic>>[];
  for (var i = 0; i < 7 * fetchWeeks; i++) {
    final day = monday.add(Duration(days: i));
    final isToday = sameDay(day, today);
    final plan = isToday && day.weekday == DateTime.sunday
        ? _week[2]!
        : _week[day.weekday] ?? const [];
    final week = i ~/ 7;
    final discs = <Map<String, dynamic>>[];
    for (final (n, (slot, subject, type, room)) in plan.indexed) {
      final (h, m) = _slots[slot];
      var start = day.add(Duration(hours: h, minutes: m));
      if (isToday) start = start.add(shift);
      final (name, lecturer, email) = _subjects[subject];
      var place = room < 0 ? _remote : _rooms[room];
      if (revision.isOdd && sameDay(day, nextDay) && n == 0) {
        place = _rooms[(room + 2) % 4];
      }
      // Предпоследняя неделя — консультация, последняя — зачёт.
      final kind = week == fetchWeeks - 2 && day.weekday == 6 && n == 1
          ? 'Консультация'
          : week == fetchWeeks - 1 && day.weekday == 6 && n == 1
          ? 'Зачёт'
          : type;
      discs.add({
        'start_date': stamp(start),
        'end_date': stamp(start.add(_pairLength)),
        'disc': name,
        'type': kind,
        'room': place,
        'lecturer': lecturer,
        'sam_email': email.isEmpty ? '' : '$email@ranepa.example',
        'groups': type == _lecture
            ? {'0': demoGroup, '1': 'ГМУ-ОБ25-04'}
            : {'0': demoGroup},
        'lms_link': room < 0 ? 'https://lms.ranepa.ru/' : '',
        'comment': type == _lab ? 'Нужен ноутбук' : '',
        // Одна отменённая пара послезавтра.
        'status':
            sameDay(day, nextDay.add(const Duration(days: 1))) &&
                n == plan.length - 1
            ? 'Отменено'
            : '',
      });
    }
    days.add({'date': stamp(day), 'discs': discs});
  }
  return FetchResult(
    days: days,
    group: demoGroup,
    program: demoProgram,
    fullName: demoName,
  );
}

/// Демо-расписание на сегодня. Сдвиг запоминается на весь день, иначе
/// каждое обновление «переносило» бы сегодняшние пары.
Future<FetchResult> demoFetch(
  SharedPreferences prefs, {
  int revision = 0,
}) async {
  final now = currentTime();
  final day = dateOnly(now).toIso8601String();
  final saved = prefs.getString(Keys.demoShift)?.split('|');
  Duration shift;
  if (saved != null && saved.length == 2 && saved[0] == day) {
    shift = Duration(minutes: int.parse(saved[1]));
  } else {
    shift = _todayShift(now);
    await prefs.setString(Keys.demoShift, '$day|${shift.inMinutes}');
  }
  return demoResult(now, revision: revision, shift: shift);
}

/// Обновление в демо: без сети. Расписание пересобирается раз в день,
/// «потянуть вниз» каждый раз меняет одну аудиторию.
Future<SyncResult> syncDemo(
  SharedPreferences prefs,
  SyncTrigger trigger,
) async {
  final now = currentTime();
  final fetchedAt = prefs.getInt(Keys.fetchedAt);
  final fresh =
      fetchedAt != null &&
      sameDay(DateTime.fromMillisecondsSinceEpoch(fetchedAt), now);
  if (trigger != SyncTrigger.manual && fresh) {
    return SyncResult.skipped(SkipReason.notNeeded);
  }
  var revision = prefs.getInt(Keys.demoRevision) ?? 0;
  if (trigger == SyncTrigger.manual) {
    // Как настоящий запрос: жест не должен заканчиваться мгновенно.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    revision++;
    await prefs.setInt(Keys.demoRevision, revision);
  }
  final result = await saveSchedule(
    prefs,
    await demoFetch(prefs, revision: revision),
    mondayOf(now),
  );
  // Новый день пересобирает всё — это не изменения в расписании.
  return trigger == SyncTrigger.manual
      ? result
      : SyncResult(changes: const [], sideEffectError: result.sideEffectError);
}
