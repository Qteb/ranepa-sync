import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import 'lesson_sheet.dart';
import 'settings_screen.dart';

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
    // Перерисовка раз в минуту: «идёт сейчас» и «осталось N мин».
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
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed && state.isStale) {
      state.refresh();
    }
  }

  void _onState() {
    if (!mounted) return;
    final error = state.error;
    if (error == null) _shownError = null;
    if (error != null && !state.loading && error != _shownError) {
      _shownError = error;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fetchedAt = state.fetchedAt;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.group ?? 'Расписание'),
            Text(
              state.loading
                  ? 'Обновляю…'
                  : fetchedAt == null
                  ? 'Нет данных'
                  : 'Обновлено ${sameDay(fetchedAt, DateTime.now()) ? 'сегодня' : '${fetchedAt.day}.${fetchedAt.month.toString().padLeft(2, '0')}'} в ${hm(fetchedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (!sameDay(_selected, DateTime.now()))
            IconButton(
              tooltip: 'Сегодня',
              icon: const Icon(Icons.today_outlined),
              onPressed: () => _goTo(DateTime.now()),
            ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
            ),
          ),
        ],
        bottom: state.loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          _WeekStrip(
            selected: _selected,
            firstDay: _firstDay,
            lastDay: _dayAt(_dayCount - 1),
            hasLessons: (d) => state.lessonsOn(d).any((l) => !l.cancelled),
            onSelect: _goTo,
          ),
          const Divider(height: 1),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _dayCount,
              onPageChanged: (i) => setState(() => _selected = _dayAt(i)),
              itemBuilder: (context, i) => RefreshIndicator(
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
    final theme = Theme.of(context);
    final monday = mondayOf(selected);
    final today = dateOnly(DateTime.now());
    final sunday = monday.add(const Duration(days: 6));
    final monthLabel = monday.month == sunday.month
        ? monthsGenitive[monday.month - 1]
        : '${monthsGenitive[monday.month - 1]} – ${monthsGenitive[sunday.month - 1]}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: monday.isAfter(firstDay)
                    ? () => onSelect(selected.subtract(const Duration(days: 7)))
                    : null,
              ),
              Expanded(
                child: Text(
                  '${monday.day} – ${sunday.day} $monthLabel',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: sunday.isBefore(lastDay)
                    ? () => onSelect(selected.add(const Duration(days: 7)))
                    : null,
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _DayChip(
                    day: monday.add(Duration(days: i)),
                    selected: sameDay(monday.add(Duration(days: i)), selected),
                    today: sameDay(monday.add(Duration(days: i)), today),
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

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.today,
    required this.dot,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected
        ? scheme.onPrimary
        : today
        ? scheme.primary
        : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(
                  weekdaysShort[day.weekday - 1],
                  style: TextStyle(
                    fontSize: 12,
                    color: fg.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot
                        ? (selected ? scheme.onPrimary : scheme.primary)
                        : Colors.transparent,
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

class _DayView extends StatelessWidget {
  const _DayView({required this.day, required this.lessons});

  final DateTime day;
  final List<Lesson> lessons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(dayTitle(day), style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Column(
              children: [
                Icon(
                  Icons.weekend_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'Пар нет',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          )
        else
          for (final l in lessons) LessonCard(lesson: l),
      ],
    );
  }
}

class LessonCard extends StatelessWidget {
  const LessonCard({super.key, required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final ongoing =
        !lesson.cancelled &&
        !now.isBefore(lesson.start) &&
        now.isBefore(lesson.end);
    final past = now.isAfter(lesson.end);
    final accent = kindColor(lesson.kind, scheme);
    final muted = lesson.cancelled || past;

    return Opacity(
      opacity: muted ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        color: ongoing ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showLessonSheet(context, lesson),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: accent),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 4, 14),
                  child: SizedBox(
                    width: 48,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hm(lesson.start),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          hm(lesson.end),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.subject,
                          style: theme.textTheme.titleSmall?.copyWith(
                            decoration: lesson.cancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (lesson.kind.isNotEmpty)
                              _Tag(text: lesson.kind, color: accent),
                            if (lesson.cancelled)
                              _Tag(text: 'отменена', color: scheme.error),
                            if (lesson.location.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    lesson.isRemote
                                        ? Icons.videocam_outlined
                                        : Icons.place_outlined,
                                    size: 14,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      lesson.location,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        if (lesson.lecturer.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            lesson.lecturer,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (ongoing) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Идёт сейчас · осталось ${lesson.end.difference(now).inMinutes + 1} мин',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
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

Color kindColor(String kind, ColorScheme scheme) => switch (kind) {
  'лекция' => scheme.primary,
  'семинар' => scheme.tertiary,
  _ => scheme.secondary,
};

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
    ),
  );
}
