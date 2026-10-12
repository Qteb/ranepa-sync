import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:workmanager/workmanager.dart';

import '../ranepa_client.dart';
import 'home_widget_bridge.dart';
import 'notifications.dart';
import 'sync.dart';

/// Должен совпадать с BGTaskSchedulerPermittedIdentifiers в Info.plist и
/// с регистрацией в AppDelegate.swift.
const backgroundTaskId = 'com.qteb.ranepaTimetable.refresh';

/// Раз в 4 часа: refresh-токен ЛК живёт сутки и продлевается при каждом
/// обновлении, так что сессия с запасом не истекает. На iOS это лишь
/// пожелание — реальное время запуска выбирает система.
const backgroundInterval = Duration(hours: 4);

Future<void> initBackground() => Workmanager().initialize(backgroundDispatcher);

Future<void> scheduleBackgroundRefresh() => Workmanager().registerPeriodicTask(
  backgroundTaskId,
  backgroundTaskId,
  frequency: backgroundInterval,
  initialDelay: backgroundInterval,
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
);

Future<void> cancelBackgroundRefresh() => Workmanager().cancelAll();

/// Точка входа фоновой задачи: отдельный изолят без UI.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    tzdata.initializeTimeZones();
    await HomeWidget.setAppGroupId(appGroupId);
    await initNotifications();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!(prefs.getBool(Keys.loggedIn) ?? false)) return true;

    String outcome;
    try {
      final result = await syncSchedule(prefs);
      await showScheduleChanges(result.changes);
      outcome = result.changes.isEmpty
          ? 'без изменений'
          : 'изменений: ${result.changes.length}';
    } on NeedLoginException {
      await prefs.setBool(Keys.loggedIn, false);
      await cancelKeepAlive();
      if (!(prefs.getBool(Keys.sessionExpiredNotified) ?? false)) {
        await showSessionExpired();
        await prefs.setBool(Keys.sessionExpiredNotified, true);
      }
      outcome = 'сессия истекла';
    } catch (e) {
      outcome = 'ошибка: $e';
    }
    await prefs.setInt(
      Keys.lastBackgroundRun,
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(Keys.lastBackgroundResult, outcome);
    // true даже при ошибке: повтор по расписанию через 4 часа, без лавины
    // ретраев WorkManager.
    return true;
  });
}

/// Отладка: сдвигает в кэше ближайшую будущую пару на час раньше, чтобы
/// следующее обновление нашло «перенос» и прислало уведомление.
Future<void> debugShiftNextLesson() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(Keys.days);
  if (raw == null) return;
  final days = jsonDecode(raw) as List;
  final now = DateTime.now();
  for (final day in days) {
    for (final disc in (day['discs'] as List? ?? [])) {
      final start = DateTime.parse(disc['start_date'] as String);
      if (start.isAfter(now)) {
        String shift(String v) =>
            DateTime.parse(v)
                .subtract(const Duration(hours: 1))
                .toIso8601String()
                .substring(0, 19);
        disc['start_date'] = shift(disc['start_date'] as String);
        disc['end_date'] = shift(disc['end_date'] as String);
        await prefs.setString(Keys.days, jsonEncode(days));
        return;
      }
    }
  }
}
