import UIKit
import WebKit

/// Запрос расписания, который делает сама страница ЛК: в нём уже есть
/// uid_org, все группы и подгруппы студента и нужные заголовки.
struct ScheduleTemplate {
    let url: String
    let headers: [String: String]

    /// Тот же запрос на другие дни.
    func with(dates: [Date]) -> String {
        guard var parts = URLComponents(string: url) else { return url }
        var items = (parts.queryItems ?? []).filter { $0.name != "dates[]" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T00:00:00.000'"
        items += dates.map { URLQueryItem(name: "dates[]", value: f.string(from: $0)) }
        parts.queryItems = items
        return parts.url?.absoluteString ?? url
    }
}

struct FetchResult {
    var days: [Any]
    var group: String?
    var program: String?
    /// «Фамилия Имя Отчество».
    var fullName: String?
    /// data:image/…;base64,… — nil, если фото не запрашивали; пустая
    /// строка, если в ЛК его нет.
    var photo: String?
    /// Когда истекает refresh-токен: сутки, а с «Запомнить меня» — 30 дней.
    /// Сам токен из страницы не выходит, только его срок.
    var sessionUntil: Date?
}

enum LKError: LocalizedError {
    case needLogin
    /// ЛК перегружен или лежит (429, 5xx): обновления ставятся на паузу.
    case serverBusy(status: Int, retryAfter: Int?)
    case message(String)

    static func busy(_ status: Int) -> Bool { status == 429 || status >= 500 }

    var errorDescription: String? {
        switch self {
        case .needLogin: "Сессия истекла, войди в ЛК заново"
        case .serverBusy: "ЛК сейчас недоступен, попробую позже"
        case .message(let text): text
        }
    }
}

/// Работа с ЛК идёт только через WebView: сайт закрыт JS-проверкой браузера,
/// поэтому обычный HTTP-клиент вместо JSON получает заглушку-лоадер.
/// Cookie и токены лежат в общем хранилище WebKit — то же, что было
/// у Flutter-версии.
@MainActor
final class LKWebView: NSObject, WKNavigationDelegate {
    static let scheduleURL = URL(string: "https://my.ranepa.ru/lk/student/schedule")!
    private static let groupsURL = "https://my.ranepa.ru/lk/n-api/manual/student-groups"
    private static let profileURL = "https://my.ranepa.ru/lk/n-api/profile"
    private static let photoURL = "https://my.ranepa.ru/lk/n-api/profile/photo"

    let webView: WKWebView
    var onTemplate: ((ScheduleTemplate) -> Void)?
    var onURL: ((URL?) -> Void)?
    var onLoading: ((Bool) -> Void)?
    /// Страница ЛК не открылась: нет сети, TLS или 429/5xx.
    var onFailure: ((LKError) -> Void)?

