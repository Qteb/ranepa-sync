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

/// Вкладка «Сессия»: ближайшая сессия по плану — экзамены и зачёты
/// строками пар, сданное — внизу.
struct SessionTab: View {
    @Environment(AppState.self) private var state
    @State private var lesson: Lesson?
    @State private var showAccount = false

    var body: some View {
        let now = Clock.now
        let session = state.session
        NavigationStack {
            Group {
                if let session {
                    content(session, now: now)
                } else {
                    ContentUnavailableView("Сессии пока нет", systemImage: "graduationcap",
                                           description: Text("Даты появятся, когда загрузится план обучения."))
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaBar(edge: .top) {
                TabHeader(title: "Сессия", subtitle: session.map { subtitle($0, now: now) }) { showAccount = true }
            }
            .toolbar(.hidden, for: .navigationBar)
            .routes()
        }
        .sheet(item: $lesson) { LessonSheet(lesson: $0) }
        .sheet(isPresented: $showAccount) { AccountView() }
    }

    /// «11–30 января · через 89 дней», «11–30 января · идёт, осталось 8 из 9».
    private func subtitle(_ session: ExamSession, now: Date) -> String {
        let when: String
        if session.isRunning(now: now) {
            when = "идёт, осталось \(session.remaining(now: now)) из \(session.all.count)"
        } else {
            when = session.firstDate.map { daysUntil($0, from: now) } ?? ""
        }
        return [session.dates, when].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func content(_ session: ExamSession, now: Date) -> some View {
        let exams = session.exams.filter { !session.isDone($0, now: now) }
        let credits = session.credits.filter { !session.isDone($0, now: now) }
        let done = session.all.filter { session.isDone($0, now: now) }
        return List {
            if !exams.isEmpty {
                Section("\(exams.count == 1 ? "Экзамен" : "Экзамены") · \(exams.count)") {
                    ForEach(exams) { row($0) }
                }
            }
            if !credits.isEmpty {
                Section("\(credits.count == 1 ? "Зачёт" : "Зачёты") · \(credits.count)") {
                    ForEach(credits) { row($0) }
                }
            }
            if !done.isEmpty {
                Section("Прошли") {
                    ForEach(done) { row($0) }
                }
            }
            Section {
            } footer: {
                Text("Вечером накануне каждого экзамена и зачёта с датой придёт напоминание.")
            }
        }
        .contentMargins(.top, 4, for: .scrollContent)
    }

    /// С датой — строка пары (открывает карточку), без даты — предмет.
    @ViewBuilder
    private func row(_ e: ExamSession.Entry) -> some View {
        if let event = e.event {
            Button { lesson = event } label: {
                LessonListRow(lesson: event, note: consultationNote(e))
            }
            .foregroundStyle(Color(.label))
        } else {
            NavigationLink(value: Route.subject(e.subject)) {
                HStack(alignment: .top, spacing: 12) {
                    KindStripe(kind: "экзамен", muted: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Дата не назначена").font(.subheadline.weight(.medium)).foregroundStyle(.tertiary)
                        Text(e.subject).font(.headline)
                        Text(e.form).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            }
        }
    }

    private func consultationNote(_ e: ExamSession.Entry) -> String? {
        guard let c = e.consultation, c.end > Clock.now else { return nil }
        return "Консультация — \(shortWhen(c.start))\(c.isRemote ? ", дистанционно" : ", \(c.shortLocation)")"
    }
}
