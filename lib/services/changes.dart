import '../format.dart';
import '../models.dart';

/// За сколько дней вперёд сообщаем об изменениях: дальние недели в ЛК
/// часто правят, и уведомления о них — шум.
const changesHorizon = Duration(days: 7);

/// Сравнивает старое и новое расписание и описывает изменения в ближайшие
/// [changesHorizon] строками вида «Микроэкономика, ср 22.10: перенесли с 12:20
/// на 14:00». Пары сопоставляются по дню, предмету и типу занятия.
List<String> describeChanges(
  List<Lesson> before,
  List<Lesson> after, {
  required DateTime now,
}) {
  final horizon = now.add(changesHorizon);
  bool relevant(Lesson l) => l.start.isAfter(now) && l.start.isBefore(horizon);

  String key(Lesson l) => '${dateOnly(l.start)}|${l.subject}|${l.kind}';
  Map<String, List<Lesson>> group(List<Lesson> lessons) {
    final map = <String, List<Lesson>>{};
    for (final l in lessons) {
      map.putIfAbsent(key(l), () => []).add(l);
    }
    return map;
  }

  final old = group(before);
  final fresh = group(after);
  final changes = <(DateTime, String)>[];
  void add(Lesson l, String what) => changes.add((
    l.start,
    '${l.subject}, ${weekdaysShort[l.start.weekday - 1].toLowerCase()} '
        '${l.start.day.toString().padLeft(2, '0')}.'
        '${l.start.month.toString().padLeft(2, '0')}: $what',
  ));

  for (final k in {...old.keys, ...fresh.keys}) {
    final a = old[k] ?? const <Lesson>[];
    final b = fresh[k] ?? const <Lesson>[];
    for (var i = 0; i < a.length || i < b.length; i++) {
      final was = i < a.length ? a[i] : null;
      final cur = i < b.length ? b[i] : null;
      if (was != null && cur != null) {
        if (!relevant(was) && !relevant(cur)) continue;
        if (was.cancelled != cur.cancelled) {
          add(cur, cur.cancelled ? 'пару отменили' : 'пару вернули');
        } else if (was.start != cur.start || was.end != cur.end) {
          add(cur, 'перенесли с ${hm(was.start)} на ${hm(cur.start)}');
        } else if (was.room != cur.room) {
          add(cur, 'аудитория: ${cur.shortLocation}');
        }
      } else if (cur != null && relevant(cur) && !cur.cancelled) {
        add(cur, 'добавили пару в ${hm(cur.start)}');
      } else if (was != null && relevant(was) && !was.cancelled) {
        add(was, 'пару в ${hm(was.start)} убрали');
      }
    }
  }
  changes.sort((x, y) => x.$1.compareTo(y.$1));
  return [for (final c in changes) c.$2];
}
