import 'dart:convert';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../models.dart';
import '../ranepa_client.dart';
import 'calendar_export.dart';
import 'changes.dart';
import 'demo.dart';
import 'home_widget_bridge.dart';
import 'live_activity.dart';
import 'notifications.dart';
import 'remote_config.dart';

/// Полная загрузка: месяц вперёд, то есть текущая неделя и ещё 4.
/// Делается при входе и первым обновлением за день.
const fetchWeeks = 5;

/// Напоминание о паре по умолчанию, пока пользователь не выбрал своё.
const defaultReminderMinutes = 15;

/// Данные старше этого обновляются при открытии приложения.
const staleAfter = Duration(hours: 4);

/// При открытии не пытаемся чаще, даже если прошлая попытка не удалась.
const _openRetryAfter = Duration(minutes: 15);

/// Ночью фон в ЛК не ходит.
const _quietUntilHour = 7;

/// Допуск к интервалу фона: WorkManager запускает задачу с разбросом.
const _intervalSlack = Duration(minutes: 15);

/// Пауза после ответа 429/5xx: 8 → 16 → 24 часа.
const _backoffBase = Duration(hours: 4);
const _backoffMax = Duration(hours: 24);

/// Ключи в SharedPreferences. Их читают и приложение, и фоновая задача
/// (в отдельном изоляте), поэтому всё состояние живёт только здесь.
abstract final class Keys {
  static const loggedIn = 'loggedIn';
  static const days = 'days';
  static const group = 'group';
  static const fetchedAt = 'fetchedAt';
  static const rangeStart = 'rangeStart';
  static const reminderMinutes = 'reminderMinutes';
  static const calendarExport = 'calendarExport';
  static const sessionExpiredNotified = 'sessionExpiredNotified';
  static const lastBackgroundRun = 'lastBackgroundRun';
  static const lastBackgroundResult = 'lastBackgroundResult';
  static const fullName = 'fullName';
  static const program = 'program';
  static const photo = 'photo';
  static const photoFetchedAt = 'photoFetchedAt';
  static const lastFullAt = 'lastFullAt';
  static const lastAttemptAt = 'lastAttemptAt';
  static const backoffUntil = 'backoffUntil';
  static const backoffFailures = 'backoffFailures';
  static const liveActivity = 'liveActivity';
  static const demo = 'demo';
  static const demoRevision = 'demoRevision';
  static const demoShift = 'demoShift';

  /// Всё, что относится к сессии и удаляется при выходе.
  static const session = [
    loggedIn,
    days,
    group,
    fetchedAt,
    rangeStart,
    sessionExpiredNotified,
    lastBackgroundRun,
    lastBackgroundResult,
    fullName,
    program,
    photo,
    photoFetchedAt,
    lastFullAt,
    lastAttemptAt,
    backoffUntil,
    backoffFailures,
    demo,
    demoRevision,
    demoShift,
  ];
}

class SyncResult {
  SyncResult({required this.changes, this.sideEffectError}) : skipped = null;

  SyncResult.skipped(SkipReason this.skipped)
    : changes = const [],
      sideEffectError = null;

  /// Изменения в ближайшие дни по сравнению с прошлой загрузкой.
  final List<String> changes;
  final String? sideEffectError;

  /// Почему в ЛК не ходили; null — обновление было.
  final SkipReason? skipped;
}

enum SkipReason {
  /// Обновление выключено удалённым конфигом.
  paused,

  /// Пауза после ошибки сервера.
  backoff,

  /// Ночь — фон не ходит в ЛК.
  quietHours,

  /// С прошлого обновления прошло слишком мало времени.
  tooSoon,

  /// Обновлять нечего: воскресенье, каникулы или данные свежие.
  notNeeded,
}

enum SyncTrigger {
  background,
  open,
  manual,

  /// Кнопка в отладочной сборке: без проверок интервалов и тихих часов.
  debug,
}

List<Lesson> cachedLessons(SharedPreferences prefs) {
  final raw = prefs.getString(Keys.days);
  return raw == null ? [] : parseLessons(jsonDecode(raw) as List);
}

DateTime? _time(SharedPreferences prefs, String key) {
  final at = prefs.getInt(key);
  return at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
}

Duration _since(SharedPreferences prefs, String key, DateTime now) {
  final at = _time(prefs, key);
  return at == null ? const Duration(days: 365) : now.difference(at);
}

