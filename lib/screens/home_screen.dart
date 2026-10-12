import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/avatar.dart';
import '../widgets/banner.dart';
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
    if (state.isStale) state.refresh();
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
    if (state.isStale) state.refresh();
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
    if (state.loading) return 'Обновляю…';
    final at = state.fetchedAt;
    if (at == null) return 'Нет данных';
    final day = sameDay(at, DateTime.now())
        ? ''
        : ' ${at.day}.${at.month.toString().padLeft(2, '0')}';
    return 'Обновлено$day в ${hm(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Строка навигации: только «Сегодня», когда ушли с сегодняшнего дня.
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: sameDay(_selected, DateTime.now())
                    ? null
                    : CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        onPressed: () => _goTo(DateTime.now()),
                        child: const Text('Сегодня'),
                      ),
              ),
            ),
            // Крупный заголовок и аватарка справа, как в App Store и Музыке.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Расписание',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.37,
                            color: label,
                          ),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                [
                                  if (state.group != null) state.group!,
                                  _status,
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: secondary,
                                ),
                              ),
                            ),
                            if (state.loading) ...[
                              const SizedBox(width: 6),
                              const CupertinoActivityIndicator(radius: 7),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Аккаунт и настройки',
                    child: GestureDetector(
                      onTap: () => showAccountSheet(context, state),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
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
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: _dayCount,
                onPageChanged: (i) => setState(() => _selected = _dayAt(i)),
                itemBuilder: (context, i) => RefreshIndicator.adaptive(
                  onRefresh: state.refresh,
                  child: _DayView(
                    day: _dayAt(i),
                    lessons: state.lessonsOn(_dayAt(i)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final sunday = monday.add(const Duration(days: 6));
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final range = monday.month == sunday.month
        ? '${monday.day} – ${sunday.day} ${monthsGenitive[monday.month - 1]}'
        : '${monday.day} ${monthsGenitive[monday.month - 1]} – '
              '${sunday.day} ${monthsGenitive[sunday.month - 1]}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: monday.isAfter(firstDay)
                    ? () => onSelect(selected.subtract(const Duration(days: 7)))
                    : null,
                child: const Icon(CupertinoIcons.chevron_left, size: 20),
              ),
              Expanded(
                child: Text(
                  range,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                onPressed: sunday.isBefore(lastDay)
                    ? () => onSelect(selected.add(const Duration(days: 7)))
                    : null,
                child: const Icon(CupertinoIcons.chevron_right, size: 20),
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _Day(
                    day: monday.add(Duration(days: i)),
                    selected: sameDay(monday.add(Duration(days: i)), selected),
                    dot: hasLessons(monday.add(Duration(days: i))),
                    onTap: () => onSelect(monday.add(Duration(days: i))),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// День недели как в Календаре iOS: буква сверху, число в кружке.
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
    final weekend = day.weekday >= 6;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final numberColor = selected
        ? CupertinoColors.white
        : today
        ? accent
        : weekend
        ? secondary
        : label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Text(
            weekdaysShort[day.weekday - 1],
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 4),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? (today ? accent : label) : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 19,
                fontWeight: selected || today
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: selected && !today
                    ? CupertinoColors.systemBackground.resolveFrom(context)
                    : numberColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot
                  ? CupertinoColors.systemGrey.resolveFrom(context)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({required this.day, required this.lessons});

  final DateTime day;
  final List<Lesson> lessons;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 96),
            child: Column(
              children: [
                Icon(CupertinoIcons.moon_zzz, size: 44, color: secondary),
                const SizedBox(height: 10),
                Text(
                  'Пар нет',
                  style: TextStyle(fontSize: 17, color: secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  dayTitle(day),
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
            ),
          )
        else
          CupertinoListSection.insetGrouped(
            header: Text(dayTitle(day)),
            hasLeading: false,
            children: [for (final l in lessons) _LessonRow(lesson: l)],
          ),
      ],
    );
  }
}

Color kindColor(String kind, BuildContext context) => switch (kind) {
  'лекция' => CupertinoTheme.of(context).primaryColor,
  'семинар' => CupertinoColors.systemOrange.resolveFrom(context),
  _ => CupertinoColors.systemTeal.resolveFrom(context),
};

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final ongoing =
        !lesson.cancelled &&
        !now.isBefore(lesson.start) &&
        now.isBefore(lesson.end);
    final past = now.isAfter(lesson.end);
    final dimmed = past || lesson.cancelled;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;

    final details = [
      timeRange(lesson),
      if (lesson.kind.isNotEmpty) lesson.kind,
      if (lesson.cancelled) 'отменена',
    ].join(' · ');

    return CupertinoListTile(
      onTap: () => showLessonSheet(context, lesson),
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 40,
            margin: const EdgeInsets.only(right: 12, top: 2),
            decoration: BoxDecoration(
              color: kindColor(
                lesson.kind,
                context,
              ).withValues(alpha: dimmed ? 0.35 : 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.subject,
                  softWrap: true,
                  maxLines: 3,
                  style: TextStyle(
                    fontSize: 17,
                    color: dimmed ? secondary : label,
                    decoration: lesson.cancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(details, style: TextStyle(fontSize: 15, color: secondary)),
                if (lesson.location.isNotEmpty)
                  Text(
                    lesson.shortLocation,
                    style: TextStyle(fontSize: 15, color: secondary),
                  ),
                if (ongoing)
                  Text(
                    'Идёт сейчас · ещё ${lesson.end.difference(now).inMinutes + 1} мин',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      trailing: const CupertinoListTileChevron(),
    );
  }
}
