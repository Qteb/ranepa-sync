import SwiftUI
import WebKit

/// Стартовый экран → вход в ЛК.
struct AuthFlow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            OnboardingView()
        }
    }
}

/// Стартовый экран до входа: что это за приложение и куда уходит пароль.
struct OnboardingView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("Logo")
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(.rect(cornerRadius: 22))
                // Долгое нажатие: демо без ЛК для App Review и скриншотов.
                .onLongPressGesture {
                    Task { await state.startDemo() }
                }
                .sensoryFeedback(.impact, trigger: state.demo)
                .accessibilityHidden(true)
            Text("Расписание студента")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 20)
            VStack(alignment: .leading, spacing: 18) {
                block("Что это", "Твоё расписание из личного кабинета РАНХиГС.")
                block("Как работает", "Входишь в ЛК на странице сайта. Логин и пароль приложение не видит и не хранит.")
                block("Что умеет", "Работает без интернета, напоминает о парах, добавляет их в календарь и виджет.")
            }
            .padding(.top, 32)
            Spacer(minLength: 24)
            Spacer()
            if let error = state.error {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }
            NavigationLink {
                LoginView()
            } label: {
                Text("Войти через ЛК").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            Text("Неофициальное приложение\nс [открытым кодом](https://github.com/Qteb/ranepa-sync)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: 560)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Вход идёт на настоящей странице ЛК: пароль вводится на сайте,
/// приложение его не видит и не хранит.
struct LoginView: View {
    @Environment(AppState.self) private var state
    @State private var lk = LKWebView()
    @State private var pageLoading = true
    @State private var sawLoginForm = false
    @State private var fetching = false
    @State private var requested = false
    @State private var error: String?
    @State private var timeout: Task<Void, Never>?

    var body: some View {
        WebView(lk: lk)
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if fetching {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.large).padding(.bottom, 8)
                        Text("Загружаю расписание…").font(.headline)
                        Text("Обычно это занимает несколько секунд").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
            .overlay(alignment: .bottom) {
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        .padding(16)
                }
            }
            .navigationTitle(fetching ? "Расписание" : "Вход в ЛК")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(fetching)
            .toolbar {
                if pageLoading && !fetching {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .onAppear {
                lk.onLoading = { pageLoading = $0 }
                lk.onURL = onURL
                lk.onTemplate = { template in Task { await onTemplate(template) } }
                lk.load()
            }
            .onDisappear { timeout?.cancel() }
    }

    private func onURL(_ url: URL?) {
        if LKWebView.isLoginPage(url) {
            sawLoginForm = true
            if fetching && !requested { fail("Не удалось войти, попробуй ещё раз") }
        } else if sawLoginForm {
            // Ушли с формы входа — значит, вход прошёл. Сайт дальше грузится под
            // экраном загрузки: нам нужен только его запрос расписания.
            showLoading()
        }
    }

    private func showLoading() {
        guard !fetching else { return }
        fetching = true
        error = nil
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled && !requested { fail("ЛК не ответил за минуту, попробуй ещё раз") }
        }
    }

    private func fail(_ message: String) {
        timeout?.cancel()
        fetching = false
        requested = false
        error = message
    }

    private func onTemplate(_ template: ScheduleTemplate) async {
        guard !requested else { return }
        requested = true
        showLoading()
        do {
            let monday = Date().monday
            let result = try await lk.fetch(template, monday: monday, weeks: fetchWeeks, withPhoto: true)
            timeout?.cancel()
            await state.completeLogin(result, monday: monday)
        } catch {
            fail(error.localizedDescription)
        }
    }
}

private struct WebView: UIViewRepresentable {
    let lk: LKWebView

    func makeUIView(context: Context) -> WKWebView { lk.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
