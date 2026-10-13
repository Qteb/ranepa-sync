part of 'home_screen.dart';

/// Ширина, с которой главный экран показывает неделю колонками (iPad).
const _wideFrom = 700.0;

/// С этой ширины слева появляется сайдбар (iPad в альбомной ориентации).
const _sidebarFrom = 1100.0;

const _sidebarWidth = 320.0;

/// iPad: вся неделя колонками карточек. В альбомной ориентации слева
/// сайдбар с карточкой «Сейчас» и календарём загруженных недель,
/// в портретной карточка «Сейчас» стоит над неделей.
class _WideHome extends StatelessWidget {
  const _WideHome({
    required this.state,
    required this.selected,
    required this.firstDay,
    required this.lastDay,
    required this.status,
    required this.loadingQuietly,
    required this.nextAfter,
    required this.onSelect,
    required this.onRefresh,
    required this.width,
  });

  final AppState state;
  final DateTime selected;
  final DateTime firstDay;
  final DateTime lastDay;
  final String status;
  final bool loadingQuietly;
  final Lesson? Function(DateTime) nextAfter;
  final void Function(DateTime) onSelect;
  final Future<void> Function() onRefresh;
  final double width;

  @override
  Widget build(BuildContext context) {
    final now = currentTime();
    final today = state.lessonsOn(now).where((l) => !l.cancelled).toList();
    final nowCard = _NowCard(today: today, next: nextAfter(now));
    final header = _TodayHeader(state: state, loading: loadingQuietly);
    final sidebar = width >= _sidebarFrom;

    final week = _WeekPane(
      state: state,
      selected: selected,
      firstDay: firstDay,
      lastDay: lastDay,
      status: status,
      onSelect: onSelect,
      onRefresh: onRefresh,
      // В портретной ориентации «Сейчас» прокручивается вместе с неделей.
      top: sidebar
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  nowCard,
                  const _HomeTip(padding: EdgeInsets.only(top: 12)),
                ],
              ),
            ),
    );

    return Scaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      body: SafeArea(
        bottom: false,
        child: sidebar
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _sidebarWidth,
                    child: _Sidebar(
                      header: header,
                      nowCard: nowCard,
                      calendar: _RangeCalendar(
                        state: state,
                        selected: selected,
                        firstDay: firstDay,
                        lastDay: lastDay,
                        onSelect: onSelect,
                      ),
                    ),
                  ),
                  Container(
                    width: 0.5,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  Expanded(child: week),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: header,
                  ),
                  Expanded(child: week),
                ],
              ),
      ),
    );
  }
}

/// «ВТОРНИК, 13 ОКТЯБРЯ / Сегодня» и аватар.
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.state, required this.loading});

  final AppState state;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final now = currentTime();
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${weekdaysLong[now.weekday - 1]}, '
                            '${now.day} ${monthsGenitive[now.month - 1]}'
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                  if (loading) ...[
                    const SizedBox(width: 6),
                    const CupertinoActivityIndicator(radius: 6),
                  ],
                ],
              ),
              Text(
                'Сегодня',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.37,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _AvatarButton(state: state),
      ],
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => Semantics(
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
  );
}

/// Подсказка по одной, как на iPhone.
class _HomeTip extends StatelessWidget {
  const _HomeTip({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Tips.instance,
    builder: (context, _) {
      final tip = Tips.instance.nextOnHome;
      return AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: tip == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: padding,
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
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.header,
    required this.nowCard,
    required this.calendar,
  });

  final Widget header;
  final Widget nowCard;
  final Widget calendar;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    ),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        header,
        const SizedBox(height: 16),
        // Карточка на фоне сайдбара: тот же цвет, что у сайдбара, не виден.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
          child: nowCard,
        ),
        const _HomeTip(padding: EdgeInsets.only(top: 12)),
        const SizedBox(height: 24),
        calendar,
      ],
    ),
  );
}

/// Загруженные недели одной сеткой: нажатие открывает неделю.
class _RangeCalendar extends StatelessWidget {
  const _RangeCalendar({
    required this.state,
    required this.selected,
    required this.firstDay,
    required this.lastDay,
    required this.onSelect,
  });

