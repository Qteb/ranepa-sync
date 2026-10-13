import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ranepa_sync/services/sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

// Проверяем только решения «идти или нет»: все случаи ниже не доходят до ЛК.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  // Вторник, 13 октября 2026.
  final tuesday = DateTime(2026, 10, 13, 12);
  final ms = tuesday.millisecondsSinceEpoch;

  Future<SharedPreferences> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({
      // Конфиг уже проверен сегодня — в сеть за ним не ходим.
      'remoteConfigCheckedAt': DateTime.now().millisecondsSinceEpoch,
      'remoteConfig': '{"sync": true}',
      'lastFullAt': ms - 3600 * 1000,
      ...values,
    });
    return SharedPreferences.getInstance();
  }

  Map<String, Object> lessonOn(DateTime day) => {
    'days': jsonEncode([
      {
        'date': '${day.toIso8601String().substring(0, 10)}T00:00:00',
        'discs': [
          {
            'start_date': '${day.toIso8601String().substring(0, 10)}T10:00:00',
            'end_date': '${day.toIso8601String().substring(0, 10)}T11:30:00',
          },
        ],
      },
    ]),
  };

  Future<SkipReason?> run(
    SyncTrigger trigger,
    DateTime now, [
    Map<String, Object> values = const {},
  ]) async =>
      (await syncSchedule(await prefs(values), trigger, now: now)).skipped;

  test('kill switch останавливает любое обновление', () async {
    final skip = await run(SyncTrigger.manual, tuesday, {
      'remoteConfig': '{"sync": false, "message": "Пауза"}',
    });
    expect(skip, SkipReason.paused);
  });

  test('пауза после ошибки сервера', () async {
    final skip = await run(SyncTrigger.manual, tuesday, {
      'backoffUntil': ms + 8 * 3600 * 1000,
    });
    expect(skip, SkipReason.backoff);
  });

  test('ночью фон не ходит в ЛК', () async {
    expect(
      await run(SyncTrigger.background, DateTime(2026, 10, 13, 3)),
      SkipReason.quietHours,
    );
  });

  test('фон не чаще интервала из конфига', () async {
    final skip = await run(SyncTrigger.background, tuesday, {
      'lastAttemptAt': ms - 3 * 3600 * 1000,
    });
    expect(skip, SkipReason.tooSoon);
  });

  test('в воскресенье — только ежедневная полная загрузка', () async {
    final sunday = DateTime(2026, 10, 18, 12);
    final skip = await run(SyncTrigger.background, sunday, {
      'lastFullAt': sunday.millisecondsSinceEpoch - 3600 * 1000,
      ...lessonOn(DateTime(2026, 10, 19)),
    });
    expect(skip, SkipReason.notNeeded);
  });

  test('на каникулах — только ежедневная полная загрузка', () async {
    expect(await run(SyncTrigger.background, tuesday), SkipReason.notNeeded);
  });

  test('ручное обновление сразу после прошлого не ходит в ЛК', () async {
    final skip = await run(SyncTrigger.manual, tuesday, {
      'fetchedAt': ms - 30 * 1000,
    });
    expect(skip, SkipReason.tooSoon);
  });

  test('при открытии свежие данные не обновляются', () async {
    final skip = await run(SyncTrigger.open, tuesday, {
      'fetchedAt': ms - 3600 * 1000,
    });
    expect(skip, SkipReason.notNeeded);
  });
}