/// Обновление стоит на паузе: выключено конфигом или после ошибки сервера.
bool syncPausedFor(SharedPreferences prefs) =>
    !RemoteConfig.cached(prefs).sync ||
    (_time(prefs, Keys.backoffUntil)?.isAfter(currentTime()) ?? false);

/// Решает, идти ли в ЛК и сколько грузить, и загружает расписание через
/// скрытый WebView. Месяц — первым обновлением за день, иначе текущую
/// неделю (с пятницы — и следующую).
Future<SyncResult> syncSchedule(
  SharedPreferences prefs,
  SyncTrigger trigger, {
  DateTime? now,
}) async {
  if (isDemo(prefs)) return syncDemo(prefs, trigger);
  final config = await RemoteConfig.load(prefs);
  now ??= currentTime();
  if (!config.sync) return SyncResult.skipped(SkipReason.paused);
  if (_time(prefs, Keys.backoffUntil)?.isAfter(now) ?? false) {
    return SyncResult.skipped(SkipReason.backoff);
  }
  final lastFull = _time(prefs, Keys.lastFullAt);
  final full = lastFull == null || !sameDay(lastFull, now);

  switch (trigger) {
    case SyncTrigger.background:
      if (now.hour < _quietUntilHour) {
        return SyncResult.skipped(SkipReason.quietHours);
      }
      if (_since(prefs, Keys.lastAttemptAt, now) <
          config.minInterval - _intervalSlack) {
        return SyncResult.skipped(SkipReason.tooSoon);
      }
      // В воскресенье и на каникулах — только ежедневная полная загрузка.
      if (!full &&
          (now.weekday == DateTime.sunday || !_lessonsSoon(prefs, now))) {
        return SyncResult.skipped(SkipReason.notNeeded);
      }
    case SyncTrigger.open:
      if (_since(prefs, Keys.fetchedAt, now) < staleAfter ||
          _since(prefs, Keys.lastAttemptAt, now) < _openRetryAfter) {
        return SyncResult.skipped(SkipReason.notNeeded);
      }
    case SyncTrigger.manual:
      if (_since(prefs, Keys.fetchedAt, now) < config.manualCooldown) {
        return SyncResult.skipped(SkipReason.tooSoon);
      }
    case SyncTrigger.debug:
      break;
  }

  await prefs.setInt(Keys.lastAttemptAt, now.millisecondsSinceEpoch);
  final monday = mondayOf(now);
  final weeks = full ? fetchWeeks : (now.weekday >= DateTime.friday ? 2 : 1);
  final FetchResult result;
  try {
    result = await RanepaClient.refresh(
      monday,
      weeks,
      withProfile: full,
      withPhoto: full && _photoStale(prefs),
    );
  } on ServerBusyException catch (e) {
    await _startBackoff(prefs, e);
    rethrow;
  }
  await prefs.remove(Keys.backoffUntil);
  await prefs.remove(Keys.backoffFailures);
  return saveSchedule(prefs, result, monday, weeks: weeks);
}

/// Есть ли пары в ближайшие 14 дней — если нет, это каникулы.
bool _lessonsSoon(SharedPreferences prefs, DateTime now) {
  final until = now.add(const Duration(days: 14));
  return cachedLessons(prefs)
      .any((l) => l.end.isAfter(now) && l.start.isBefore(until));
}

Future<void> _startBackoff(
  SharedPreferences prefs,
  ServerBusyException e,
) async {
  final failures = (prefs.getInt(Keys.backoffFailures) ?? 0) + 1;
  var pause = _backoffBase * (1 << failures);
  if (pause > _backoffMax) pause = _backoffMax;
  final retryAfter = Duration(seconds: e.retryAfterSeconds ?? 0);
  if (retryAfter > pause) pause = retryAfter;
  await prefs.setInt(Keys.backoffFailures, failures);
  await prefs.setInt(
    Keys.backoffUntil,
    currentTime().add(pause).millisecondsSinceEpoch,
  );
}

/// Фото весит под мегабайт — качаем его при входе и потом раз в неделю.
const _photoMaxAge = Duration(days: 7);

bool _photoStale(SharedPreferences prefs) {
  final at = prefs.getInt(Keys.photoFetchedAt);
  return at == null ||
      currentTime().difference(DateTime.fromMillisecondsSinceEpoch(at)) >
          _photoMaxAge;
}

