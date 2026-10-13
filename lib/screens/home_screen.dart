import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../services/tips.dart';
import '../widgets/avatar.dart';
import '../widgets/banner.dart';
import '../widgets/lesson_colors.dart';
import '../widgets/tip_card.dart';
import 'account_sheet.dart';
import 'lesson_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late DateTime _firstDay;
  late PageController _pages;
  late DateTime _selected;
  Timer? _ticker;
  String? _shownError;

  /// Обновление запущено жестом: тогда виден индикатор в ленте, а маленький
  /// у даты (для автообновления при открытии) не нужен.
  bool _pulling = false;

  Future<void> _pullToRefresh() async {
    setState(() => _pulling = true);
    Tips.instance.done(Tip.refresh);
    try {
      await state.refresh();
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  AppState get state => widget.state;

  int get _dayCount => fetchWeeks * 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firstDay = mondayOf(DateTime.now());
    _selected = dateOnly(DateTime.now());
    _pages = PageController(initialPage: _indexOf(_selected));
    // Перерисовка раз в минуту: «идёт сейчас» и «ещё N мин».
    _ticker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
    state.addListener(_onState);
    state.refresh(SyncTrigger.open);
    // Системный запрос — только если пользователь ещё не отвечал.
    state.checkNotifications(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(_onState);
    _ticker?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState lifecycle) async {
    if (lifecycle != AppLifecycleState.resumed) return;
    // Пока приложение было свёрнуто, расписание могла обновить фоновая задача.
    await state.reloadFromDisk();
    // Уведомления могли включить или выключить в настройках телефона.
    await state.checkNotifications();
    state.refresh(SyncTrigger.open);
  }

  void _onState() {
    if (!mounted) return;
    final error = state.error;
    if (error == null) _shownError = null;
    if (error != null && !state.loading && error != _shownError) {
      _shownError = error;
      showBanner(
        context,
        title: 'Не удалось обновить',
        message: error,
        icon: CupertinoIcons.exclamationmark_circle_fill,
      );
    } else if (state.pendingChanges.isNotEmpty) {
      final changes = state.pendingChanges;
      state.pendingChanges = const [];
      showBanner(
        context,
        title: changes.length == 1
            ? 'Изменение в расписании'
            : 'Изменения в расписании',
        message: changes.join('\n'),
        icon: CupertinoIcons.calendar_badge_plus,
        duration: const Duration(seconds: 8),
      );
    }
    setState(() {});
  }

  int _indexOf(DateTime day) =>
      dateOnly(day).difference(_firstDay).inDays.clamp(0, _dayCount - 1);

  DateTime _dayAt(int index) => _firstDay.add(Duration(days: index));

  void _goTo(DateTime day) {
    _pages.animateToPage(
      _indexOf(day),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  String get _status {
    final at = state.fetchedAt;
    if (at == null) return 'Расписание ещё не загружено';
    if (state.syncPaused) {
      // Без объяснений про ЛК: по дате видно, насколько данные старые.
      final day = sameDay(at, DateTime.now())
          ? ''
          : '${at.day}.${at.month.toString().padLeft(2, '0')}, ';
      return 'Расписание от $day${hm(at)}';
    }
    final day = sameDay(at, DateTime.now())
        ? 'сегодня'
        : '${at.day}.${at.month.toString().padLeft(2, '0')}';
    return 'Обновлено $day в ${hm(at)}';
  }

  /// Ближайшая пара после [after] (не отменённая), из всего расписания.
  Lesson? _nextAfter(DateTime after) => state.lessons
      .where((l) => !l.cancelled && l.start.isAfter(after))
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final isToday = sameDay(_selected, DateTime.now());
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Строка навигации: «Сегодня», когда ушли с сегодняшнего дня.
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: isToday
                    ? null
                    : CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onPressed: () => _goTo(DateTime.now()),
                        child: const Text('Сегодня'),
                      ),
              ),
            ),
            // Дата мелкими заглавными, под ней крупно «Сегодня» / «Завтра».
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${weekdaysLong[_selected.weekday - 1]}, '
                                      '${_selected.day} ${monthsGenitive[_selected.month - 1]}'
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: secondary,
                              ),
                            ),
                            if (state.loading && !_pulling) ...[
                              const SizedBox(width: 6),
                              const CupertinoActivityIndicator(radius: 6),
                            ],
                          ],
                        ),
                        Text(
                          relativeDayName(_selected),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.37,
                            color: label,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Аккаунт и настройки',
                    child: GestureDetector(
                      onTap: () {
                        Tips.instance.done(Tip.account);
                        showAccountSheet(context, state);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Avatar(state: state, size: 36),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _WeekStrip(
              selected: _selected,
              firstDay: _firstDay,
              lastDay: _dayAt(_dayCount - 1),
              hasLessons: (d) => state.lessonsOn(d).any((l) => !l.cancelled),
              onSelect: _goTo,
            ),
            // Подсказки по одной; появляются, когда расписание уже есть.
            ListenableBuilder(
              listenable: Tips.instance,
              builder: (context, _) {
                final tip = Tips.instance.nextOnHome;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: tip == null || state.lessons.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: TipCard(
                            tip: tip,
                            icon: tip == Tip.refresh
                                ? CupertinoIcons.arrow_down_circle
                                : CupertinoIcons.person_crop_circle,
                          ),
                        ),
                );
              },
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _dayCount,
                onPageChanged: (i) => setState(() => _selected = _dayAt(i)),
                itemBuilder: (context, i) {
                  final day = _dayAt(i);
                  return _DayView(
                    onRefresh: _pullToRefresh,
                    day: day,
                    lessons: state.lessonsOn(day),
                    next: _nextAfter(
                      sameDay(day, DateTime.now())
                          ? DateTime.now()
                          : dateOnly(day).add(const Duration(days: 1)),
                    ),
                    status: _status,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Неделя как в Календаре iOS. Свайп по полосе листает недели.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.firstDay,
    required this.lastDay,
    required this.hasLessons,
    required this.onSelect,
  });

  final DateTime selected;
  final DateTime firstDay;
  final DateTime lastDay;
  final bool Function(DateTime) hasLessons;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    final monday = mondayOf(selected);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    void shift(int days) {
      final target = selected.add(Duration(days: days));
      if (!target.isBefore(firstDay) && !target.isAfter(lastDay)) {
        onSelect(target);
      }
    }

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) shift(7);
        if (v > 200) shift(-7);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Text(
                      weekdaysShort[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _Day(
                      day: monday.add(Duration(days: i)),
                      selected: sameDay(
                        monday.add(Duration(days: i)),
                        selected,
                      ),
                      dot: hasLessons(monday.add(Duration(days: i))),
                      onTap: () => onSelect(monday.add(Duration(days: i))),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.selected,
    required this.dot,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final today = sameDay(day, DateTime.now());
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final Color fill = selected
        ? (today ? accent : label)
        : const Color(0x00000000);
    final Color text = selected
        ? (today
              ? CupertinoColors.white
              : CupertinoColors.systemBackground.resolveFrom(context))
        : today
        ? accent
        : day.weekday >= 6
        ? secondary
        : label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: selected || today
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: text,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot
                  ? CupertinoColors.systemGrey2.resolveFrom(context)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.onRefresh,
    required this.day,
    required this.lessons,
    required this.next,
    required this.status,
  });

  final Future<void> Function() onRefresh;
  final DateTime day;
  final List<Lesson> lessons;

  /// Ближайшая пара после этого дня (или после «сейчас» для сегодня).
  final Lesson? next;
  final String status;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final isToday = sameDay(day, DateTime.now());
    final active = lessons.where((l) => !l.cancelled).toList();

    // Обновление как UIRefreshControl: пока идёт загрузка, список остаётся
    // сдвинутым вниз и не наезжает на индикатор, потом плавно возвращается.
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          sliver: SliverList.list(
            children: [
              if (isToday) ...[
                _NowCard(today: active, next: next),
                const SizedBox(height: 20),
              ],
              if (lessons.isEmpty && !isToday)
                Padding(
                  padding: const EdgeInsets.only(top: 72, bottom: 24),
                  child: Column(
                    children: [
                      Icon(CupertinoIcons.moon_zzz, size: 44, color: secondary),
                      const SizedBox(height: 10),
                      Text(
                        'Пар нет',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                      if (next != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Следующая ${whenLabel(next!.start)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: secondary),
                        ),
                      ],
                    ],
                  ),
                ),
              for (var i = 0; i < lessons.length; i++) ...[
                if (i > 0) _Gap(from: lessons[i - 1].end, to: lessons[i].start),
                _TimelineRow(lesson: lessons[i]),
              ],
              const SizedBox(height: 20),
              Text(
                status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Карточка «Сейчас»: идущая пара, следующая или итог дня.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.today, required this.next});

  final List<Lesson> today;
  final Lesson? next;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final accent = CupertinoTheme.of(context).primaryColor;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    final current = today
        .where((l) => !now.isBefore(l.start) && now.isBefore(l.end))
        .firstOrNull;
    final upcoming = today.where((l) => l.start.isAfter(now)).firstOrNull;

    String caption;
    String? trailing;
    String? title;
    String? subtitle;
    String? footer;
    double? progress;
    Lesson? tapTarget;

    if (current != null) {
      caption = 'СЕЙЧАС';
      trailing =
          'ещё ${duration(current.end.difference(now) + const Duration(minutes: 1))}';
      title = current.subject;
      subtitle = _details(current, context).toPlainText();
      progress =
          now.difference(current.start).inSeconds /
          current.end.difference(current.start).inSeconds;
      footer = upcoming == null
          ? 'Это последняя пара сегодня'
          : 'Дальше в ${hm(upcoming.start)} — ${upcoming.subject}';
      tapTarget = current;
    } else if (upcoming != null) {
      final wait = upcoming.start.difference(now);
      caption = 'ДАЛЕЕ';
      trailing = wait < const Duration(hours: 2)
          ? 'через ${duration(wait + const Duration(minutes: 1))}'
          : 'в ${hm(upcoming.start)}';
      title = upcoming.subject;
      subtitle =
          '${timeRange(upcoming)} · ${_details(upcoming, context).toPlainText()}';
      tapTarget = upcoming;
    } else {
      caption = today.isEmpty ? 'СЕГОДНЯ ПАР НЕТ' : 'ПАРЫ ЗАКОНЧИЛИСЬ';
      if (next != null) {
        title = 'Следующая ${whenLabel(next!.start)}';
        subtitle = next!.subject;
        tapTarget = next;
      } else {
        title = 'Отдыхай';
      }
    }

    return GestureDetector(
      onTap: tapTarget == null
          ? null
          : () => showLessonSheet(context, tapTarget!),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                const Spacer(),
                if (trailing != null)
                  Text(
                    trailing,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: label,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 15, color: secondary)),
            ],
            if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 4,
                  color: accent,
                  backgroundColor: CupertinoColors.systemFill.resolveFrom(
                    context,
                  ),
                ),
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: 10),
              Text(footer, style: TextStyle(fontSize: 13, color: secondary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Подпись под названием: тип цветом типа, остальное серым.
TextSpan _details(Lesson l, BuildContext context) {
  final rest = [
    if (l.location.isNotEmpty) l.isRemote ? 'дистанционно' : l.shortLocation,
    if (l.cancelled) 'отменена',
  ].join(' · ');
  return TextSpan(
    children: [
      if (l.kind.isNotEmpty)
        TextSpan(
          text: capitalize(l.kind),
          style: TextStyle(
            color: LessonColors.of(l.kind).text.resolveFrom(context),
          ),
        ),
      if (l.kind.isNotEmpty && rest.isNotEmpty) const TextSpan(text: ' · '),
      TextSpan(text: rest),
    ],
  );
}

/// Пара в ленте: время столбиком слева, цветная полоска, название.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ongoing =
        !lesson.cancelled &&
        !now.isBefore(lesson.start) &&
        now.isBefore(lesson.end);
    final dimmed = lesson.cancelled || now.isAfter(lesson.end);
    final accent = CupertinoTheme.of(context).primaryColor;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showLessonSheet(context, lesson),
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 48,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hm(lesson.start),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: ongoing
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: ongoing ? accent : label,
                        ),
                      ),
                      Text(
                        hm(lesson.end),
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: LessonColors.of(lesson.kind).bar
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.subject,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: ongoing
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: label,
                          decoration: lesson.cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text.rich(
                        _details(lesson, context),
                        style: TextStyle(fontSize: 15, color: secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Перерыв 20 мин» или «Окно 1 ч 40 мин» между парами.
class _Gap extends StatelessWidget {
  const _Gap({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final gap = to.difference(from);
    if (gap <= Duration.zero) return const SizedBox(height: 4);
    final text = gap >= const Duration(minutes: 60)
        ? 'Окно ${duration(gap)}'
        : 'Перерыв ${duration(gap)}';
    return Padding(
      padding: const EdgeInsets.only(left: 71, top: 2, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}
