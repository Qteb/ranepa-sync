import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../services/lesson_links.dart';
import '../services/notifications.dart';
import '../services/tips.dart';
import '../widgets/avatar.dart';
import '../widgets/banner.dart';
import '../widgets/lesson_colors.dart';
import '../widgets/tip_card.dart';
import 'account_sheet.dart';
import 'lesson_sheet.dart';

part 'home_wide.dart';

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

  /// Идёт программный переход к дню: промежуточные страницы не выбираются.
  bool _jumping = false;
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
    _firstDay = mondayOf(currentTime());
    _selected = dateOnly(currentTime());
    _pages = PageController(initialPage: _indexOf(_selected));
    // Перерисовка раз в минуту: «идёт сейчас» и «ещё N мин».
    _ticker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
    state.addListener(_onState);
    pendingLesson.addListener(_openPendingLesson);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingLesson());
    state.refresh(SyncTrigger.open);
    state.showLiveActivity();
    // Системный запрос — только если пользователь ещё не отвечал.
    state.checkNotifications(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.removeListener(_onState);
    pendingLesson.removeListener(_openPendingLesson);
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
    removeStaleReminders();
    state.showLiveActivity();
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

  /// Нажали на напоминание, Live Activity или виджет: день пары и её
  /// карточка поверх.
  void _openPendingLesson() {
    final start = pendingLesson.value;
    if (start == null || !mounted) return;
    pendingLesson.value = null;
    final lesson = state.lessons
        .where((l) => l.start.difference(start).inMinutes.abs() < 1)
        .firstOrNull;
    if (lesson == null) return;
    // Убрать открытые листы, чтобы карточка не легла поверх другой.
    Navigator.of(context).popUntil((r) => r.isFirst);
    _goTo(lesson.start);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLessonSheet(context, lesson);
    });
  }

  int _indexOf(DateTime day) =>
      dateOnly(day).difference(_firstDay).inDays.clamp(0, _dayCount - 1);

  DateTime _dayAt(int index) => _firstDay.add(Duration(days: index));

  void _goTo(DateTime day) {
    // На iPad листаются недели, а не страницы дней.
    if (!_pages.hasClients) {
      final target = dateOnly(day);
      if (target.isBefore(_firstDay) || target.isAfter(_dayAt(_dayCount - 1))) {
        return;
      }
      setState(() => _selected = target);
      return;
    }
    // Как в Календаре: к дальнему дню — один сдвиг страницы, без
    // пролистывания всех промежуточных дней.
    final target = _indexOf(day);
    final current = _pages.page?.round() ?? target;
    if (target == current) return;
    setState(() => _selected = _dayAt(target));
    _jumping = true;
    if ((target - current).abs() > 1) {
      _pages.jumpToPage(target > current ? target - 1 : target + 1);
    }
    _pages
        .animateToPage(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _jumping = false);
  }

  /// Месяцы, в которые попадает загруженное расписание.
  List<DateTime> get _months {
    final last = _dayAt(_dayCount - 1);
    return [
      for (
        var m = DateTime(_firstDay.year, _firstDay.month);
        !m.isAfter(last);
        m = DateTime(m.year, m.month + 1)
      )
        m,
    ];
  }

  /// Пролистали месяц: сегодня, если это текущий месяц, иначе 1-е число.
  void _goToMonth(DateTime month) {
    final now = currentTime();
    _goTo(
      month.year == now.year && month.month == now.month
          ? now
          : month.isBefore(_firstDay)
          ? _firstDay
          : month,
    );
  }

  String get _status {
    final at = state.fetchedAt;
    if (at == null) return 'Расписание ещё не загружено';
    if (state.syncPaused) {
      // Без объяснений про ЛК: по дате видно, насколько данные старые.
      final day = sameDay(at, currentTime())
          ? ''
          : '${at.day}.${at.month.toString().padLeft(2, '0')}, ';
      return 'Расписание от $day${hm(at)}';
    }
    final day = sameDay(at, currentTime())
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
    final isToday = sameDay(_selected, currentTime());
    final width = MediaQuery.sizeOf(context).width;
    if (width >= _wideFrom) {
      return _WideHome(
        state: state,
        selected: _selected,
        firstDay: _firstDay,
        lastDay: _dayAt(_dayCount - 1),
        status: _status,
        loadingQuietly: state.loading && !_pulling,
        nextAfter: _nextAfter,
        onSelect: _goTo,
        onRefresh: _pullToRefresh,
        width: width,
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Строка «Обновлено…» внизу, над полосой «домой», как в Почте.
    final statusHeight =
        scaler.clamp(maxScaleFactor: 1.3).scale(16) + 16 + bottomInset;
    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Как в Календаре: месяц, «Сегодня» и аватар в одну строку.
                // Шапка растёт со шрифтом меньше остального, как в системных
                // приложениях.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MonthTitle(
                            months: _months,
                            selected: _selected,
                            onSwipe: _goToMonth,
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: isToday
                              ? const SizedBox.shrink()
                              : _TodayButton(
                                  onPressed: () => _goTo(currentTime()),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Аккаунт и настройки',
                          child: GestureDetector(
                            onTap: () {
                              Tips.instance.done(Tip.account);
                              showAccountSheet(context, state);
                            },
                            // Высота как у кнопки «Сегодня»: шапка не
                            // прыгает, когда та появляется.
                            child: SizedBox(
                              height: 44,
                              child: Center(
                                child: Avatar(state: state, size: 36),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _WeekPager(
                  selected: _selected,
                  firstDay: _firstDay,
                  weeks: _dayCount ~/ 7,
                  hasLessons: (d) =>
                      state.lessonsOn(d).any((l) => !l.cancelled),
                  onSelect: _goTo,
                ),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                    child: Text(
                      '${relativeDayName(_selected)}, '
                      '${_selected.day} ${monthsGenitive[_selected.month - 1]}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: label,
                      ),
                    ),
                  ),
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
                              child: MediaQuery.withClampedTextScaling(
                                // Подсказка над лентой не должна вытеснять пары.
                                maxScaleFactor: 1.3,
                                child: TipCard(
                                  tip: tip,
                                  icon: tip == Tip.refresh
                                      ? CupertinoIcons.arrow_down_circle
                                      : CupertinoIcons.person_crop_circle,
                                ),
                              ),
                            ),
                    );
                  },
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _dayCount,
                    onPageChanged: (i) {
                      if (!_jumping) setState(() => _selected = _dayAt(i));
                    },
                    itemBuilder: (context, i) {
                      final day = _dayAt(i);
                      return _DayView(
                        onRefresh: _pullToRefresh,
                        day: day,
                        lessons: state.lessonsOn(day),
                        next: _nextAfter(
                          sameDay(day, currentTime())
                              ? currentTime()
                              : dateOnly(day).add(const Duration(days: 1)),
                        ),
                        bottomInset: statusHeight,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: statusHeight,
            child: _StatusBar(
              text: _status,
              loading: state.loading && !_pulling,
              bottomInset: bottomInset,
            ),
          ),
        ],
      ),
    );
  }
}

