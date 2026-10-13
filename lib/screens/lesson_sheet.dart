import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models.dart';
import '../widgets/copy.dart';
import '../widgets/mail.dart';

/// Подробности пары листом, как карточка события в Календаре iOS.
void showLessonSheet(BuildContext context, Lesson lesson) {
  showCupertinoSheet(
    context: context,
    scrollableBuilder: (context, controller) => DefaultTextStyle(
      style: CupertinoTheme.of(context).textTheme.textStyle,
      child: _LessonSheet(lesson: lesson, controller: controller),
    ),
  );
}

/// Тип занятия над названием: «лекция» → «ЛЕКЦИЯ».
String _kindLabel(String kind) => switch (kind) {
  '' => 'ПАРА',
  'лаба' => 'ЛАБОРАТОРНАЯ',
  _ => kind.toUpperCase(),
};

class _LessonSheet extends StatelessWidget {
  const _LessonSheet({required this.lesson, required this.controller});

  final Lesson lesson;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      // Карточку только смотрят, поэтому закрывается крестиком, а не
      // «Готово», как карточка события в Календаре.
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        transitionBetweenRoutes: false,
        border: null,
        backgroundColor: CupertinoColors.systemGroupedBackground,
        trailing: const _CloseButton(),
      ),
      child: ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kindLabel(lesson.kind),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => copyText(context, lesson.subject),
                  child: Text(
                    lesson.subject,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: label,
                      decoration: lesson.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [dayTitle(lesson.start), timeRange(lesson)].join(', '),
                  style: TextStyle(fontSize: 17, color: secondary),
                ),
                if (lesson.cancelled)
                  Text(
                    'Отменена',
                    style: TextStyle(
                      fontSize: 17,
                      color: CupertinoColors.systemRed.resolveFrom(context),
                    ),
                  ),
              ],
            ),
          ),
          CupertinoListSection.insetGrouped(
            children: [
              if (lesson.location.isNotEmpty)
                _Row(
                  icon: lesson.isRemote
                      ? CupertinoIcons.videocam
                      : CupertinoIcons.placemark,
                  title: lesson.isRemote ? 'Дистанционно' : lesson.room,
                ),
              if (lesson.lecturer.isNotEmpty)
                _Row(icon: CupertinoIcons.person, title: lesson.lecturer),
              if (lesson.email.isNotEmpty)
                _Row(
                  icon: CupertinoIcons.mail,
                  title: lesson.email,
                  color: accent,
                  onTap: () => openMail(context, lesson.email),
                  copy: lesson.email,
                ),
              if (lesson.groups.isNotEmpty)
                _Row(
                  icon: CupertinoIcons.person_3,
                  title: lesson.groups.join(', '),
                ),
            ],
          ),
          if (lesson.comment.isNotEmpty)
            CupertinoListSection.insetGrouped(
              header: const Text('Комментарий'),
              children: [
                _Row(icon: CupertinoIcons.text_bubble, title: lesson.comment),
              ],
            ),
          if (lesson.lmsLink.isNotEmpty)
            CupertinoListSection.insetGrouped(
              children: [
                _Row(
                  icon: CupertinoIcons.book,
                  title: 'Открыть курс в СДО',
                  color: accent,
                  trailing: Icon(
                    CupertinoIcons.arrow_up_right,
                    size: 16,
                    color: accent,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(lesson.lmsLink),
                    mode: LaunchMode.externalApplication,
                  ),
                  copy: lesson.lmsLink,
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.color,
    this.trailing,
    this.onTap,
    this.copy,
  });

  final IconData icon;
  final String title;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Что копировать: по нажатию, если у строки нет своего действия,
  /// иначе долгим нажатием. По умолчанию — сам текст строки.
  final String? copy;

  @override
  Widget build(BuildContext context) {
    void copyRow() => copyText(context, copy ?? title);
    return GestureDetector(
      onLongPress: onTap == null ? null : copyRow,
      child: CupertinoListTile(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Icon(
          icon,
          size: 22,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
        title: Text(
          title,
          maxLines: 4,
          style: TextStyle(
            color: color ?? CupertinoColors.label.resolveFrom(context),
          ),
        ),
        trailing: trailing,
        onTap: onTap ?? copyRow,
      ),
    );
  }
}

/// Круглая кнопка закрытия листа, как в системных приложениях iOS.
class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size.square(44),
    onPressed: () => Navigator.of(context).pop(),
    child: Semantics(
      label: 'Закрыть',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 30,
          child: Icon(
            CupertinoIcons.xmark,
            size: 14,
            weight: 700,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      ),
    ),
  );
}
