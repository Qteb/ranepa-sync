import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode, showGeneralDialog;
import 'package:workmanager/workmanager.dart';

import '../app_state.dart';
import '../format.dart';
import '../services/background.dart';
import '../services/calendar_export.dart';
import '../services/notifications.dart';
import '../widgets/avatar.dart';
import '../widgets/copy.dart';
import '../widgets/settings.dart';
import 'about_screen.dart';

/// Аккаунт и настройки одним листом, как аккаунт в App Store. На iPad —
/// окном по центру, как настройки в системных приложениях.
Future<void> showAccountSheet(BuildContext context, AppState state) {
  if (MediaQuery.sizeOf(context).width >= 700) {
    return _showAccountPanel(context, state);
  }
  return showCupertinoSheet(
    context: context,
    // «О приложении» открывается внутри листа.
    useNestedNavigation: true,
    // Лист iOS не задаёт стиль текста по умолчанию — без этого Flutter
    // подчёркивает текст жёлтым.
    // Углы скруглены сильнее стандартных 12 pt Flutter, как у листов
    // iOS 26.
    scrollableBuilder: (context, controller) => ClipRSuperellipse(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(sheetRadius),
      ),
      child: DefaultTextStyle(
        style: CupertinoTheme.of(context).textTheme.textStyle,
        child: _AccountSheet(
          state: state,
          controller: controller,
          // Через корневой навигатор: pop из вложенного оставляет главный
          // экран уменьшенным и затемнённым, как будто лист ещё открыт.
          close: CupertinoSheetRoute.popSheet,
        ),
      ),
    ),
  );
}