/// «Сегодня» капсулой, как в Календаре; видна, когда ушли с сегодняшнего дня.
class _TodayButton extends StatelessWidget {
  const _TodayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
          context,
        ),
      ),
      child: Text(
        'Сегодня',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: CupertinoTheme.of(context).primaryColor,
        ),
      ),
    ),
  );
}

/// Строка внизу экрана: когда обновлялось расписание или что оно обновляется.
/// Лента прокручивается под ней, размытая, как под панелями iOS.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.text,
    required this.loading,
    required this.bottomInset,
  });

  final String text;
  final bool loading;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final background = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: background.withValues(alpha: 0.8),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading) ...[
                    const CupertinoActivityIndicator(radius: 6),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      loading ? 'Обновление…' : text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Название месяца листается пальцем, как в Календаре: соседний месяц
/// выезжает следом, полоса дней переходит к нему.
class _MonthTitle extends StatefulWidget {
  const _MonthTitle({
    required this.months,
    required this.selected,
    required this.onSwipe,
  });

  final List<DateTime> months;
  final DateTime selected;
  final void Function(DateTime month) onSwipe;

  @override
  State<_MonthTitle> createState() => _MonthTitleState();
}

class _MonthTitleState extends State<_MonthTitle> {
  late final _pages = PageController(initialPage: _indexOf(widget.selected));
  bool _following = false;

  int _indexOf(DateTime day) => widget.months
      .indexWhere((m) => m.year == day.year && m.month == day.month)
      .clamp(0, widget.months.length - 1);

  @override
  void didUpdateWidget(_MonthTitle old) {
    super.didUpdateWidget(old);
    final index = _indexOf(widget.selected);
    if (!_pages.hasClients || _pages.page?.round() == index) return;
    _following = true;
    _pages
        .animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _following = false);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final style = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.36,
      color: label,
    );
    final now = currentTime();
    return SizedBox(
      height: MediaQuery.textScalerOf(context).scale(36),
      child: PageView.builder(
        controller: _pages,
        itemCount: widget.months.length,
        onPageChanged: (i) {
          if (!_following) widget.onSwipe(widget.months[i]);
        },
        itemBuilder: (context, i) {
          final month = widget.months[i];
          final name = monthsNominative[month.month - 1];
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              month.year == now.year ? name : '$name ${month.year}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          );
        },
      ),
    );
  }
}

/// Полоса недель как в Календаре: листается неделями за пальцем, выбор
/// остаётся на том же дне недели. Если выбранный день ушёл в другую неделю
/// (листали пары, «Сегодня»), полоса перелистывается сама.
class _WeekPager extends StatefulWidget {
  const _WeekPager({
    required this.selected,
    required this.firstDay,
    required this.weeks,
    required this.hasLessons,
    required this.onSelect,
  });

  final DateTime selected;

  /// Понедельник первой недели.
  final DateTime firstDay;
  final int weeks;
  final bool Function(DateTime) hasLessons;
  final void Function(DateTime) onSelect;

  @override
  State<_WeekPager> createState() => _WeekPagerState();
}

