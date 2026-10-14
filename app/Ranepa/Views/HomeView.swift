import SwiftUI
import TipKit

/// Главный экран как Календарь iPhone: месяц, «Сегодня» и аватар в одну
/// строку, под ними полоса недель, ниже лента пар выбранного дня.
/// На iPad вместо ленты — неделя колонками.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var selected = Clock.now.dateOnly
    @State private var dayPage: Int?
    /// Идёт программный переход к дню: промежуточные страницы не выбираются.
    @State private var jumping = false
    @State private var sheetLesson: Lesson?
    @State private var showAccount = false
    @State private var banner: Banner?
    /// Перерисовка раз в минуту: «идёт сейчас» и «ещё N мин».
    @State private var minute = Date()

    private var firstDay: Date { state.firstDay }
    private func dayAt(_ i: Int) -> Date { firstDay.adding(days: i) }
    private func index(of day: Date) -> Int { min(max(day.days(since: firstDay), 0), state.dayCount - 1) }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    WeekColumns(week: selected.monday, open: { sheetLesson = $0 })
                } else {
                    dayPager
                }
            }
            .background(Color(.systemGroupedBackground))
            // Мягкий край под строкой «Обновлено…»: лента вложена в листание
            // дней, и система не находит её, чтобы размыть край сама.
            .overlay {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(colors: [Color(.systemGroupedBackground).opacity(0),
                                                Color(.systemGroupedBackground)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                        Color(.systemGroupedBackground)
                            .frame(height: geometry.safeAreaInsets.bottom + 8)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                .allowsHitTesting(false)
            }
            .safeAreaBar(edge: .top) { header }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                // Строка состояния без подложки, как в Почте: лента уходит
                // под неё в фон (см. overlay выше).
                ToolbarItem(placement: .status) {
                    status.fixedSize()
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .overlay(alignment: .top) {
                if let banner {
                    BannerView(banner: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { withAnimation { self.banner = nil } }
                }
            }
        }
        .sheet(item: $sheetLesson) { LessonSheet(lesson: $0) }
        .sheet(isPresented: $showAccount) { AccountView() }
        .onAppear {
            dayPage = index(of: selected)
            openPendingLesson()
        }
        .task {
            await state.refresh(.open)
            await state.showLiveActivity()
            await state.checkNotifications(request: true)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60 - Double(Calendar.current.component(.second, from: .now))))
                minute = Date()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await state.resumed() } }
        }
        .onChange(of: dayPage) { _, page in
            if !jumping, let page { selected = dayAt(page) }
        }
        .onChange(of: state.pendingLesson) { openPendingLesson() }
        .onChange(of: state.pendingChanges) { _, changes in
            guard !changes.isEmpty else { return }
            state.pendingChanges = []
            show(Banner(title: changes.count == 1 ? "Изменение в расписании" : "Изменения в расписании",
                        message: changes.joined(separator: "\n"), symbol: "calendar.badge.exclamationmark"),
                 for: 8)
        }
        .onChange(of: state.error) { _, error in
            guard let error, !state.loading else { return }
            show(Banner(title: "Не удалось обновить", message: error, symbol: "exclamationmark.circle.fill"), for: 5)
        }
    }

    private func show(_ banner: Banner, for seconds: Double) {
        withAnimation(.snappy) { self.banner = banner }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            withAnimation(.snappy) { if self.banner == banner { self.banner = nil } }
        }
    }

    /// Как в Календаре: к дальнему дню — один сдвиг страницы, без
    /// пролистывания всех промежуточных дней.
    private func goTo(_ day: Date) {
        let target = index(of: day)
        selected = dayAt(target)
        guard sizeClass != .regular, let current = dayPage, target != current else { return }
        jumping = true
        if abs(target - current) > 1 {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dayPage = target > current ? target - 1 : target + 1 }
        }
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.3)) { dayPage = target } completion: { jumping = false }
        }
    }

    /// Нажали на напоминание, Live Activity или виджет: день пары и её карточка.
    private func openPendingLesson() {
        guard let start = state.pendingLesson else { return }
        state.pendingLesson = nil
        guard let lesson = state.lessons.first(where: { abs($0.start.timeIntervalSince(start)) < 60 }) else { return }
        showAccount = false
        goTo(lesson.start)
        sheetLesson = lesson
    }

    /// Пролистали месяц: сегодня, если это текущий месяц, иначе 1-е число.
    private func goToMonth(_ month: Date) {
        let now = Clock.now
        goTo(month.year == now.year && month.month == now.month ? now : max(month, firstDay))
    }

    private var months: [Date] {
        let last = dayAt(state.dayCount - 1)
        var result: [Date] = []
        var m = calendar.date(from: calendar.dateComponents([.year, .month], from: firstDay))!
        while m <= last {
            result.append(m)
            m = calendar.date(byAdding: .month, value: 1, to: m)!
        }
        return result
    }

    // MARK: Шапка

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                MonthPager(months: months, selected: selected, onSwipe: goToMonth)
                if !selected.sameDay(Clock.now) {
                    Button("Сегодня") { goTo(Clock.now) }
                        .buttonStyle(.glass)
                        .transition(.opacity)
                }
                Button {
                    AccountTip().invalidate(reason: .actionPerformed)
                    showAccount = true
                } label: {
                    AvatarView(size: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Аккаунт и настройки")
            }
            .padding(.horizontal, 16)
            .animation(.snappy, value: selected.sameDay(Clock.now))
            // Крупный заголовок растёт со шрифтом меньше текста, как в системных
            // приложениях.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            WeekPager(selected: selected, firstDay: firstDay, weeks: state.dayCount / 7,
                      hasLessons: { day in state.lessons(on: day).contains { !$0.cancelled } },
                      onSelect: { goTo($0) })
                // Семь дней в ряд: крупнее числа не помещаются.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .padding(.bottom, 6)
    }

    private var status: some View {
        HStack(spacing: 6) {
            if state.loading {
                ProgressView().controlSize(.mini)
                Text("Обновление…")
            } else {
                Text(statusText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var statusText: String {
        guard let at = state.fetchedAt else { return "Расписание ещё не загружено" }
        let today = at.sameDay(Clock.now)
        // На паузе без объяснений про ЛК: по дате видно, насколько данные старые.
        if state.syncPaused { return "Расписание от \(today ? "" : "\(shortDate(at)), ")\(hm(at))" }
        return "Обновлено \(today ? "сегодня" : shortDate(at)) в \(hm(at))"
    }

    // MARK: Лента дней

    private var dayPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<state.dayCount, id: \.self) { i in
                    DayPage(day: dayAt(i), minute: minute, open: { sheetLesson = $0 })
                        .containerRelativeFrame(.horizontal)
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $dayPage)
        .scrollIndicators(.hidden)
    }
}

/// Пары одного дня: карточка «Сейчас» (сегодня), лента с перерывами.
private struct DayPage: View {
    @Environment(AppState.self) private var state
    let day: Date
    let minute: Date
    let open: (Lesson) -> Void

    /// Подсказки по одной, по порядку.
    @State private var tips = TipGroup(.ordered) {
        RefreshTip()
        AccountTip()
    }

    var body: some View {
        let lessons = state.lessons(on: day)
        let isToday = day.sameDay(Clock.now)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !lessons.isEmpty || isToday {
                    TipView(tips.currentTip)
                        .padding(.bottom, 12)
                }
                if isToday {
                    NowCard(today: lessons.filter { !$0.cancelled },
                            next: state.next(after: Clock.now), open: open)
                        .padding(.bottom, 20)
                }
                if lessons.isEmpty && !isToday {
                    ContentUnavailableView {
                        Label("Пар нет", systemImage: "moon.zzz")
                    } description: {
                        if let next = state.next(after: day.adding(days: 1)) {
                            Text("Следующая \(whenLabel(next.start))")
                        }
                    }
                    .padding(.top, 40)
                }
                ForEach(Array(lessons.enumerated()), id: \.element.id) { i, lesson in
                    if i > 0 { GapRow(from: lessons[i - 1].end, to: lesson.start) }
                    TimelineRow(lesson: lesson, now: Clock.now) { open(lesson) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .id(minute)
        }
        .refreshable {
            RefreshTip().invalidate(reason: .actionPerformed)
            await state.refresh(.manual)
        }
    }
}

/// Карточка «Сейчас»: идущая пара, следующая или итог дня.
struct NowCard: View {
    let today: [Lesson]
    let next: Lesson?
    let open: (Lesson) -> Void

    var body: some View {
        let now = Clock.now
        let current = today.first { $0.start <= now && now < $0.end }
        let upcoming = today.first { $0.start > now }
        let target = current ?? upcoming ?? next

        Button { if let target { open(target) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Не помещается в строку (крупный шрифт) — «ещё 40 мин» под подписью.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        captionText(current: current, upcoming: upcoming)
                        Spacer()
                        trailingText(current: current, upcoming: upcoming, now: now)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        captionText(current: current, upcoming: upcoming)
                        trailingText(current: current, upcoming: upcoming, now: now)
                    }
                }
                .padding(.bottom, 6)
                if let current {
                    Text(current.subject).font(.title3.weight(.semibold))
                    lessonDetails(current).font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)
                    ProgressView(value: min(max(now.timeIntervalSince(current.start)
                        / current.end.timeIntervalSince(current.start), 0), 1))
                        .padding(.top, 12)
                    Text(upcoming.map { "Дальше в \(hm($0.start)) — \($0.subject)" } ?? "Это последняя пара сегодня")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 10)
                } else if let upcoming {
                    Text(upcoming.subject).font(.title3.weight(.semibold))
                    Text("\(hm(upcoming.start))–\(hm(upcoming.end)) · \(lessonDetails(upcoming))")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)
                } else if let next {
                    Text("Следующая \(whenLabel(next.start))").font(.title3.weight(.semibold))
                    Text(next.subject).font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)
                } else {
                    Text("Отдыхай").font(.title3.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
    }

    private func captionText(current: Lesson?, upcoming: Lesson?) -> some View {
        Text(caption(current: current, upcoming: upcoming))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tint)
            .fixedSize()
    }

    @ViewBuilder
    private func trailingText(current: Lesson?, upcoming: Lesson?, now: Date) -> some View {
        if let trailing = trailing(current: current, upcoming: upcoming, now: now) {
            Text(trailing).font(.footnote).foregroundStyle(.secondary).fixedSize()
        }
    }

    private func caption(current: Lesson?, upcoming: Lesson?) -> String {
        if current != nil { return "СЕЙЧАС" }
        if upcoming != nil { return "ДАЛЕЕ" }
        return today.isEmpty ? "СЕГОДНЯ ПАР НЕТ" : "ПАРЫ ЗАКОНЧИЛИСЬ"
    }

    private func trailing(current: Lesson?, upcoming: Lesson?, now: Date) -> String? {
        if let current { return "ещё \(durationText(current.end.timeIntervalSince(now) + 60))" }
        if let upcoming {
            let wait = upcoming.start.timeIntervalSince(now)
            return wait < 2 * 3600 ? "через \(durationText(wait + 60))" : "в \(hm(upcoming.start))"
        }
        return nil
    }
}

