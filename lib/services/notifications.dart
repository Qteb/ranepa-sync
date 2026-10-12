import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../format.dart';
import '../models.dart';

final _plugin = FlutterLocalNotificationsPlugin();

// iOS держит не больше 64 запланированных уведомлений на приложение.
const _maxScheduled = 60;

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
  await _plugin.cancelAll();
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
