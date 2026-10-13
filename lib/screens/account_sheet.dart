import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:workmanager/workmanager.dart';

import '../app_state.dart';
import '../format.dart';
import '../services/background.dart';
import '../services/calendar_export.dart';
import '../widgets/avatar.dart';
import '../widgets/copy.dart';
import '../widgets/settings.dart';
import 'about_screen.dart';

/// Аккаунт и настройки одним листом, как аккаунт в App Store.
Future<void> showAccountSheet(BuildContext context, AppState state) =>
    showCupertinoSheet(
      context: context,
      // «О приложении» открывается внутри листа.
      useNestedNavigation: true,
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
            // Через корневой навигатор: pop из вложенного оставляет главный
            // экран уменьшенным и затемнённым, как будто лист ещё открыт.
            onPressed: () => CupertinoSheetRoute.popSheet(context),
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
              footer: SectionFooter(_backgroundFooter(state)),
              children: [
                CupertinoListTile(
                  leading: const Glyph(
                    CupertinoIcons.bell_fill,
                    CupertinoColors.systemRed,
                  ),
                  title: const Text('Напоминание'),
                  additionalInfo: Text(
                    state.notificationsEnabled == false
                        ? 'Выключены'
                        : _reminderLabel(state.reminderMinutes),
                  ),
                  trailing: const _Chevron(),
                  onTap: () => state.notificationsEnabled == false
                      ? _explainNotificationsOff(context)
                      : _pickReminder(context),
                ),
                CupertinoListTile(
                  leading: const Glyph(
                    CupertinoIcons.calendar,
                    CupertinoColors.systemOrange,
                  ),
                  title: const Text('Календарь iPhone'),
                  trailing: CupertinoSwitch(
                    value: state.calendarExport && !state.demo,
                    // Выдуманные пары в настоящий календарь не пишем.
                    onChanged: state.demo ? null : state.setCalendarExport,
                  ),
                ),
                CupertinoListTile(
                  leading: const Glyph(
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
                  leading: const Glyph(
                    CupertinoIcons.info,
                    CupertinoColors.systemGrey,
                  ),
                  title: const Text('О приложении'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: Center(
                    child: Text(
                      state.demo ? 'Выйти из демо' : 'Выйти из ЛК',
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
    if (state.demo) {
      return 'Демо-режим: студент и расписание выдуманы, приложение не '
          'обращается к ЛК. Календарь в демо не используется.';
    }
    final calendar = state.calendarExport
        ? 'Пары добавляются в отдельный календарь «$calendarName». '
        : '';
    final at = state.lastBackgroundRun;
    final last = at == null
        ? 'В фоне ещё не обновлялось.'
        : 'Последнее фоновое обновление — '
              '${sameDay(at, currentTime()) ? 'сегодня' : '${at.day}.${at.month.toString().padLeft(2, '0')}'}'
              ' в ${hm(at)}.';
    final off = state.notificationsEnabled == false
        ? 'Уведомления выключены — об изменениях в расписании ты не узнаешь. '
        : '';
    return '$off$calendarРасписание обновляется в фоне примерно раз в 4 часа. '
        '$last';
  }

  /// Уведомления запрещены в настройках телефона: iOS больше не покажет
  /// запрос, включить их можно только там.
  Future<void> _explainNotificationsOff(BuildContext context) async {
    final open = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('Уведомления выключены'),
        content: const Text(
          'Чтобы получать напоминания о парах и изменениях в расписании, '
          'разреши уведомления в Настройках.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Открыть Настройки'),
          ),
        ],
      ),
    );
    if (open == true) {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
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
        message: Text(
          state.demo
              ? 'Демо-расписание и напоминания будут удалены.'
              : 'Расписание, напоминания и календарь «РАНХиГС» будут удалены '
                    'с этого iPhone.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: Text(state.demo ? 'Выйти из демо' : 'Выйти из ЛК'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (ok == true && context.mounted) {
      CupertinoSheetRoute.popSheet(context);
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
              CopyOnLongPress(
                text: line,
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
              ),
        ],
      ),
    );
  }
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
    footer: SectionFooter(
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
