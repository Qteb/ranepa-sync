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
