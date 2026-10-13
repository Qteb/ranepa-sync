import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart';
import 'models.dart';
import 'ranepa_client.dart';
import 'services/background.dart';
import 'services/calendar_export.dart';
import 'services/demo.dart';
import 'services/home_widget_bridge.dart';
import 'services/notifications.dart';
import 'services/remote_config.dart';
import 'services/sync.dart';

export 'services/sync.dart'
    show SyncTrigger, defaultReminderMinutes, fetchWeeks;

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

  /// Изменения, найденные последним ручным обновлением: показываются
  /// на главном экране и сбрасываются после показа.
  List<String> pendingChanges = const [];

  /// Разрешены ли уведомления в настройках телефона; null — ещё не знаем.
  bool? notificationsEnabled;

  bool get loggedIn => _prefs.getBool(Keys.loggedIn) ?? false;

  /// Выдуманный студент вместо ЛК, см. services/demo.dart.
  bool get demo => isDemo(_prefs);
  int get reminderMinutes =>
      _prefs.getInt(Keys.reminderMinutes) ?? defaultReminderMinutes;
  bool get calendarExport => _prefs.getBool(Keys.calendarExport) ?? false;
  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];

  DateTime? get lastBackgroundRun {
    final at = _prefs.getInt(Keys.lastBackgroundRun);
    return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  String? get fullName => _prefs.getString(Keys.fullName);
  String? get program => _prefs.getString(Keys.program);

  Uint8List? _photo;
  String? _photoSource;

  /// Уменьшенное фото из ЛК; декодируется один раз на каждое новое фото.
  Uint8List? get photo {
    final raw = _prefs.getString(Keys.photo);
    if (raw != _photoSource) {
      _photoSource = raw;
      _photo = raw == null ? null : base64Decode(raw);
    }
    return _photo;
  }

  String? get lastBackgroundResult =>
      _prefs.getString(Keys.lastBackgroundResult);

  /// Обновление остановлено конфигом или стоит на паузе после ошибки ЛК.
  bool get syncPaused => syncPausedFor(_prefs);

  /// Пояснение из удалённого конфига, если обновление остановлено.
  String? get pausedMessage => RemoteConfig.cached(_prefs).message;

  DateTime get rangeEnd => (rangeStart ?? mondayOf(currentTime())).add(
    const Duration(days: 7 * fetchWeeks),
  );

  List<Lesson> lessonsOn(DateTime day) =>
      lessons.where((l) => sameDay(l.start, day)).toList();

  void _loadCache() {
    lessons = cachedLessons(_prefs);
    group = _prefs.getString(Keys.group);
    final at = _prefs.getInt(Keys.fetchedAt);
    fetchedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    final start = _prefs.getInt(Keys.rangeStart);
    rangeStart = start == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(start);
    if (!loggedIn && (_prefs.getBool(Keys.sessionExpiredNotified) ?? false)) {
      error = 'Сессия ЛК истекла, войди заново';
    }
  }

  /// Фоновая задача пишет в SharedPreferences из другого изолята —
  /// при возвращении в приложение перечитываем.
  Future<void> reloadFromDisk() async {
    await _prefs.reload();
    _loadCache();
    notifyListeners();
  }

  /// Вызывается экраном входа, когда страница ЛК уже авторизована.
  Future<void> completeLogin(FetchResult result, DateTime monday) async {
    error = null;
    final sync = await saveSchedule(_prefs, result, monday);
    _loadCache();
    error = sync.sideEffectError;
    notifyListeners();
    if (!demo) await scheduleBackgroundRefresh();
    // Разрешение нужно и для уведомлений об изменениях, не только для напоминаний.
    await checkNotifications(request: true);
  }

  /// Вход в демо долгим нажатием на логотип стартового экрана.
  Future<void> startDemo() async {
    await _prefs.setBool(Keys.demo, true);
    await completeLogin(await demoFetch(_prefs), mondayOf(currentTime()));
  }

  /// Перечитывает разрешение на уведомления (пользователь мог поменять его в
  /// настройках). С [request] — показывает системный запрос, если ещё не
  /// спрашивали.
  Future<void> checkNotifications({bool request = false}) async {
    final allowed = request
        ? await requestNotificationPermission()
        : await notificationsAllowed();
    if (allowed == notificationsEnabled) return;
    final wasOff = notificationsEnabled == false;
    notificationsEnabled = allowed;
    notifyListeners();
    // Включили в настройках — сразу ставим напоминания заново.
    if (allowed && wasOff && loggedIn) await _resync();
  }

  /// [SyncTrigger.open] — при открытии, если данные устарели;
  /// [SyncTrigger.manual] — жестом «потянуть вниз».
  Future<void> refresh([SyncTrigger trigger = SyncTrigger.manual]) async {
    if (loading || !loggedIn) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final sync = await syncSchedule(_prefs, trigger);
      // Данные только что обновлялись — запрос не нужен, но жест должен
      // выглядеть как обычное обновление.
      if (sync.skipped == SkipReason.tooSoon) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      pendingChanges = sync.changes;
      error = sync.sideEffectError;
      if (sync.skipped == SkipReason.paused && trigger == SyncTrigger.manual) {
        error = pausedMessage;
      }
    } on NeedLoginException catch (e) {
      await _prefs.setBool(Keys.loggedIn, false);
      await cancelBackgroundRefresh();
      await cancelKeepAlive();
      error = e.message;
    } catch (e) {
      error = e is RanepaException ? e.message : 'Не удалось обновить: $e';
    } finally {
      _loadCache();
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _resync() async {
    error = await applySideEffects(_prefs, lessons);
    notifyListeners();
  }

  Future<void> setReminderMinutes(int minutes) async {
    if (minutes > 0 && !await requestNotificationPermission()) {
      error = 'Разреши уведомления в настройках телефона';
      notifyListeners();
      return;
    }
    await _prefs.setInt(Keys.reminderMinutes, minutes);
    notifyListeners();
    await _resync();
  }

  Future<void> setCalendarExport(bool enabled) async {
    await _prefs.setBool(Keys.calendarExport, enabled);
    notifyListeners();
    if (enabled) {
      await _resync();
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
      cancelBackgroundRefresh,
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
    for (final key in Keys.session) {
      await _prefs.remove(key);
    }
    lessons = [];
    group = null;
    fetchedAt = null;
    rangeStart = null;
    error = null;
    pendingChanges = const [];
    notifyListeners();
  }
}
