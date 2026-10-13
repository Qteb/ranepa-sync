import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../format.dart';
import '../models.dart';

const appGroupId = 'group.com.qteb.ranepatimetable';
const iOSWidgetName = 'RanepaWidget';
const androidWidgetName = 'RanepaWidgetProvider';

/// Отдаёт виджету пары на две недели вперёд. Какие из них показать «сейчас»,
/// виджет решает сам по текущему времени, чтобы не зависеть от запуска приложения.
Future<void> updateHomeWidget(List<Lesson> lessons) async {
  final now = currentTime();
  final horizon = now.add(const Duration(days: 14));
  final items = [
    for (final l in lessons)
      if (!l.cancelled && l.end.isAfter(now) && l.start.isBefore(horizon))
        {
          's': l.start.millisecondsSinceEpoch ~/ 1000,
          'e': l.end.millisecondsSinceEpoch ~/ 1000,
          't': l.subject,
          'k': l.kind,
          'r': l.shortLocation,
        },
  ];
  await HomeWidget.saveWidgetData<String>('lessons', jsonEncode(items));
  await HomeWidget.saveWidgetData<double>(
    'nowShift',
    clockShift.inSeconds.toDouble(),
  );
  await _sendToWatch(jsonEncode(items));
  await HomeWidget.updateWidget(
    iOSName: iOSWidgetName,
    androidName: androidWidgetName,
  );
}

const _watch = MethodChannel('ranepa/watch');

/// Те же пары — на Apple Watch (ios/Runner/WatchBridge.swift). Без часов
/// или без приложения на них вызов ничего не делает.
Future<void> _sendToWatch(String lessons) async {
  if (!Platform.isIOS) return;
  try {
    await _watch.invokeMethod<void>('update', {
      'lessons': lessons,
      'nowShift': clockShift.inSeconds.toDouble(),
    });
  } on MissingPluginException {
    // Тесты и движки без плагина.
  } on PlatformException {
    // Часы недоступны — отправим при следующем обновлении.
  }
}
