import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart';
import 'models.dart';
import 'ranepa_client.dart';
import 'services/calendar_export.dart';
import 'services/home_widget_bridge.dart';
import 'services/notifications.dart';

/// Сколько недель качать начиная с понедельника текущей недели.
const fetchWeeks = 5;

/// Кэш старше этого обновляется автоматически при открытии приложения.
const staleAfter = Duration(hours: 3);

class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _loadCache();
  }

  final SharedPreferences _prefs;

  List<Lesson> lessons = [];
  String? group;
  DateTime? fetchedAt;
  DateTime? rangeStart;
  bool loading = false;
  String? error;

  bool get loggedIn => _prefs.getBool('loggedIn') ?? false;
  int get reminderMinutes => _prefs.getInt('reminderMinutes') ?? 0;
  bool get calendarExport => _prefs.getBool('calendarExport') ?? false;
  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];

  bool get isStale =>
      fetchedAt == null || DateTime.now().difference(fetchedAt!) > staleAfter;

  DateTime get rangeEnd => (rangeStart ?? mondayOf(DateTime.now())).add(
    const Duration(days: 7 * fetchWeeks),
  );

  List<Lesson> lessonsOn(DateTime day) =>
      lessons.where((l) => sameDay(l.start, day)).toList();

  void _loadCache() {
    final raw = _prefs.getString('days');
    if (raw != null) lessons = parseLessons(jsonDecode(raw) as List);
    group = _prefs.getString('group');
    final at = _prefs.getInt('fetchedAt');
    fetchedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    final start = _prefs.getInt('rangeStart');
    rangeStart = start == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(start);
  }

  /// Вызывается экраном входа, когда страница ЛК уже авторизована.
  Future<void> completeLogin(FetchResult result, DateTime monday) async {
    await _prefs.setBool('loggedIn', true);
    await _apply(result, monday);
  }

  Future<void> refresh() async {
    if (loading || !loggedIn) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final monday = mondayOf(DateTime.now());
      await _apply(await RanepaClient.refresh(monday, fetchWeeks), monday);
    } on NeedLoginException catch (e) {
      error = e.message;
      await _prefs.setBool('loggedIn', false);
    } catch (e) {
      error = e is RanepaException ? e.message : 'Не удалось обновить: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _apply(FetchResult result, DateTime monday) async {
    lessons = parseLessons(result.days);
    group = result.group ?? group;
    fetchedAt = DateTime.now();
    rangeStart = monday;
    error = null;
    await _prefs.setString('days', jsonEncode(result.days));
    if (group != null) await _prefs.setString('group', group!);
    await _prefs.setInt('fetchedAt', fetchedAt!.millisecondsSinceEpoch);
    await _prefs.setInt('rangeStart', monday.millisecondsSinceEpoch);
    notifyListeners();
    await _syncSideEffects();
  }

  /// Напоминания, календарь телефона и виджет — всё строится из кэша.
  Future<void> _syncSideEffects() async {
    try {
      await scheduleReminders(lessons, reminderMinutes);
      await updateHomeWidget(lessons);
      if (calendarExport) {
        final err = await exportToCalendar(
          lessons,
          rangeStart ?? mondayOf(DateTime.now()),
          rangeEnd,
          reminderMinutes,
        );
        if (err != null) error = err;
      }
    } catch (e) {
      error = 'Ошибка синхронизации: $e';
    }
    notifyListeners();
  }

  Future<void> setReminderMinutes(int minutes) async {
    if (minutes > 0 && !await requestNotificationPermission()) {
      error = 'Разреши уведомления в настройках телефона';
      notifyListeners();
      return;
    }
    await _prefs.setInt('reminderMinutes', minutes);
    notifyListeners();
    await _syncSideEffects();
  }

  Future<void> setCalendarExport(bool enabled) async {
    await _prefs.setBool('calendarExport', enabled);
    notifyListeners();
    if (enabled) {
      await _syncSideEffects();
    } else {
      await removeCalendar();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }

  Future<void> logout() async {
    // Сессию WebView чистим до перехода на экран входа, иначе страница ЛК
    // подхватит старые токены и снова «войдёт». Остальное — по возможности:
    // ошибка в одном шаге не должна оставлять пользователя залогиненным.
    for (final step in [
      RanepaClient.logout,
      () => scheduleReminders(const [], 0),
      if (calendarExport) removeCalendar,
      () => updateHomeWidget(const []),
    ]) {
      try {
        await step();
      } catch (e) {
        debugPrint('logout: $e');
      }
    }
    for (final key in [
      'loggedIn',
      'days',
      'group',
      'fetchedAt',
      'rangeStart',
    ]) {
      await _prefs.remove(key);
    }
    lessons = [];
    group = null;
    fetchedAt = null;
    rangeStart = null;
    error = null;
    notifyListeners();
  }
}
