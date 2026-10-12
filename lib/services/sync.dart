import 'dart:convert';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../models.dart';
import '../ranepa_client.dart';
import 'calendar_export.dart';
import 'changes.dart';
import 'home_widget_bridge.dart';
import 'notifications.dart';

/// Сколько недель качать начиная с понедельника текущей недели.
const fetchWeeks = 5;

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
  ];
}

class SyncResult {
  SyncResult({required this.changes, this.sideEffectError});

  /// Изменения в ближайшие дни по сравнению с прошлой загрузкой.
  final List<String> changes;
  final String? sideEffectError;
}

List<Lesson> cachedLessons(SharedPreferences prefs) {
  final raw = prefs.getString(Keys.days);
  return raw == null ? [] : parseLessons(jsonDecode(raw) as List);
}

/// Скачивает расписание через скрытый WebView и применяет его.
Future<SyncResult> syncSchedule(SharedPreferences prefs) async {
  final monday = mondayOf(DateTime.now());
  return saveSchedule(
    prefs,
    await RanepaClient.refresh(
      monday,
      fetchWeeks,
      withPhoto: _photoStale(prefs),
    ),
    monday,
  );
}

/// Фото весит под мегабайт — качаем его при входе и потом раз в неделю.
const _photoMaxAge = Duration(days: 7);

bool _photoStale(SharedPreferences prefs) {
  final at = prefs.getInt(Keys.photoFetchedAt);
  return at == null ||
      DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) >
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
Future<SyncResult> saveSchedule(
  SharedPreferences prefs,
  FetchResult result,
  DateTime monday,
) async {
  final hadCache = prefs.containsKey(Keys.days);
  final before = cachedLessons(prefs);
  final after = parseLessons(result.days);

  await prefs.setString(Keys.days, jsonEncode(result.days));
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
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Битое фото — останутся инициалы, попробуем в следующий раз.
    }
  }
  await prefs.setInt(Keys.fetchedAt, DateTime.now().millisecondsSinceEpoch);
  await prefs.setInt(Keys.rangeStart, monday.millisecondsSinceEpoch);
  await prefs.setBool(Keys.loggedIn, true);
  await prefs.remove(Keys.sessionExpiredNotified);

  return SyncResult(
    changes: hadCache
        ? describeChanges(before, after, now: DateTime.now())
        : const [],
    sideEffectError: await applySideEffects(prefs, after),
  );
}

/// Напоминания, виджет и календарь телефона строятся из расписания.
/// Возвращает текст ошибки или null.
Future<String?> applySideEffects(
  SharedPreferences prefs,
  List<Lesson> lessons,
) async {
  final minutes = prefs.getInt(Keys.reminderMinutes) ?? 0;
  try {
    await scheduleReminders(lessons, minutes);
    // После scheduleReminders: тот снимает все запланированные уведомления.
    final fetchedAt = prefs.getInt(Keys.fetchedAt);
    if (fetchedAt != null) {
      await scheduleKeepAlive(DateTime.fromMillisecondsSinceEpoch(fetchedAt));
    }
    await updateHomeWidget(lessons);
    if (prefs.getBool(Keys.calendarExport) ?? false) {
      final start = prefs.getInt(Keys.rangeStart);
      final from = start == null
          ? mondayOf(DateTime.now())
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