/// iPad: окно 620 pt по центру со своей навигацией внутри.
Future<void> _showAccountPanel(BuildContext context, AppState state) {
  void close(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).pop();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: const Color(0x47000000),
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, _) {
      final height = MediaQuery.sizeOf(context).height;
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: height - 120 < 860 ? height - 120 : 860,
          ),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(sheetRadius),
            // Цвета «приподнятые», как у системных окон в тёмной теме.
            child: CupertinoUserInterfaceLevel(
              data: CupertinoUserInterfaceLevelData.elevated,
              // Окно не касается краёв экрана: отступы строки состояния
              // и жеста «домой» внутри не нужны.
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: Navigator(
                  onGenerateRoute: (_) => CupertinoPageRoute<void>(
                    builder: (context) => DefaultTextStyle(
                      style: CupertinoTheme.of(context).textTheme.textStyle,
                      child: _AccountSheet(state: state, close: close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

const _reminderOptions = [0, 5, 10, 15, 30, 60];

String _reminderLabel(int minutes) =>
    minutes == 0 ? 'Выкл.' : 'За $minutes мин';

const _themeLabels = {
  ThemeMode.system: 'Авто',
  ThemeMode.light: 'Светлое',
  ThemeMode.dark: 'Тёмное',
};

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({
    required this.state,
    required this.close,
    this.controller,
  });

  final AppState state;
  final ScrollController? controller;

  /// Закрывает лист или окно целиком, из любого вложенного экрана.
  final void Function(BuildContext) close;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.systemGroupedBackground,
        // Без заголовка, как лист аккаунта в iOS 26: профиль и так виден.
        navigationBar: SettingsBar(
          trailing: BarCircleButton(
            icon: CupertinoIcons.xmark,
            label: 'Закрыть',
            onPressed: () => close(context),
          ),
        ),
        // Строки настроек с переключателями: при очень крупном шрифте
        // подпись не помещается даже в две строки.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              _Profile(state: state),
              SettingsSection(
                footer: _backgroundFooter(state),
                children: [
                  SettingsRow(
                    leading: const Glyph(
                      CupertinoIcons.bell_fill,
                      CupertinoColors.systemRed,
                    ),
                    title: const Text('Напоминание'),
                    value: Text(
                      state.notificationsEnabled == false
                          ? 'Выключены'
                          : _reminderLabel(state.reminderMinutes),
                    ),
                    trailing: const _Chevron(),
                    onTap: () => state.notificationsEnabled == false
                        ? _explainNotificationsOff(context)
                        : _pickReminder(context),
                  ),
                  SettingsRow(
                    leading: const Glyph(
                      CupertinoIcons.calendar,
                      CupertinoColors.systemOrange,
                    ),
                    title: const Text('Календарь iPhone'),
                    trailing: CupertinoSwitch(
                      value: state.calendarExport,
                      onChanged: state.setCalendarExport,
                    ),
                  ),
                  // Live Activity есть только на iOS.
                  if (Platform.isIOS)
                    SettingsRow(
                      leading: const Glyph(
                        CupertinoIcons.timer,
                        CupertinoColors.systemGreen,
                      ),
                      title: const Text('Пара на экране блокировки'),
                      trailing: CupertinoSwitch(
                        value: state.liveActivity,
                        onChanged: state.setLiveActivity,
                      ),
                    ),
                  SettingsRow(
                    leading: const Glyph(
                      CupertinoIcons.moon_fill,
                      CupertinoColors.systemIndigo,
                    ),
                    title: const Text('Оформление'),
                    value: Text(_themeLabels[state.themeMode]!),
                    trailing: const _Chevron(),
                    onTap: () => _pickTheme(context),
                  ),
                ],
              ),
              if ((kDebugMode || testTools) &&
                  !recordingMode &&
                  !screenshotMode)
                _DebugSection(state: state),
              SettingsSection(
                children: [
                  SettingsRow(
                    leading: const Glyph(
                      CupertinoIcons.info,
                      CupertinoColors.systemGrey,
                    ),
                    title: const Text('О приложении'),
                    trailing: const SettingsChevron(),
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const AboutScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              SettingsSection(
                icons: false,
                children: [
                  SettingsRow(
                    title: Center(
                      child: Text(
                        state.demo && !screenshotMode
                            ? 'Выйти из демо'
                            : 'Выйти из ЛК',
                        style: TextStyle(color: CupertinoColors.systemRed),
                      ),
                    ),
                    onTap: () => _confirmLogout(context),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
            ],
          ),
        ),
      ),
    );
  }

  String _backgroundFooter(AppState state) {
    if (state.demo && !screenshotMode) {
      return 'Демо-режим: профиль и расписание выдуманы, приложение не '
          'обращается к ЛК. «Выйти из демо» удалит и календарь «$calendarName».';
    }
    final calendar = state.calendarExport
        ? 'Пары добавляются в отдельный календарь «$calendarName». '
        : '';
    final at = state.lastBackgroundRun;
    final last = state.demo
        ? ''
        : at == null
        ? 'В фоне ещё не обновлялось.'
        : 'Последнее фоновое обновление — '
              '${sameDay(at, currentTime()) ? 'сегодня' : '${at.day}.${at.month.toString().padLeft(2, '0')}'}'
              ' в ${hm(at)}.';
    final off = state.notificationsEnabled == false
        ? 'Уведомления выключены — об изменениях в расписании ты не узнаешь. '
        : '';
    return '$off$calendarРасписание обновляется в фоне примерно раз в 4 часа. '
            '$last'
        .trim();
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
        title: const Text('Оформление', maxLines: 2),
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
              ? 'Демо-расписание, напоминания и календарь «РАНХиГС» будут '
                    'удалены.'
              : 'Расписание, напоминания и календарь «РАНХиГС» будут удалены '
                    'с этого iPhone.',
        ),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              state.demo && !screenshotMode ? 'Выйти из демо' : 'Выйти из ЛК',
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Отмена'),
        ),
      ),
    );
    if (ok == true && context.mounted) {
      close(context);
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
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
  Widget build(BuildContext context) => SettingsSection(
    header: 'Отладка',
    footer: 'Последний результат: ${state.lastBackgroundResult ?? '—'}',
    icons: false,
    children: [
      SettingsRow(
        title: const Text('Ускоренный день'),
        subtitle: const Text('Демо: 4 пары по 4 мин, первая через 3 мин'),
        onTap: () => _startFastDay(context),
      ),
      SettingsRow(
        title: const Text('Напоминание о паре'),
        subtitle: const Text('Через 5 секунд — заблокируй телефон'),
        onTap: () {
          final now = currentTime();
          final lesson =
              state.lessons
                  .where((l) => !l.cancelled && l.start.isAfter(now))
                  .firstOrNull ??
              state.lessons.lastOrNull;
          if (lesson != null) {
            showTestReminder(lesson, state.reminderMinutes.clamp(1, 60));
          }
        },
      ),
      SettingsRow(
        title: const Text('Уведомление об изменении'),
        subtitle: const Text('Показать сразу, как после обновления'),
        onTap: () => showScheduleChanges(const [
          'Математика, ср 14.10: перенесли с 12:20 на 14:00',
        ]),
      ),
      if (Platform.isIOS)
        SettingsRow(
          title: const Text('Обновить Live Activity'),
          subtitle: const Text('Запустить или обновить по сегодняшним парам'),
          onTap: state.showLiveActivity,
        ),
      SettingsRow(
        title: const Text('Запустить фоновое обновление'),
        subtitle: const Text('Сверни приложение сразу после нажатия'),
        onTap: () => Workmanager().registerOneOffTask(
          'debug-${DateTime.now().millisecondsSinceEpoch}',
          backgroundTaskId,
          inputData: {'debug': true},
        ),
      ),
      SettingsRow(
        title: const Text('Сымитировать изменение'),
        subtitle: const Text('Сдвигает ближайшую пару на час раньше'),
        onTap: () async {
          await debugShiftNextLesson();
          await state.reloadFromDisk();
        },
      ),
    ],
  );

  Future<void> _startFastDay(BuildContext context) async {
    if (state.loggedIn && !state.demo) {
      final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (c) => CupertinoAlertDialog(
          title: const Text('Ускоренный день'),
          content: const Text(
            'Это демо-режим: выйдешь из ЛК, потом нужно будет войти заново.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Выйти и начать'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (context.mounted) CupertinoSheetRoute.popSheet(context);
    await state.startFastDay();
  }
}
