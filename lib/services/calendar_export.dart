import 'package:eventide/eventide.dart';
import 'package:flutter/material.dart';

import '../models.dart';

const calendarName = 'РАНХиГС';
final _eventide = Eventide();

/// Пересобирает отдельный календарь «РАНХиГС» на телефоне за [from]..[to].
/// Календарь принадлежит только приложению, поэтому проще всего удалить старые
/// события в диапазоне и создать заново. Возвращает текст ошибки или null.
Future<String?> exportToCalendar(
  List<Lesson> lessons,
  DateTime from,
  DateTime to,
  int reminderMinutes,
) async {
  try {
    final calendars = await _eventide.retrieveCalendars();
    final calendarId =
        calendars.where((c) => c.title == calendarName).firstOrNull?.id ??
        (await _eventide.createCalendar(
          title: calendarName,
          color: const Color(0xFF8E1B2E),
        )).id;

    final existing = await _eventide.retrieveEvents(
      calendarId: calendarId,
      startDate: from,
      endDate: to,
    );
    for (final e in existing) {
      await _eventide.deleteEvent(eventId: e.id);
    }

    for (final l in lessons) {
      if (l.cancelled || l.start.isBefore(from) || !l.start.isBefore(to)) {
        continue;
      }
      await _eventide.createEvent(
        calendarId: calendarId,
        title: l.title,
        startDate: l.start,
        endDate: l.end,
        location: l.location,
        description: l.details,
        reminders: reminderMinutes > 0
            ? [Duration(minutes: reminderMinutes)]
            : null,
      );
    }
    return null;
  } on ETPermissionException {
    return 'Нет доступа к календарю: разреши его в настройках телефона';
  } on ETException catch (e) {
    return 'Не удалось выгрузить в календарь: ${e.message}';
  }
}

Future<void> removeCalendar() async {
  try {
    final calendars = await _eventide.retrieveCalendars();
    for (final c in calendars.where((c) => c.title == calendarName)) {
      await _eventide.deleteCalendar(calendarId: c.id);
    }
  } on ETException {
    // Нет доступа или календаря — удалять нечего.
  }
}
