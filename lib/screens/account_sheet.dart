import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:workmanager/workmanager.dart';

import '../app_state.dart';
import '../format.dart';
import '../services/background.dart';
import '../services/calendar_export.dart';
import '../widgets/avatar.dart';

/// Аккаунт и настройки одним листом, как аккаунт в App Store.
Future<void> showAccountSheet(BuildContext context, AppState state) =>
    showCupertinoSheet(
      context: context,
      // Лист iOS не задаёт стиль текста по умолчанию — без этого Flutter
      // подчёркивает текст жёлтым.
      scrollableBuilder: (context, controller) => DefaultTextStyle(
        style: CupertinoTheme.of(context).textTheme.textStyle,
        child: _AccountSheet(state: state, controller: controller),
      ),
    );

const _reminderOptions = [0, 5, 10, 15, 30, 60];

String _reminderLabel(int minutes) =>
    minutes == 0 ? 'Выкл.' : 'За $minutes мин';

const _themeLabels = {
  ThemeMode.system: 'Авто',
  ThemeMode.light: 'Светлое',
  ThemeMode.dark: 'Тёмное',
};

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.state, required this.controller});

  final AppState state;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          transitionBetweenRoutes: false,
          middle: const Text('Аккаунт'),
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Готово',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        child: ListView(
          controller: controller,
          children: [
            _Profile(state: state),
            CupertinoListSection.insetGrouped(
              footer: _Footer(_backgroundFooter(state)),
              children: [
                CupertinoListTile(
                  leading: const _Glyph(
                    CupertinoIcons.bell_fill,
                    CupertinoColors.systemRed,
                  ),
                  title: const Text('Напоминание'),
                  additionalInfo: Text(_reminderLabel(state.reminderMinutes)),
                  trailing: const _Chevron(),
                  onTap: () => _pickReminder(context),
                ),
                CupertinoListTile(
                  leading: const _Glyph(
                    CupertinoIcons.calendar,
                    CupertinoColors.systemOrange,
                  ),
                  title: const Text('Календарь iPhone'),
                  trailing: CupertinoSwitch(
                    value: state.calendarExport,
                    onChanged: state.setCalendarExport,
                  ),
                ),
                CupertinoListTile(
                  leading: const _Glyph(
                    CupertinoIcons.moon_fill,
                    CupertinoColors.systemIndigo,
                  ),
                  title: const Text('Оформление'),
                  additionalInfo: Text(_themeLabels[state.themeMode]!),
                  trailing: const _Chevron(),
                  onTap: () => _pickTheme(context),
                ),
              ],
            ),
            if (kDebugMode) _DebugSection(state: state),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: const Center(
                    child: Text(
                      'Выйти из ЛК',
                      style: TextStyle(color: CupertinoColors.systemRed),
                    ),
                  ),
                  onTap: () => _confirmLogout(context),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _backgroundFooter(AppState state) {
    final calendar = state.calendarExport
        ? 'Пары добавляются в отдельный календарь «$calendarName». '
        : '';
    final at = state.lastBackgroundRun;
    final last = at == null
        ? 'В фоне ещё не обновлялось.'
        : 'Последнее фоновое обновление — '
              '${sameDay(at, DateTime.now()) ? 'сегодня' : '${at.day}.${at.month.toString().padLeft(2, '0')}'}'
              ' в ${hm(at)}.';
    return '$calendarРасписание обновляется в фоне примерно раз в 4 часа. $last';
  }

  Future<void> _pickReminder(BuildContext context) async {
    final picked = await showCupertinoModalPopup<int>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('Напоминать перед парой'),
        actions: [
          for (final m in _reminderOptions)
            CupertinoActionSheetAction(
              isDefaultAction: m == state.reminderMinutes,
              onPressed: () => Navigator.pop(c, m),
              child: Text(_reminderLabel(m)),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (picked != null) await state.setReminderMinutes(picked);
  }

  Future<void> _pickTheme(BuildContext context) async {
    final picked = await showCupertinoModalPopup<ThemeMode>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('Оформление'),
        actions: [
          for (final e in _themeLabels.entries)
            CupertinoActionSheetAction(
              isDefaultAction: e.key == state.themeMode,
              onPressed: () => Navigator.pop(c, e.key),
              child: Text(e.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (picked != null) await state.setThemeMode(picked);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        message: const Text(
          'Расписание, напоминания и календарь «РАНХиГС» будут удалены '
          'с этого iPhone.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Выйти из ЛК'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop();
      await state.logout();
    }
  }
}

class _Profile extends StatelessWidget {
  const _Profile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        children: [
          Avatar(state: state, size: 84),
          const SizedBox(height: 12),
          Text(
            state.fullName ?? 'Студент',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 4),
          for (final line in [state.group, state.program])
            if (line != null && line.isNotEmpty)
              Text(
                line,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: secondary),
              ),
        ],
      ),
    );
  }
}

/// Цветная иконка-плашка, как в «Настройках» iPhone.
class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: SizedBox.square(
      dimension: 29,
      child: Icon(icon, size: 18, color: CupertinoColors.white),
    ),
  );
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.chevron_up_chevron_down,
    size: 15,
    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
  );
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => CupertinoListSection.insetGrouped(
    header: const Text('Отладка'),
    footer: _Footer(
      'Последний результат: ${state.lastBackgroundResult ?? '—'}',
    ),
    children: [
      CupertinoListTile(
        title: const Text('Запустить фоновое обновление'),
        subtitle: const Text('Сверни приложение сразу после нажатия'),
        onTap: () => Workmanager().registerOneOffTask(
          'debug-${DateTime.now().millisecondsSinceEpoch}',
          backgroundTaskId,
          inputData: {'debug': true},
        ),
      ),
      CupertinoListTile(
        title: const Text('Сымитировать изменение'),
        subtitle: const Text('Сдвигает ближайшую пару на час раньше'),
        onTap: () async {
          await debugShiftNextLesson();
          await state.reloadFromDisk();
        },
      ),
    ],
  );
}

/// Подпись под блоком: 13 pt, вторичный цвет, как в «Настройках».
class _Footer extends StatelessWidget {
  const _Footer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    ),
  );
}
