import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showModalBottomSheet;
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models.dart';
import '../services/tips.dart';
import '../widgets/copy.dart';
import '../widgets/lesson_colors.dart';
import '../widgets/mail.dart';
import '../widgets/tip_card.dart';

/// Подробности пары листом высотой по содержимому, как карточка места
/// в Картах: язычок сверху, закрывается свайпом вниз, тапом мимо или
/// крестиком. Длинная карточка растёт почти до верха и прокручивается.
void showLessonSheet(BuildContext context, Lesson lesson) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // На iPad лист не растягивается на всю ширину.
    constraints: const BoxConstraints(maxWidth: 640),
    useSafeArea: true,
    // Фон рисует сам лист: цвет, вычисленный здесь, не сменится вместе
    // с темой, пока лист открыт.
    backgroundColor: const Color(0x00000000),
    barrierColor: const Color(0x47000000),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    clipBehavior: Clip.antiAlias,
    // Как у системных листов: в тёмной теме цвета «приподнятые», серые,
    // иначе лист сливается с затемнённым экраном под ним.
    builder: (context) => CupertinoUserInterfaceLevel(
      data: CupertinoUserInterfaceLevelData.elevated,
      child: Builder(
        builder: (context) => ColoredBox(
          color: CupertinoColors.systemGroupedBackground.resolveFrom(context),
          child: DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: _LessonSheet(lesson: lesson),
          ),
        ),
      ),
    ),
  );
}

/// Тип занятия над названием: «лекция» → «ЛЕКЦИЯ».
String _kindLabel(String kind) => switch (kind) {
  '' => 'ПАРА',
  _ => kind.toUpperCase(),
};

class _LessonSheet extends StatelessWidget {
  const _LessonSheet({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;

    return SingleChildScrollView(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kindLabel(lesson.kind),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            color: LessonColors.of(lesson.kind).text
                                .resolveFrom(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        CopyOnLongPress(
                          text: lesson.subject,
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
                          [
                            dayTitle(lesson.start),
                            timeRange(lesson),
                          ].join(', '),
                          style: TextStyle(fontSize: 17, color: secondary),
                        ),
                        if (lesson.cancelled)
                          Text(
                            'Отменена',
                            style: TextStyle(
                              fontSize: 17,
                              color: CupertinoColors.systemRed.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Справа на уровне названия, как в карточке места в Картах.
                  const _CloseButton(),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: Tips.instance,
              builder: (context, _) => AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: Tips.instance.isDone(Tip.copy)
                    ? const SizedBox(width: double.infinity)
                    : const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: TipCard(
                          tip: Tip.copy,
                          icon: CupertinoIcons.doc_on_doc,
                        ),
                      ),
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
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Язычок листа: подсказывает, что его можно смахнуть вниз.
class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      width: 36,
      height: 5,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey3.resolveFrom(context),
        borderRadius: BorderRadius.circular(2.5),
      ),
    ),
  );
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

  /// Что копировать долгим нажатием; по умолчанию — текст строки.
  final String? copy;

  @override
  Widget build(BuildContext context) => CopyOnLongPress(
    text: copy ?? title,
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
      onTap: onTap,
    ),
  );
}

/// Кнопка закрытия листа, как в Картах: серый круг с крестиком,
/// зона нажатия 44×44.
class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size.square(44),
    onPressed: () => Navigator.of(context).pop(),
    child: Semantics(
      button: true,
      label: 'Закрыть',
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.xmark,
          size: 14,
          weight: 700,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    ),
  );
}
