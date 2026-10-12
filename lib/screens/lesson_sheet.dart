import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models.dart';

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
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        transitionBetweenRoutes: false,
        middle: const Text('Пара'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.subject,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: label,
                    decoration: lesson.cancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [dayTitle(lesson.start), timeRange(lesson)].join(', '),
                  style: TextStyle(fontSize: 17, color: secondary),
                ),
                if (lesson.kind.isNotEmpty || lesson.cancelled)
                  Text(
                    [
                      if (lesson.kind.isNotEmpty) lesson.kind,
                      if (lesson.cancelled) 'отменена',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 17,
                      color: lesson.cancelled
                          ? CupertinoColors.systemRed.resolveFrom(context)
                          : secondary,
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
                  onTap: () =>
                      launchUrl(Uri(scheme: 'mailto', path: lesson.email)),
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
  });

  final IconData icon;
  final String title;
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CupertinoListTile(
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
    onTap: onTap,
  );
}
