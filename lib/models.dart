import 'package:timezone/timezone.dart' as tz;

const _typeShort = {
  'Лекционные занятия': 'лекция',
  'Практические занятия': 'семинар',
  'Лабораторные занятия': 'лаба',
};

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
      final kind = _str(disc['type']);
      final groups = disc['groups'];
      lessons.add(
        Lesson(
          start: _moscow(disc['start_date']),
          end: _moscow(disc['end_date']),
          subject: _str(disc['disc']),
          kind: _typeShort[kind] ?? kind.toLowerCase(),
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
