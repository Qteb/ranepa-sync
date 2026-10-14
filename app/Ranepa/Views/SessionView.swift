import SwiftUI

/// Карточка «Сессия через 13 дней» над лентой сегодняшнего дня.
struct ExamCard: View {
    let session: ExamSession
    let open: () -> Void

    var body: some View {
        let now = Clock.now
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "graduationcap.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(kindColor("экзамен")))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(now)).font(.headline).foregroundStyle(Color(.label))
                    Text(subtitle(now))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открывает список зачётов и экзаменов")
    }

    private func title(_ now: Date) -> String {
        guard let first = session.firstDate, !session.isRunning(now: now) else { return "Сессия идёт" }
        return "Сессия \(daysUntil(first, from: now))"
    }

    private func subtitle(_ now: Date) -> String {
        if session.isRunning(now: now), let next = session.nextEvent {
            return "\(next.kind.capitalizedFirst) \(whenLabel(next.start)) · \(next.subject)"
        }
        return [session.dates, session.summary].filter { !$0.isEmpty }.joined(separator: " · ").capitalizedFirst
    }
}

/// Вкладка «Сессия»: ближайшая сессия по плану — экзамены карточками,
/// зачёты списком, сданное — внизу.
struct SessionTab: View {
    @Environment(AppState.self) private var state
    @State private var lesson: Lesson?
    @State private var showAccount = false

    var body: some View {
        let now = Clock.now
        NavigationStack {
            Group {
                if let session = state.session {
                    content(session, now: now)
                } else {
                    ContentUnavailableView("Сессии пока нет", systemImage: "graduationcap",
                                           description: Text("Даты сессии появятся, когда загрузится план обучения."))
                }
            }
            .navigationTitle("Сессия")
            .routes()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAccount = true } label: { AvatarView(size: 36) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Аккаунт и настройки")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .sheet(item: $lesson) { LessonSheet(lesson: $0) }
        .sheet(isPresented: $showAccount) { AccountView() }
    }

    private func content(_ session: ExamSession, now: Date) -> some View {
        let running = session.isRunning(now: now)
        let exams = session.exams.filter { !session.isDone($0, now: now) }
        let credits = session.credits.filter { !session.isDone($0, now: now) }
        let done = session.all.filter { session.isDone($0, now: now) }
        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(running
                         ? "\(session.dates) · осталось \(session.remaining(now: now)) из \(session.all.count)"
                         : [session.dates, session.summary].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    if let when = countdown(session, running: running, now: now) {
                        Text(when).font(.headline).foregroundStyle(Color.accentColor)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            if !exams.isEmpty {
                Section(running ? "Впереди" : exams.count == 1 ? "Экзамен" : "Экзамены") {
                    ForEach(exams) { examRow($0) }
                }
            }
            if !credits.isEmpty {
                Section(credits.count == 1 ? "Зачёт" : "Зачёты") {
                    ForEach(credits) { creditRow($0, done: false) }
                }
            }
            if !done.isEmpty {
                Section("Прошли") {
                    ForEach(done) { creditRow($0, done: true) }
                }
            }
            Section {
            } footer: {
                Text("Вечером накануне каждого экзамена и зачёта с датой придёт напоминание.")
            }
        }
        .listSectionSpacing(.compact)
    }

    private func countdown(_ session: ExamSession, running: Bool, now: Date) -> String? {
        if running {
            guard let left = session.daysLeft(now: now) else { return "Идёт" }
            return left == 0 ? "Идёт · последний день" : "Идёт · до конца \(left) \(plural(left, "день", "дня", "дней"))"
        }
        return session.firstDate.map { daysUntil($0, from: now).capitalizedFirst }
    }

    @ViewBuilder
    private func examRow(_ e: ExamSession.Entry) -> some View {
        if let event = e.event {
            Button { lesson = event } label: { examLabel(e) }
                .foregroundStyle(Color(.label))
        } else {
            NavigationLink(value: Route.subject(e.subject)) { examLabel(e) }
        }
    }

    private func examLabel(_ e: ExamSession.Entry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(e.form, systemImage: kindSymbol("экзамен"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kindTextColor("экзамен"))
                Spacer()
                if let event = e.event {
                    Text(daysUntil(event.start, from: Clock.now))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(e.subject).font(.title3.bold()).multilineTextAlignment(.leading)
            Text(e.event.map { "\(shortDay($0.start)), \(hm($0.start)) · \(place($0))" } ?? "Дата не назначена")
                .font(.subheadline)
                .foregroundStyle(e.event == nil ? .tertiary : .secondary)
            if let c = e.consultation, c.end > Clock.now {
                Label {
                    Text("Консультация — \(shortDay(c.start)), \(hm(c.start)) · \(place(c))")
                } icon: {
                    Image(systemName: kindSymbol(c.kind)).foregroundStyle(kindColor(c.kind))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func creditRow(_ e: ExamSession.Entry, done: Bool) -> some View {
        NavigationLink(value: Route.subject(e.subject)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(e.subject)
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                    if e.form != "Зачёт" {
                        Text(e.form).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Text(e.event.map { done ? shortDay($0.start) : "\(shortDay($0.start)), \(hm($0.start)) · \(place($0))" }
                     ?? "Дата не назначена")
                    .font(.subheadline)
                    .foregroundStyle(e.event == nil ? .tertiary : .secondary)
            }
        }
    }

    /// «сб, 7 ноября».
    private func shortDay(_ d: Date) -> String {
        "\(weekdaysShort[d.isoWeekday - 1].lowercased()), \(d.day) \(monthsGenitive[d.month - 1])"
    }

    private func place(_ l: Lesson) -> String { l.isRemote ? "дистанционно" : l.shortLocation }
}