class _WeekPagerState extends State<_WeekPager> {
  late final _pages = PageController(initialPage: _weekOf(widget.selected));

  /// Полоса догоняет выбранный день: промежуточные недели не выбираются.
  bool _following = false;

  int _weekOf(DateTime day) =>
      (dateOnly(day).difference(widget.firstDay).inDays ~/ 7).clamp(
        0,
        widget.weeks - 1,
      );

  @override
  void didUpdateWidget(_WeekPager old) {
    super.didUpdateWidget(old);
    final week = _weekOf(widget.selected);
    final current = _pages.hasClients ? _pages.page?.round() : null;
    if (current == null || current == week) return;
    _following = true;
    if ((week - current).abs() > 1) {
      _pages.jumpToPage(week > current ? week - 1 : week + 1);
    }
    _pages
        .animateToPage(
          week,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _following = false);
  }

  /// Свайп недели: тот же день недели в новой неделе.
  void _onPage(int week) {
    if (_following || week == _weekOf(widget.selected)) return;
    widget.onSelect(
      widget.firstDay.add(
        Duration(days: week * 7 + widget.selected.weekday - 1),
      ),
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Семь дней в ряд: крупнее ×1.3 цифры не помещаются.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Builder(
        builder: (context) {
          final scaler = MediaQuery.textScalerOf(context);
          final height = scaler.scale(16) + 4 + scaler.scale(34) + 7 + 14;
          return SizedBox(
            height: height,
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.weeks,
              onPageChanged: _onPage,
              itemBuilder: (context, week) =>
                  _week(context, widget.firstDay.add(Duration(days: week * 7))),
            ),
          );
        },
      ),
    );
  }

  Widget _week(BuildContext context, DateTime monday) {
    Widget cell(int i) {
      final day = monday.add(Duration(days: i));
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ExcludeSemantics(
                child: Text(
                  weekdaysShort[i],
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _Day(
                day: day,
                selected: sameDay(day, widget.selected),
                dot: widget.hasLessons(day),
                onTap: () => widget.onSelect(day),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < 5; i++) cell(i),
          // Выходные на общей подложке: видно, где кончается неделя.
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(children: [cell(5), cell(6)]),
            ),
          ),
        ],
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
    final today = sameDay(day, currentTime());
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
    final size = MediaQuery.textScalerOf(context).scale(34);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${today ? 'Сегодня, ' : ''}${weekdaysLong[day.weekday - 1]}, '
          '${day.day} ${monthsGenitive[day.month - 1]}'
          '${dot ? '' : ', пар нет'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: size,
              height: size,
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
    required this.bottomInset,
  });

  final Future<void> Function() onRefresh;
  final DateTime day;
  final List<Lesson> lessons;

  /// Ближайшая пара после этого дня (или после «сейчас» для сегодня).
  final Lesson? next;

  /// Высота строки статуса внизу экрана: лента прокручивается под ней.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final isToday = sameDay(day, currentTime());
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
          padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + bottomInset),
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
    final now = currentTime();
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

    return Semantics(
      button: tapTarget != null,
      container: true,
      child: GestureDetector(
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
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 15, color: secondary),
                ),
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
      ),
    );
  }
}

/// Подпись под названием: тип цветом типа, остальное серым. С [icon] —
/// иконка типа перед словом (лента на iPhone).
TextSpan _details(Lesson l, BuildContext context, {bool icon = false}) {
  final color = LessonColors.of(l.kind).text.resolveFrom(context);
  final rest = [
    if (l.location.isNotEmpty) l.isRemote ? 'дистанционно' : l.shortLocation,
    if (l.cancelled) 'отменена',
  ].join(' · ');
  return TextSpan(
    children: [
      if (l.kind.isNotEmpty && icon)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(LessonColors.iconOf(l.kind), size: 14, color: color),
          ),
        ),
      if (l.kind.isNotEmpty)
        TextSpan(
          text: capitalize(l.kind),
          style: TextStyle(color: color),
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
    final now = currentTime();
    final ongoing =
        !lesson.cancelled &&
        !now.isBefore(lesson.start) &&
        now.isBefore(lesson.end);
    final dimmed = lesson.cancelled || now.isAfter(lesson.end);
    final accent = CupertinoTheme.of(context).primaryColor;
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    final scale = MediaQuery.textScalerOf(context);
    // VoiceOver читает строку целиком: «10:40–12:00, Иностранный язык,
    // семинар, 1 - 2317, идёт сейчас».
    return Semantics(
      button: true,
      label: [
        '${hm(lesson.start)}–${hm(lesson.end)}',
        lesson.subject,
        if (lesson.kind.isNotEmpty) lesson.kind,
        lesson.isRemote ? 'дистанционно' : lesson.shortLocation,
        if (lesson.cancelled) 'отменена',
        if (ongoing) 'идёт сейчас',
      ].join(', '),
      excludeSemantics: true,
      child: GestureDetector(
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
                    width: scale.scale(48),
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
                          _details(lesson, context, icon: true),
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
      padding: EdgeInsets.only(
        left: MediaQuery.textScalerOf(context).scale(48) + 23,
        top: 2,
        bottom: 2,
      ),
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
