import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../format.dart';
import '../models.dart';

final _plugin = FlutterLocalNotificationsPlugin();

// iOS держит не больше 64 запланированных уведомлений на приложение.
const _maxScheduled = 60;

// Id напоминаний — 0..59, у служебных уведомлений свои.
const _changesId = 1000;
const _sessionId = 1001;
const _keepAliveId = 1002;

/// Через сколько после последнего обновления напомнить открыть приложение.
/// Refresh-токен ЛК живёт 24 часа — нужен запас.
const keepAliveAfter = Duration(hours: 20);

const _infoDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'schedule',
    'Изменения в расписании',
    importance: Importance.high,
    priority: Priority.high,
  ),
  iOS: DarwinNotificationDetails(),
);

Future<void> initNotifications() async {
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
}

Future<bool> requestNotificationPermission() async {
  final ios = _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
  if (ios != null) {
    return await ios.requestPermissions(alert: true, sound: true) ?? false;
  }
  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (android != null) {
    return await android.requestNotificationsPermission() ?? false;
  }
  return false;
}

/// Перепланирует напоминания: [minutes] до начала каждой пары, 0 — выключено.
Future<void> scheduleReminders(List<Lesson> lessons, int minutes) async {
  // Только запланированные: уже показанное «расписание изменилось» не трогаем.
  await _plugin.cancelAllPendingNotifications();
  if (minutes <= 0) return;

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'lessons',
      'Напоминания о парах',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );
  final now = DateTime.now();
  final upcoming = lessons
      .where((l) => !l.cancelled)
      .map((l) => (l, l.start.subtract(Duration(minutes: minutes))))
      .where((e) => e.$2.isAfter(now))
      .take(_maxScheduled);

  var id = 0;
  for (final (lesson, at) in upcoming) {
    await _plugin.zonedSchedule(
      id: id++,
      title: lesson.title,
      body: '${timeRange(lesson)} · ${lesson.location}',
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

/// Одно уведомление на все изменения: первые строки и «и ещё N».
Future<void> showScheduleChanges(List<String> changes) async {
  if (changes.isEmpty) return;
  const shown = 3;
  final body = [
    ...changes.take(shown),
    if (changes.length > shown) 'и ещё ${changes.length - shown}',
  ].join('\n');
  await _plugin.show(
    id: _changesId,
    title: changes.length == 1
        ? 'Изменение в расписании'
        : 'Изменения в расписании',
    body: body,
    notificationDetails: _infoDetails,
  );
}

Future<void> showSessionExpired() => _plugin.show(
  id: _sessionId,
  title: 'Расписание не обновляется',
  body: 'Сессия ЛК истекла. Открой приложение и войди заново.',
  notificationDetails: _infoDetails,
);

/// «Таймер мёртвой руки»: каждое успешное обновление переносит уведомление
/// на [keepAliveAfter] вперёд. Пока фоновое обновление работает, оно не
/// срабатывает; если приложение смахнули и iOS перестала его будить —
/// пользователь узнает об этом до того, как истечёт сессия ЛК.
Future<void> scheduleKeepAlive(DateTime lastSync) async {
  await _plugin.cancel(id: _keepAliveId);
  final at = lastSync.add(keepAliveAfter);
  if (!at.isAfter(DateTime.now())) return;
  await _plugin.zonedSchedule(
    id: _keepAliveId,
    title: 'Открой приложение',
    body:
        'Расписание не обновлялось почти сутки. Открой приложение, '
        'иначе придётся заново входить в ЛК.',
    scheduledDate: tz.TZDateTime.from(at, tz.UTC),
    notificationDetails: _infoDetails,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

Future<void> cancelKeepAlive() => _plugin.cancel(id: _keepAliveId);
