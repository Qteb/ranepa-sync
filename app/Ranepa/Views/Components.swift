import SwiftUI
import TipKit

/// Подпись типа пары: в светлой теме темнее системного цвета, чтобы
/// читалась на светлом фоне. Полоска и иконка — системный цвет
/// (kindColor в Shared/Lessons.swift).
func kindTextColor(_ kind: String) -> Color {
    let (light, dark): (UInt32, UInt32) = switch kind {
    case "лекция": (0x0062CC, 0x409CFF)
    case "семинар": (0x248A3D, 0x30D158)
    case "физкультура": (0xC93400, 0xFF9F0A)
    case "лабораторная": (0x8944AB, 0xDA8FFF)
    case "консультация": (0x0071A4, 0x5DE6FF)
    case "экзамен", "зачёт": (0xD30F45, 0xFF6482)
    default: (0x6C6C70, 0xAEAEB2)
    }
    func ui(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
}

/// «Лекция · 5 - 201»: тип цветом типа (с иконкой — в ленте), остальное серым.
func lessonDetails(_ l: Lesson, icon: Bool = false) -> Text {
    let rest = [l.location.isEmpty ? "" : (l.isRemote ? "дистанционно" : l.shortLocation),
                l.cancelled ? "отменена" : ""]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    guard !l.kind.isEmpty else { return Text(rest) }
    // Иконка чуть мельче текста, как символы в подписях системных приложений.
    let kind = icon
        ? Text("\(Text(Image(systemName: kindSymbol(l.kind))).font(.caption)) \(l.kind.capitalizedFirst)")
        : Text(l.kind.capitalizedFirst)
    return Text("\(kind.foregroundStyle(kindTextColor(l.kind)))\(rest.isEmpty ? "" : " · ")\(rest)")
}

/// Цветная плашка с иконкой, как в «Настройках» iPhone.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    init(_ symbol: String, _ color: Color) {
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: .rect(cornerRadius: 8))
    }
}

/// Фото из ЛК, а если его нет — инициалы «Имя Фамилия» на сером круге,
/// как у контактов. В демо — схематичный портрет.
struct AvatarView: View {
    @Environment(AppState.self) private var state
    let size: CGFloat

    private var initials: String {
        let parts = (state.fullName ?? "").split(separator: " ")
        guard parts.count >= 2 else { return "" }
        return "\(parts[1].prefix(1))\(parts[0].prefix(1))"
    }

    var body: some View {
        Group {
            if let photo = state.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else if state.demo {
                Image("DemoAvatar").resizable().scaledToFill()
            } else {
                ZStack {
                    Color(.systemGray4)
                    if initials.isEmpty {
                        Image(systemName: "person.fill").font(.system(size: size * 0.5))
                    } else {
                        Text(initials).font(.system(size: size * 0.38, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

/// Баннер сверху экрана: изменения в расписании или ошибка обновления.
struct Banner: Equatable {
    var title: String
    var message: String
    var symbol: String
}

struct BannerView: View {
    let banner: Banner

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).font(.subheadline.weight(.semibold))
                Text(banner.message).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Подсказки (TipKit)

struct RefreshTip: Tip {
    var title: Text { Text("Потяни вниз, чтобы обновить") }
    var message: Text? { Text("Расписание и так обновляется само в фоне, но так можно проверить изменения прямо сейчас.") }
    var image: Image? { Image(systemName: "arrow.down.circle") }
}

struct AccountTip: Tip {
    var title: Text { Text("Настройки — под фото") }
    var message: Text? { Text("Нажми на своё фото: там напоминания, календарь и выход из ЛК.") }
    var image: Image? { Image(systemName: "person.crop.circle") }
}

/// Открывает письмо; если почтового приложения нет (его можно удалить),
/// копирует адрес, чтобы написать из другого.
@MainActor
func openMail(_ address: String, subject: String? = nil, openURL: OpenURLAction, copied: @escaping () -> Void) {
    var parts = URLComponents()
    parts.scheme = "mailto"
    parts.path = address
    if let subject { parts.queryItems = [URLQueryItem(name: "subject", value: subject)] }
    guard let url = parts.url else { return }
    openURL(url) { accepted in
        guard !accepted else { return }
        UIPasteboard.general.string = address
        copied()
    }
}
