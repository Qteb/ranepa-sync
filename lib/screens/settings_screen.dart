import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/calendar_export.dart';

const _reminderOptions = [0, 5, 10, 15, 30, 60];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: ListView(
          children: [
            const _Header('Напоминания'),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Перед парой'),
              trailing: DropdownButton<int>(
                value: state.reminderMinutes,
                underline: const SizedBox(),
                items: [
                  for (final m in _reminderOptions)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m == 0 ? 'выкл.' : 'за $m мин'),
                    ),
                ],
                onChanged: (m) => state.setReminderMinutes(m ?? 0),
              ),
            ),
            const _Header('Календарь'),
            SwitchListTile(
              secondary: const Icon(Icons.event_outlined),
              title: const Text('Добавлять пары в календарь телефона'),
              subtitle: const Text(
                'Отдельный календарь «$calendarName», обновляется вместе с расписанием',
              ),
              value: state.calendarExport,
              onChanged: state.setCalendarExport,
            ),
            const _Header('Оформление'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Авто')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (s) => state.setThemeMode(s.first),
              ),
            ),
            const _Header('Аккаунт'),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Выйти из ЛК'),
              subtitle: const Text('Удалит сохранённое расписание с телефона'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Выйти?'),
                    content: const Text(
                      'Расписание, напоминания и календарь «РАНХиГС» будут удалены.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Отмена'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Выйти'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  await state.logout();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
