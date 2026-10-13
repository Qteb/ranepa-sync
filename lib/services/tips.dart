import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Одноразовые подсказки, как TipKit в iOS: каждая показывается, пока её
/// не закрыли или пока пользователь сам не сделал то, о чём она.
enum Tip {
  refresh(
    'Потяни вниз, чтобы обновить',
    'Расписание и так обновляется само '
        'в фоне, но так можно проверить изменения прямо сейчас.',
  ),
  account(
    'Настройки — под фото',
    'Нажми на своё фото справа: там '
        'напоминания, календарь и выход из ЛК.',
  ),
  copy(
    'Удерживай строку, чтобы скопировать',
    'Так можно скопировать '
        'аудиторию, преподавателя, почту или группу.',
  );

  const Tip(this.title, this.message);

  final String title;
  final String message;

  String get _key => 'tip.$name';
}

class Tips extends ChangeNotifier {
  Tips._();

  static final instance = Tips._();

  SharedPreferences? _prefs;

  void init(SharedPreferences prefs) => _prefs = prefs;

  bool isDone(Tip tip) => _prefs?.getBool(tip._key) ?? false;

  /// Главный экран показывает подсказки по одной, по порядку.
  Tip? get nextOnHome =>
      [Tip.refresh, Tip.account].where((t) => !isDone(t)).firstOrNull;

  Future<void> done(Tip tip) async {
    if (isDone(tip)) return;
    await _prefs?.setBool(tip._key, true);
    notifyListeners();
  }
}
