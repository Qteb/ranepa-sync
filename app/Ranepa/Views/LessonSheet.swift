import MapKit
import SwiftUI
import TipKit

/// Подробности пары листом, как карточка места в Картах: высотой по
/// содержимому, тянется вверх, закрывается свайпом или крестиком. Любую строку
/// можно скопировать через контекстное меню.
struct LessonSheet: View {
    let lesson: Lesson
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    /// Точка корпуса: из кэша или геокодера, пока не нашлась — nil.
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var choosingMaps = false
    /// Высота листа по содержимому: шапка, строки и отступы.
    @State private var fitted: CGFloat = 320
    @State private var detent = PresentationDetent.height(320)

    var body: some View {
        List {
                Section {
                    if lesson.isRemote {
                        row("Дистанционно", symbol: "video")
                    } else if !lesson.room.isEmpty {
                        if let coordinate {
                            mapPreview(coordinate)
                        }
                        placeRow
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
            // Под последним блоком — столько же, сколько сбоку.
            .contentMargins(.bottom, 20, for: .scrollContent)
            // Название в одной строке с крестиком, как в карточке места
            // в Картах. Список прокручивается под шапкой.
            .safeAreaBar(edge: .top) { header }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Зона полосы «домой» не нужна: лист iOS 26 и так висит
                // над краем экрана, иначе снизу остаётся лишняя пустота.
                geometry.contentSize.height + geometry.contentInsets.top - geometry.contentInsets.bottom
            } action: { _, height in
                let height = height.rounded()
                guard height > 0, abs(height - fitted) > 1 else { return }
                let wasFitted = detent != .large
                fitted = height
                if wasFitted { detent = .height(height) }
            }
            .alert("Адрес скопирован", isPresented: $copied) {} message: { Text(lesson.email) }
            .task {
                if let address { coordinate = await Places.locate(address) }
            }
            // Карты, установленные на телефоне, как в Telegram и Яндекс Go:
            // системного выбора приложения карт в iOS нет.
            .confirmationDialog(address.map(Places.query(for:)) ?? lesson.shortLocation,
                                isPresented: $choosingMaps, titleVisibility: .visible) {
                ForEach(MapApp.installedApps) { app in
                    Button(app.title) { open(in: app) }
                }
                Button("Скопировать адрес") {
                    UIPasteboard.general.string = address.map(Places.query(for:)) ?? lesson.room
                }
            }
        // Лист открывается ровно по содержимому; длинную карточку можно
        // растянуть на весь экран.
        .presentationDetents([.height(fitted), .large], selection: $detent)
        // На самых крупных размерах шрифта название и адрес рвутся по
        // слогам, а на экране помещается одна строка.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    /// «Вернадского, 84, корпус 1» из строки аудитории.
    private var address: String? { Places.address(from: lesson.room) }

    /// «1 - 2262, блок 2F».
    private var placeTitle: String {
        guard let block = lesson.room.firstMatch(of: /Блок\s+(\S+)/) else { return lesson.shortLocation }
        return "\(lesson.shortLocation), блок \(block.1)"
    }

    /// Аудитория и адрес корпуса; нажатие открывает карты.
    private var placeRow: some View {
        Button { openPlace() } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(placeTitle).foregroundStyle(Color(.label))
                        if let address {
                            Text(address).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
                        }
                    }
                } icon: {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Color(.secondaryLabel))
                }
                Spacer()
                if address != nil {
                    Image(systemName: "arrow.up.right").foregroundStyle(Color(.tertiaryLabel))
                }
            }
        }
        .disabled(address == nil)
        .copyable(lesson.room)
    }

    /// Подпись булавки: «Корпус 1» для кампуса, иначе аудитория.
    private var markerTitle: String {
        guard let address, let m = address.firstMatch(of: /корпус\s*(\d+)/) else { return lesson.shortLocation }
        return "Корпус \(m.1)"
    }

    /// Корпус на карте. Карта не листается: нажатие открывает приложение карт.
    private func mapPreview(_ c: CLLocationCoordinate2D) -> some View {
        Button { openPlace() } label: {
            let building = address.flatMap(Campus.building(for:))
            Map(initialPosition: .camera(MapCamera(centerCoordinate: c, distance: building == nil ? 600 : 450))) {
                // Нужный корпус залит цветом акцента, номер — подписью
                // поверх, чтобы булавка не закрывала здание.
                if let building {
                    MapPolygon(coordinates: building.outline)
                        .foregroundStyle(Color.accentColor.opacity(0.45))
                        .stroke(Color.accentColor, lineWidth: 2)
                    Annotation("", coordinate: c, anchor: .center) {
                        Text(markerTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: .capsule)
                    }
                } else {
                    Marker(markerTitle, systemImage: "building.columns.fill", coordinate: c)
                        .tint(Color.accentColor)
                }
            }
            // Без кафе, магазинов и чужих организаций: только улицы и здания.
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .frame(height: 150)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .accessibilityLabel("Корпус на карте")
    }

    private func openPlace() {
        if let app = MapApp.preferred { return open(in: app) }
        let apps = MapApp.installedApps
        // Кроме Карт ничего не установлено — спрашивать не о чем.
        if apps.count == 1 { return open(in: apps[0]) }
        choosingMaps = true
    }

    private func open(in app: MapApp) {
        guard let address else { return }
        openURL(coordinate.map { app.url($0, name: placeTitle) } ?? app.url(search: Places.query(for: address)))
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
    /// Контекстное меню «Скопировать».
    func copyable(_ text: String) -> some View {
        contextMenu {
            Button("Скопировать", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = text
            }
        }
    }
}
