import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../format.dart';
import '../models.dart';

const _live = MethodChannel('ranepa/live');

/// Пара на экране блокировки и в Dynamic Island
/// (ios/Runner/LiveActivityBridge.swift). Сюда приходят оставшиеся сегодня
/// пары: нативная часть запускает, обновляет или закрывает активность.
/// Запустить её iOS даёт только из открытого приложения, поэтому вызов
/// есть и при открытии приложения, не только после обновления.
Future<void> updateLiveActivity(
  List<Lesson> lessons, {
  required bool enabled,
}) async {
  if (!Platform.isIOS) return;
  final now = currentTime();
  // Таймеры активности идут по настоящим часам — убираем сдвиг скриншотов.
  int real(DateTime t) => t.subtract(clockShift).millisecondsSinceEpoch ~/ 1000;
  final items = [
    for (final l in lessons)
      if (!l.cancelled && sameDay(l.start, now) && l.end.isAfter(now))
        {
          's': real(l.start),
          'e': real(l.end),
          't': l.subject,
          'k': l.kind,
          'r': l.shortLocation,
          'R': l.location,
        },
  ];
  try {
    await _live.invokeMethod<void>('update', {
      'lessons': jsonEncode(items),
      'enabled': enabled,
    });
  } on MissingPluginException {
    // Тесты и движки без плагина.
  } on PlatformException {
    // Live Activity недоступна — ничего страшного.
  }
}