/// Пара в ленте: время столбиком слева, цветная полоска, название.
struct TimelineRow: View {
    let lesson: Lesson
    let now: Date
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = 48
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let ongoing = lesson.isOngoing(at: now)
        let dimmed = lesson.cancelled || now > lesson.end
        Button(action: action) {
            // На крупных размерах шрифта время встаёт над названием, иначе
            // колонка времени съедает ширину и название рвётся по слогам.
            if typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(kindColor(lesson.kind))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hm(lesson.start))–\(hm(lesson.end))")
                            .font(.subheadline.weight(ongoing ? .semibold : .medium))
                            .foregroundStyle(ongoing ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(lesson.subject)
                            .font(.body.weight(ongoing ? .semibold : .regular))
                            .strikethrough(lesson.cancelled)
                        lessonDetails(lesson, icon: true).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .contentShape(.rect)
            } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(hm(lesson.start))
                        .font(.subheadline.weight(ongoing ? .semibold : .medium))
                        .foregroundStyle(ongoing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Text(hm(lesson.end)).font(.footnote).foregroundStyle(.secondary)
                }
                .frame(width: timeWidth, alignment: .trailing)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(kindColor(lesson.kind))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(lesson.subject)
                        .font(.body.weight(ongoing ? .semibold : .regular))
                        .strikethrough(lesson.cancelled)
                    lessonDetails(lesson, icon: true).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
            .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.45 : 1)
        // VoiceOver читает строку целиком: «10:40–12:00, Иностранный язык,
        // семинар, 1 - 2317, идёт сейчас».
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            "\(hm(lesson.start))–\(hm(lesson.end))", lesson.subject, lesson.kind,
            lesson.isRemote ? "дистанционно" : lesson.shortLocation,
            lesson.cancelled ? "отменена" : "", ongoing ? "идёт сейчас" : "",
        ].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// «Перерыв 20 мин» или «Окно 1 ч 40 мин» между парами.
struct GapRow: View {
    let from: Date
    let to: Date
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = 48
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let gap = to.timeIntervalSince(from)
        if gap > 0 {
            Text("\(gap >= 3600 ? "Окно" : "Перерыв") \(durationText(gap))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.leading, typeSize.isAccessibilitySize ? 13 : timeWidth + 23)
                .padding(.vertical, 2)
        } else {
            Spacer().frame(height: 4)
        }
    }
}
