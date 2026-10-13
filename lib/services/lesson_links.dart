import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../format.dart';

/// Открыть приложение на конкретной паре: нажатие на Live Activity, виджет
/// (ссылка ranepa://lesson?start=…, ios/Runner/LinkBridge.swift) или
/// напоминание о паре. Главный экран слушает [pendingLesson], листает к дню
/// пары и открывает её карточку.
final pendingLesson = ValueNotifier<DateTime?>(null);

const _links = MethodChannel('ranepa/links');

Future<void> initLessonLinks() async {
  _links.setMethodCallHandler((call) async {
    if (call.method == 'open') _openUrl(call.arguments as String?);
  });
  try {
    _openUrl(await _links.invokeMethod<String>('initial'));
  } on MissingPluginException {
    // Android и тесты: ссылок нет.
  }
}

/// ranepa://lesson?start=<секунды по настоящим часам>.
void _openUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  final start = int.tryParse(uri?.queryParameters['start'] ?? '');
  if (uri?.host != 'lesson' || start == null) return;
  // В сборке для скриншотов часы приложения сдвинуты.
  pendingLesson.value = DateTime.fromMillisecondsSinceEpoch(start * 1000)
      .add(clockShift);
}

/// Полезная нагрузка напоминания: начало пары во времени приложения.
String lessonPayload(DateTime start) =>
    'lesson:${start.millisecondsSinceEpoch}';

void openLessonPayload(String? payload) {
  if (payload == null || !payload.startsWith('lesson:')) return;
  final ms = int.tryParse(payload.substring(7));
  if (ms != null) pendingLesson.value = DateTime.fromMillisecondsSinceEpoch(ms);
}
