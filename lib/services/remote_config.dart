import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Удалённый выключатель: файл в ветке `config` репозитория. Через него можно
/// остановить обращения к ЛК или сделать их реже без новой сборки.
/// jsDelivr — запасной адрес на случай, если GitHub недоступен.
const _urls = [
  'https://raw.githubusercontent.com/Qteb/ranepa-sync/config/config.json',
  'https://cdn.jsdelivr.net/gh/Qteb/ranepa-sync@config/config.json',
];

/// Конфиг проверяется не чаще раза в сутки.
const _maxAge = Duration(hours: 24);

const _keyJson = 'remoteConfig';
const _keyCheckedAt = 'remoteConfigCheckedAt';

class RemoteConfig {
  const RemoteConfig({
    this.sync = true,
    this.minInterval = const Duration(hours: 4),
    this.manualCooldown = const Duration(minutes: 2),
    this.message,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    const d = RemoteConfig();
    final hours = json['minIntervalHours'];
    final minutes = json['manualCooldownMinutes'];
    final message = json['message'];
    return RemoteConfig(
      sync: json['sync'] is bool ? json['sync'] as bool : d.sync,
      minInterval: hours is num
          ? Duration(minutes: (hours * 60).round())
          : d.minInterval,
      manualCooldown: minutes is num
          ? Duration(seconds: (minutes * 60).round())
          : d.manualCooldown,
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
    );
  }

  /// false — приложение не ходит в ЛК совсем, показывает сохранённое.
  final bool sync;

  /// Минимальный интервал между фоновыми обновлениями.
  final Duration minInterval;

  /// Ручное обновление чаще этого не делает запросов.
  final Duration manualCooldown;

  /// Пояснение для пользователя, когда обновление остановлено.
  final String? message;

  /// Сохранённый конфиг; без сети и до первой загрузки — значения по умолчанию.
  static RemoteConfig cached(SharedPreferences prefs) {
    final raw = prefs.getString(_keyJson);
    if (raw == null) return const RemoteConfig();
    try {
      return RemoteConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const RemoteConfig();
    }
  }

  /// Раз в сутки перечитывает конфиг. Если оба адреса недоступны, остаётся
  /// последний сохранённый.
  static Future<RemoteConfig> load(SharedPreferences prefs) async {
    final checkedAt = prefs.getInt(_keyCheckedAt);
    final fresh =
        checkedAt != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(checkedAt),
            ) <
            _maxAge;
    if (!fresh) {
      for (final url in _urls) {
        final raw = await _download(url);
        if (raw == null) continue;
        await prefs.setString(_keyJson, raw);
        await prefs.setInt(
          _keyCheckedAt,
          DateTime.now().millisecondsSinceEpoch,
        );
        break;
      }
    }
    return cached(prefs);
  }

  static Future<String?> _download(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      // Проверяем, что это наш JSON, а не страница-заглушка провайдера.
      if (jsonDecode(body) is! Map<String, dynamic>) return null;
      return body;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
