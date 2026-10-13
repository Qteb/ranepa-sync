import 'package:flutter/cupertino.dart';

import '../widgets/lesson_colors.dart';
import '../widgets/settings.dart';

/// Справка: что значат цвета и как управлять приложением жестами.
class LegendScreen extends StatelessWidget {
  const LegendScreen({super.key, required this.leading});

  final Widget leading;

  static const _kinds = [
    ('лекция', 'Лекция', null),
    ('семинар', 'Семинар', 'Практические занятия'),
    ('физкультура', 'Физкультура', 'Узнаётся по названию предмета'),
    ('лабораторная', 'Лабораторная', null),
    ('консультация', 'Консультация', null),
    ('экзамен', 'Экзамен или зачёт', null),
    ('', 'Другое', null),
  ];

  static const _gestures = [
    (CupertinoIcons.arrow_down, 'Потяни вниз', 'Обновить расписание'),
    (CupertinoIcons.arrow_left_right, 'Листай влево и вправо', 'Другой день'),
    (CupertinoIcons.calendar, 'Листай полосу с датами', 'Другая неделя'),
    (
      CupertinoIcons.hand_point_right,
      'Нажми на пару',
      'Аудитория, преподаватель и почта',
    ),
    (CupertinoIcons.doc_on_doc, 'Удерживай строку', 'Скопировать текст'),
    (
      CupertinoIcons.person_crop_circle,
      'Нажми на своё фото',
      'Настройки и выход из ЛК',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: settingsBar(
        context,
        leading: leading,
        middle: const Text('Обозначения'),
      ),
      child: DefaultTextStyle(
        style: CupertinoTheme.of(context).textTheme.textStyle,
        child: ListView(
          children: [
            const SizedBox(height: 8),
            SettingsSection(
              header: 'Типы пар',
              footer:
                  'Цвет полоски слева от пары совпадает с цветом иконки и типа '
                  'в подписи. Те же иконки — на экране блокировки, в Dynamic '
                  'Island и на часах.',
              children: [
                for (final (kind, title, subtitle) in _kinds)
                  SettingsRow(
                    leading: Glyph(
                      LessonColors.iconOf(kind),
                      LessonColors.of(kind).bar.resolveFrom(context),
                    ),
                    title: Text(title),
                    subtitle: subtitle == null ? null : Text(subtitle),
                  ),
              ],
            ),
            SettingsSection(
              header: 'В ленте',
              icons: false,
              children: [
                SettingsRow(
                  title: Text(
                    'Бледная пара',
                    style: TextStyle(color: secondary),
                  ),
                  value: const Text('Уже прошла'),
                ),
                SettingsRow(
                  title: const Text(
                    'Зачёркнутая пара',
                    style: TextStyle(decoration: TextDecoration.lineThrough),
                  ),
                  value: const Text('Отменена'),
                ),
              ],
            ),
            SettingsSection(
              header: 'Жесты',
              children: [
                for (final (icon, title, subtitle) in _gestures)
                  SettingsRow(
                    leading: Icon(
                      icon,
                      color: CupertinoTheme.of(context).primaryColor,
                    ),
                    title: Text(title),
                    subtitle: Text(subtitle),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
