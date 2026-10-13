import 'models.dart';

const weekdaysShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const weekdaysLong = [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
];
const monthsGenitive = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

/// Время для скриншотов: `--dart-define=DEMO_AT=2026-10-13T11:05` переводит
/// часы приложения в эту точку, дальше они идут как обычно.
final Duration _clockShift = () {
  final at = DateTime.tryParse(const String.fromEnvironment('DEMO_AT'));
  return at == null ? Duration.zero : at.difference(DateTime.now());
}();

/// Текущее время приложения. Без DEMO_AT — обычное DateTime.now().
DateTime currentTime() => DateTime.now().add(_clockShift);

String _two(int v) => v.toString().padLeft(2, '0');

String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String timeRange(Lesson l) => '${hm(l.start)}–${hm(l.end)}';

String dayTitle(DateTime d) =>
    '${weekdaysLong[d.weekday - 1]}, ${d.day} ${monthsGenitive[d.month - 1]}';

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime mondayOf(DateTime t) =>
    dateOnly(t).subtract(Duration(days: t.weekday - 1));

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// «Сегодня», «Завтра», «Вчера» или день недели.
String relativeDayName(DateTime d) {
  final diff = dateOnly(d).difference(dateOnly(currentTime())).inDays;
  return switch (diff) {
    0 => 'Сегодня',
    1 => 'Завтра',
    -1 => 'Вчера',
    _ => weekdaysLong[d.weekday - 1],
  };
}

/// «40 мин», «1 ч», «1 ч 40 мин».
String duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m мин';
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

/// «сегодня в 12:20», «завтра в 09:00», «в среду в 09:00».
String whenLabel(DateTime t) {
  final diff = dateOnly(t).difference(dateOnly(currentTime())).inDays;
  final day = switch (diff) {
    0 => 'сегодня',
    1 => 'завтра',
    _ =>
      '${_weekdaysAccusative[t.weekday - 1]} ${t.day} ${monthsGenitive[t.month - 1]}',
  };
  return '$day в ${hm(t)}';
}

const _weekdaysAccusative = [
  'в понедельник',
  'во вторник',
  'в среду',
  'в четверг',
  'в пятницу',
  'в субботу',
  'в воскресенье',
];

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
