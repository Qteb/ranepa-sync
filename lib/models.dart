import 'package:timezone/timezone.dart' as tz;

/// Тип занятия из ЛК → короткое название. Физкультура в ЛК — обычное
/// практическое занятие, её узнаём по названию предмета. Типы сессии
/// (консультации, экзамены, зачёты) ищем по словам: точных названий в ЛК
/// мы пока не видели.
String _kindOf(String type, String subject) {
  final t = type.toLowerCase();
  if (subject.toLowerCase().contains('физической культур')) {
    return 'физкультура';
  }
  if (t.contains('лекц')) return 'лекция';
  if (t.contains('практ') || t.contains('семин')) return 'семинар';
  if (t.contains('лаборатор')) return 'лабораторная';
  if (t.contains('консульт')) return 'консультация';
  if (t.contains('экзамен')) return 'экзамен';
  if (t.contains('зач')) return 'зачёт';
  return t;
}

class Lesson {
  Lesson({
    required this.start,
    required this.end,
    required this.subject,
    required this.kind,
    required this.room,
    required this.lecturer,
    required this.email,
    required this.groups,
    required this.lmsLink,
    required this.comment,
    required this.cancelled,
  });

  /// Время в часовом поясе устройства (сайт отдаёт московское время без зоны).
  final DateTime start;
  final DateTime end;
  final String subject;
  final String kind; // «лекция», «семинар», ...
  final String room;
  final String lecturer;
  final String email;
  final List<String> groups;
  final String lmsLink;
  final String comment;
  final bool cancelled;

  String get title => kind.isEmpty ? subject : '$subject ($kind)';
  bool get isRemote => room.startsWith('СДО');
  String get location => isRemote ? 'Дистанционно' : room;

  /// «1 - 1112 (20) ТВ+ПК Блок 1В (Вернадского, 84 …)» → «1 - 1112» для виджета.
  String get shortLocation {
    if (isRemote) return 'Дистанционно';
    final i = room.indexOf(' (');
    return i > 0 ? room.substring(0, i) : room;
  }

  /// «1 - 2262, корпус 1» или «Дистанционно» — для уведомлений.
  String get placeLabel {
    if (isRemote) return 'Дистанционно';
    final building = RegExp(r'корпус\s*(\d+)').firstMatch(room)?.group(1);
    return building == null
        ? shortLocation
        : '$shortLocation, корпус $building';
  }

  String get details => [
    lecturer,
    email,
    groups.join(', '),
    lmsLink,
    comment,
  ].where((s) => s.isNotEmpty).join('\n');
}

DateTime _moscow(String value) {
  // "2026-10-12T09:00:00" — московское время без смещения.
  final naive = DateTime.parse(value);
  final moscow = tz.TZDateTime(
    tz.getLocation('Europe/Moscow'),
    naive.year,
    naive.month,
    naive.day,
    naive.hour,
    naive.minute,
  );
  // Не TZDateTime.toLocal(): там «локальная» зона пакета, по умолчанию UTC.
  return DateTime.fromMillisecondsSinceEpoch(moscow.millisecondsSinceEpoch);
}

String _str(Object? v) => (v ?? '').toString().trim();

/// Разбирает сырые дни из n-api/schedule: [{"date": ..., "discs": [...]}, ...].
List<Lesson> parseLessons(List<dynamic> days) {
  final lessons = <Lesson>[];
  for (final day in days) {
    for (final disc in (day['discs'] as List? ?? [])) {
      final subject = _str(disc['disc']);
      final groups = disc['groups'];
      lessons.add(
        Lesson(
          start: _moscow(disc['start_date']),
          end: _moscow(disc['end_date']),
          subject: subject,
          kind: _kindOf(_str(disc['type']), subject),
          room: _str(disc['room']),
          lecturer: _str(disc['lecturer']),
          email: _str(disc['sam_email']),
          groups: groups is Map
              ? groups.values.map((g) => g.toString()).toList()
              : const [],
          lmsLink: _str(disc['lms_link']),
          comment: _str(disc['comment']),
          cancelled: _str(disc['status']).toLowerCase().contains('отмен'),
        ),
      );
    }
  }
  lessons.sort((a, b) => a.start.compareTo(b.start));
  return lessons;
}
