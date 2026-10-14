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
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(lesson.kind.isEmpty ? "Пара" : lesson.kind.capitalizedFirst,
                              systemImage: kindSymbol(lesson.kind))
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
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }

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
                                Image(systemName: "arrow.up.right").foregroundStyle(.tertiary)
                            }
                        }
                        .copyable(lesson.lmsLink)
                    }
                }
            }
            .listSectionSpacing(.compact)
            // Название сразу под крестиком, как в карточке места в Картах.
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .alert("Адрес скопирован", isPresented: $copied) {} message: { Text(lesson.email) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
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