/// data:image/png;base64,… → PNG 256×256 в base64 (несколько десятков КБ).
Future<String?> _shrinkPhoto(String dataUrl) async {
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  final codec = await ui.instantiateImageCodec(
    // Сайт режет base64 переносами строк каждые 64 символа.
    base64Decode(dataUrl.substring(comma + 1).replaceAll(RegExp(r'\s'), '')),
    targetWidth: 256,
  );
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return png == null ? null : base64Encode(png.buffer.asUint8List());
}

/// Сохраняет загруженное расписание, сравнивает с прошлым и обновляет
/// напоминания, виджет и календарь.
///
/// Полная загрузка ([weeks] == [fetchWeeks]) заменяет всё расписание,
/// лёгкая — только загруженные недели.
Future<SyncResult> saveSchedule(
  SharedPreferences prefs,
  FetchResult result,
  DateTime monday, {
  int weeks = fetchWeeks,
}) async {
  final full = weeks >= fetchWeeks;
  final hadCache = prefs.containsKey(Keys.days);
  final before = cachedLessons(prefs);
  final days = full ? result.days : _merge(prefs, result.days, monday, weeks);
  final after = parseLessons(days);

  await prefs.setString(Keys.days, jsonEncode(days));
  if (result.group != null) await prefs.setString(Keys.group, result.group!);
  if (result.program != null) {
    await prefs.setString(Keys.program, result.program!);
  }
  if (result.fullName != null && result.fullName!.isNotEmpty) {
    await prefs.setString(Keys.fullName, result.fullName!);
  }
  if (result.photo != null) {
    try {
      final photo = result.photo!.isEmpty
          ? null
          : await _shrinkPhoto(result.photo!);
      photo == null
          ? await prefs.remove(Keys.photo)
          : await prefs.setString(Keys.photo, photo);
      await prefs.setInt(
        Keys.photoFetchedAt,
        currentTime().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Битое фото — останутся инициалы, попробуем в следующий раз.
    }
  }
  await prefs.setInt(Keys.fetchedAt, currentTime().millisecondsSinceEpoch);
  if (full) {
    await prefs.setInt(Keys.rangeStart, monday.millisecondsSinceEpoch);
    await prefs.setInt(Keys.lastFullAt, currentTime().millisecondsSinceEpoch);
  }
  await prefs.setBool(Keys.loggedIn, true);
  await prefs.remove(Keys.sessionExpiredNotified);

  return SyncResult(
    changes: hadCache
        ? describeChanges(before, after, now: currentTime())
        : const [],
    sideEffectError: await applySideEffects(prefs, after),
  );
}

/// Сохранённые дни вне загруженных недель + свежие дни.
List<dynamic> _merge(
  SharedPreferences prefs,
  List<dynamic> fresh,
  DateTime monday,
  int weeks,
) {
  final end = monday.add(Duration(days: 7 * weeks));
  final raw = prefs.getString(Keys.days);
  final kept = raw == null
      ? const []
      : (jsonDecode(raw) as List).where((day) {
          final date = DateTime.tryParse('${day['date']}');
          return date == null || date.isBefore(monday) || !date.isBefore(end);
        });
  return [...kept, ...fresh];
}

/// Напоминания, виджет и календарь телефона строятся из расписания.
/// Возвращает текст ошибки или null.
Future<String?> applySideEffects(
  SharedPreferences prefs,
  List<Lesson> lessons,
) async {
  final minutes = prefs.getInt(Keys.reminderMinutes) ?? defaultReminderMinutes;
  try {
    await scheduleReminders(lessons, minutes);
    // После scheduleReminders: тот снимает все запланированные уведомления.
    final fetchedAt = prefs.getInt(Keys.fetchedAt);
    // В демо сессии ЛК нет — напоминать о ней незачем.
    if (fetchedAt != null && !isDemo(prefs)) {
      await scheduleKeepAlive(DateTime.fromMillisecondsSinceEpoch(fetchedAt));
    }
    await updateHomeWidget(lessons);
    await updateLiveActivity(
      lessons,
      enabled: prefs.getBool(Keys.liveActivity) ?? true,
    );
    if (prefs.getBool(Keys.calendarExport) ?? false) {
      final start = prefs.getInt(Keys.rangeStart);
      final from = start == null
          ? mondayOf(currentTime())
          : DateTime.fromMillisecondsSinceEpoch(start);
      return await exportToCalendar(
        lessons,
        from,
        from.add(const Duration(days: 7 * fetchWeeks)),
        minutes,
      );
    }
    return null;
  } catch (e) {
    return 'Ошибка синхронизации: $e';
  }
}