    private var urlObservation: NSKeyValueObservation?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let scripts = config.userContentController
        scripts.addUserScript(WKUserScript(source: Self.hookJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        scripts.addUserScript(WKUserScript(source: Self.noZoomJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        scripts.addUserScript(WKUserScript(source: Self.rememberMeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        scripts.add(MessageProxy(self), name: "scheduleRequest")
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        // Сайт — одностраничное приложение: вход и уход с формы входа
        // меняют адрес без новой загрузки страницы.
        urlObservation = webView.observe(\.url) { [weak self] view, _ in
            MainActor.assumeIsolated { self?.onURL?(view.url) }
        }
    }

    func load() { webView.load(URLRequest(url: Self.scheduleURL)) }

    static func isLoginPage(_ url: URL?) -> Bool { url?.path.contains("/login") ?? false }

    fileprivate func received(_ body: Any) {
        guard let data = body as? [String: Any], let url = data["url"] as? String else { return }
        let headers = (data["headers"] as? [String: Any] ?? [:]).mapValues { "\($0)" }
        onTemplate?(ScheduleTemplate(url: url, headers: headers))
    }

    // MARK: Навигация

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoading?(true)
        onURL?(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoading?(false)
        onURL?(webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoading?(false)
        // Отмена — это переход на другую страницу (например, на вход), не сбой.
        if (error as NSError).code == NSURLErrorCancelled { return }
        onFailure?(.message("Нет связи с ЛК: \(error.localizedDescription)"))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if navigationResponse.isForMainFrame,
           let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode,
           LKError.busy(status) {
            onFailure?(.serverBusy(status: status, retryAfter: nil))
        }
        return .allow
    }

    // MARK: Загрузка расписания

    /// Скачивает [weeks] недель начиная с [monday] в уже авторизованной странице.
    /// С [stopAfterEmpty] останавливается после стольких пустых недель подряд
    /// (но не раньше месяца): дальше семестр кончился.
    func fetch(_ template: ScheduleTemplate, monday: Date, weeks: Int, stopAfterEmpty: Int? = nil,
               withProfile: Bool = true, withPhoto: Bool = false) async throws -> FetchResult {
        let urls = (0..<weeks).map { w in
            template.with(dates: (0..<7).map { monday.adding(days: w * 7 + $0) })
        }
        let headers = template.headers.filter { $0.key.lowercased() != "authorization" }
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(Self.fetchJS, arguments: [
                "urls": urls, "headers": headers,
                "stopAfterEmpty": stopAfterEmpty ?? 0, "minWeeks": fetchWeeks,
                "groupsUrl": Self.groupsURL, "profileUrl": Self.profileURL, "photoUrl": Self.photoURL,
                "withProfile": withProfile, "withPhoto": withPhoto,
            ], contentWorld: .page)
        } catch {
            throw LKError.message("Ошибка WebView: \(error.localizedDescription)")
        }
        guard let raw = (value as? String)?.data(using: .utf8),
              let data = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { throw LKError.message("Сайт ответил непонятно") }
        if let error = data["error"] as? String {
            if error == "auth" { throw LKError.needLogin }
            if let m = error.firstMatch(of: /^http (\d+) ?(.*)$/), let status = Int(m.1), LKError.busy(status) {
                throw LKError.serverBusy(status: status, retryAfter: Int(m.2))
            }
            throw LKError.message("Сайт ответил ошибкой: \(error)")
        }
        return FetchResult(days: data["days"] as? [Any] ?? [], group: data["group"] as? String,
                           program: data["program"] as? String, fullName: data["name"] as? String,
                           photo: data["photo"] as? String,
                           sessionUntil: (data["sessionUntil"] as? Double).map(Date.init(timeIntervalSince1970:)))
    }

    // MARK: Без экрана

    /// Обновление без интерфейса: невидимый WebView открывает ЛК с сохранёнными
    /// cookie и токенами. Страница сама обновит токен и запросит расписание.
    static func refresh(monday: Date, weeks: Int, stopAfterEmpty: Int? = nil,
                        withProfile: Bool, withPhoto: Bool) async throws -> FetchResult {
        let lk = LKWebView()
        // Вне окна WebKit усыпляет страницу: держим её в окне, но невидимой.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first }).first {
            lk.webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            lk.webView.alpha = 0
            lk.webView.isUserInteractionEnabled = false
            window.addSubview(lk.webView)
        }
        defer { lk.webView.removeFromSuperview() }
        let template = try await lk.waitForTemplate(timeout: 60)
        return try await lk.fetch(template, monday: monday, weeks: weeks, stopAfterEmpty: stopAfterEmpty,
                                  withProfile: withProfile, withPhoto: withPhoto)
    }

    private func waitForTemplate(timeout: TimeInterval) async throws -> ScheduleTemplate {
        try await withCheckedThrowingContinuation { continuation in
            var done = false
            func finish(_ result: Result<ScheduleTemplate, Error>) {
                guard !done else { return }
                done = true
                continuation.resume(with: result)
            }
            onTemplate = { finish(.success($0)) }
            onURL = { if Self.isLoginPage($0) { finish(.failure(LKError.needLogin)) } }
            onFailure = { finish(.failure($0)) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                finish(.failure(LKError.message("ЛК не ответил за минуту, попробуй позже")))
            }
            load()
        }
    }

    /// Стирает cookie и localStorage (там лежат токены ЛК).
    static func logout() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    // MARK: Скрипты

    /// Перехватывает запрос расписания, который делает сама страница.
    private static let hookJS = #"""
    (function () {
      if (window.__rtHooked) return;
      window.__rtHooked = true;
      function report(url, headers) {
        try {
          var abs = new URL(url, location.href).href;
          if (abs.indexOf('/n-api/schedule?') === -1) return;
          window.webkit.messageHandlers.scheduleRequest.postMessage({ url: abs, headers: headers || {} });
        } catch (e) {}
      }
      var open = XMLHttpRequest.prototype.open;
      var setHeader = XMLHttpRequest.prototype.setRequestHeader;
      var send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__rtUrl = url; this.__rtHeaders = {};
        return open.apply(this, arguments);
      };
      XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
        if (this.__rtHeaders) this.__rtHeaders[k] = v;
        return setHeader.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        if (this.__rtUrl) report(this.__rtUrl, this.__rtHeaders);
        return send.apply(this, arguments);
      };
      var origFetch = window.fetch;
      if (origFetch) window.fetch = function (input, init) {
        try {
          var h = {};
          if (init && init.headers) new Headers(init.headers).forEach(function (v, k) { h[k] = v; });
          report(typeof input === 'string' ? input : input.url, h);
        } catch (e) {}
        return origFetch.apply(this, arguments);
      };
    })();
    """#

    /// Запрещает зум: Nuxt может переписать мету при навигации, поэтому
    /// следим за `<head>`.
    private static let noZoomJS = #"""
    (function () {
      var content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
      function apply() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        if (meta.content !== content) meta.content = content;
      }
      apply();
      new MutationObserver(apply).observe(document.head, { childList: true, subtree: true, attributes: true });
    })();
    """#

    /// Ставит «Запомнить меня» на форме входа: с ней сессия ЛК живёт 30 дней,
    /// без неё — сутки. Нажимаем сами, как пользователь, — так Vue узнаёт
    /// о галочке. Один раз на форму: если её сняли, не возвращаем.
    private static let rememberMeJS = #"""
    (function () {
      function apply() {
        document.querySelectorAll('label').forEach(function (label) {
          if (label.textContent.indexOf('Запомнить') === -1) return;
          var input = document.getElementById(label.htmlFor);
          if (!input || input.type !== 'checkbox' || input.dataset.rtRemember) return;
          input.dataset.rtRemember = '1';
          if (!input.checked) input.click();
        });
      }
      apply();
      new MutationObserver(apply).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """#

    private static let fetchJS = #"""
    const auth = { authorization: 'Bearer ' + localStorage.getItem('access_token') };
    async function get(url) {
      const r = await fetch(url, { headers: Object.assign({}, headers, auth) });
      const ct = r.headers.get('content-type') || '';
      if (r.status === 401) throw new Error('auth');
      if (!r.ok || ct.indexOf('json') === -1) {
        throw new Error('http ' + r.status + ' ' + (r.headers.get('retry-after') || ''));
      }
      return r.json();
    }
    try {
      const days = [];
      let empty = 0;
      for (let i = 0; i < urls.length; i++) {
        const week = (await get(urls[i])).days || [];
        days.push(...week);
        const count = week.reduce((n, day) => n + ((day.discs || []).length), 0);
        empty = count ? 0 : empty + 1;
        if (stopAfterEmpty && i + 1 >= minWeeks && empty >= stopAfterEmpty) break;
      }
      // Профиль — необязательная часть: ошибка не должна ломать расписание.
      const out = { days: days };
      if (withProfile) try {
        const sg = ((await get(groupsUrl)).items || [])[0] || {};
        out.group = sg.academic_group;
        out.program = sg.edu_program_title;
      } catch (e) {}
      if (withProfile) try {
        const p = (await get(profileUrl)).item || {};
        out.name = [p.last_name, p.first_name, p.middle_name].filter(Boolean).join(' ');
      } catch (e) {}
      if (withPhoto) {
        try { out.photo = (await get(photoUrl)).result || ''; } catch (e) {}
      }
      // Только срок refresh-токена (поле exp), не сам токен.
      try {
        const part = (localStorage.getItem('refresh_token') || '').split('.')[1];
        const exp = JSON.parse(atob(part.replace(/-/g, '+').replace(/_/g, '/'))).exp;
        if (exp) out.sessionUntil = exp;
      } catch (e) {}
      return JSON.stringify(out);
    } catch (e) {
      return JSON.stringify({ error: String(e.message || e) });
    }
    """#
}

/// WKUserContentController держит обработчик сильной ссылкой — через
/// прокси WebView может освободиться.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: LKWebView?

    init(_ target: LKWebView) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.received(message.body) }
    }
}
