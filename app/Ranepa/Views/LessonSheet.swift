import SwiftUI
import TipKit

/// Подробности пары листом, как карточка места в Картах: сначала на пол-
/// экрана, тянется вверх, закрывается свайпом или крестиком. Любую строку
/// можно скопировать через контекстное меню.
struct LessonSheet: View {
    let lesson: Lesson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        List {
                TipView(CopyTip())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                Section {
                    if !lesson.location.isEmpty {
                        row(lesson.isRemote ? "Дистанционно" : lesson.room,
                            symbol: lesson.isRemote ? "video" : "mappin.and.ellipse")
                    }
                    if !lesson.lecturer.isEmpty { row(lesson.lecturer, symbol: "person") }
                    if !lesson.email.isEmpty {
                        Button {
                            openMail(lesson.email, openURL: openURL) { copied = true }
                        } label: {
                            Label(lesson.email, systemImage: "envelope")
                        }
                        .copyable(lesson.email)
                    }
                    if !lesson.groups.isEmpty {
                        row(lesson.groups.joined(separator: ", "), symbol: "person.3")
                    }
                }
                if !lesson.comment.isEmpty {
                    Section("Комментарий") { row(lesson.comment, symbol: "text.bubble") }
                }
                if !lesson.lmsLink.isEmpty, let url = URL(string: lesson.lmsLink) {
                    Section {
                        Link(destination: url) {
                            HStack {
                                Label("Открыть курс в СДО", systemImage: "book")
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                        .copyable(lesson.lmsLink)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 8, for: .scrollContent)
            // Название в одной строке с крестиком, как в карточке места
            // в Картах. Список прокручивается под шапкой.
            .safeAreaBar(edge: .top) { header }
            .alert("Адрес скопирован", isPresented: $copied) {} message: { Text(lesson.email) }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: kindSymbol(lesson.kind))
                    Text(lesson.kind.isEmpty ? "Пара" : lesson.kind.capitalizedFirst)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kindTextColor(lesson.kind))
                Text(lesson.subject)
                    .font(.title.bold())
                    .strikethrough(lesson.cancelled)
                    .copyable(lesson.subject)
                Text("\(dayTitle(lesson.start)), \(hm(lesson.start))–\(hm(lesson.end))")
                    .foregroundStyle(.secondary)
                if lesson.cancelled {
                    Text("Отменена").foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Как системный крестик листа: 44 pt, 20 pt от верха и от края.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func row(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .copyable(text)
    }
}

extension View {
    /// Контекстное меню «Скопировать». Заодно закрывает подсказку про копирование.
    func copyable(_ text: String) -> some View {
        contextMenu {
            Button("Скопировать", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = text
                CopyTip().invalidate(reason: .actionPerformed)
            }
        }
    }
}