  final AppState state;
  final DateTime selected;
  final DateTime firstDay;
  final DateTime lastDay;
  final void Function(DateTime) onSelect;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final weeks = lastDay.difference(firstDay).inDays ~/ 7 + 1;
    final selectedWeek = mondayOf(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'РАСПИСАНИЕ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in weekdaysShort)
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < weeks; w++)
          Builder(
            builder: (context) {
              final monday = firstDay.add(Duration(days: 7 * w));
              final current = sameDay(monday, selectedWeek);
              return Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: current
                      ? CupertinoColors.tertiarySystemFill.resolveFrom(context)
                      : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _Day(
                          day: monday.add(Duration(days: i)),
                          selected: false,
                          dot: state
                              .lessonsOn(monday.add(Duration(days: i)))
                              .any((l) => !l.cancelled),
                          onTap: () => onSelect(monday.add(Duration(days: i))),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Неделя колонками: заголовок с листанием и дни с карточками пар.
class _WeekPane extends StatelessWidget {
  const _WeekPane({
    required this.state,
    required this.selected,
    required this.firstDay,
    required this.lastDay,
    required this.status,
    required this.onSelect,
    required this.onRefresh,
    this.top,
  });

  final AppState state;
  final DateTime selected;
  final DateTime firstDay;
  final DateTime lastDay;
  final String status;
  final void Function(DateTime) onSelect;
  final Future<void> Function() onRefresh;

  /// Над неделей в портретной ориентации: карточка «Сейчас» и подсказка.
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final monday = mondayOf(selected);
    final sunday = monday.add(const Duration(days: 6));
    final label = CupertinoColors.label.resolveFrom(context);
    final isThisWeek = sameDay(monday, mondayOf(currentTime()));
    final canBack = monday.isAfter(firstDay);
    final canForward = sunday.isBefore(lastDay);
    // Воскресенье — только если в него есть пары.
    final days = [
      for (var i = 0; i < 7; i++)
        if (i < 6 || state.lessonsOn(sunday).isNotEmpty)
          monday.add(Duration(days: i)),
    ];

    void shift(int weeks) {
      final target = selected.add(Duration(days: 7 * weeks));
      if (!target.isBefore(firstDay) && !target.isAfter(lastDay)) {
        onSelect(target);
      }
    }

    final title = monday.month == sunday.month
        ? '${monday.day}–${sunday.day} ${monthsGenitive[sunday.month - 1]}'
        : '${monday.day} ${monthsGenitive[monday.month - 1]} – '
              '${sunday.day} ${monthsGenitive[sunday.month - 1]}';

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) shift(1);
        if (v > 300) shift(-1);
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: onRefresh),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: SliverList.list(
              children: [
                ?top,
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: label,
                        ),
                      ),
                    ),
                    if (!isThisWeek)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onPressed: () => onSelect(currentTime()),
                        child: const Text('Сегодня'),
                      ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: canBack ? () => shift(-1) : null,
                      child: const Icon(CupertinoIcons.chevron_left, size: 22),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: canForward ? () => shift(1) : null,
                      child: const Icon(CupertinoIcons.chevron_right, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < days.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _WeekDayColumn(
                          day: days[i],
                          lessons: state.lessonsOn(days[i]),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
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
      ),
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({required this.day, required this.lessons});

  final DateTime day;
  final List<Lesson> lessons;

  @override
  Widget build(BuildContext context) {
    final today = sameDay(day, currentTime());
    final accent = CupertinoTheme.of(context).primaryColor;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final label = CupertinoColors.label.resolveFrom(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${weekdaysShort[day.weekday - 1]} ',
                  style: TextStyle(color: today ? accent : secondary),
                ),
                TextSpan(
                  text: '${day.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: today ? accent : label,
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'Пар нет',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context),
              ),
            ),
          ),
        for (final l in lessons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WeekLessonCard(lesson: l),
          ),
      ],
    );
  }
}

/// Пара в колонке недели: время, название, тип и аудитория.
class _WeekLessonCard extends StatelessWidget {
  const _WeekLessonCard({required this.lesson});

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

    return GestureDetector(
      onTap: () => showLessonSheet(context, lesson),
      child: Opacity(
        opacity: dimmed ? 0.45 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            borderRadius: BorderRadius.circular(12),
            border: ongoing ? Border.all(color: accent, width: 1.5) : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Иконка типа вместо полоски: в узкой колонке
                        // она не отнимает ширину у названия.
                        Row(
                          children: [
                            Icon(
                              LessonColors.iconOf(lesson.kind),
                              size: 15,
                              color: LessonColors.of(lesson.kind).bar
                                  .resolveFrom(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeRange(lesson),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: ongoing
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: ongoing ? accent : secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lesson.subject,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: label,
                            decoration: lesson.cancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          _details(lesson, context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: secondary),
                        ),
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
