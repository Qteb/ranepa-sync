import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Работа с ЛК идёт только через WebView: сайт закрыт JS-проверкой браузера,
/// поэтому обычный HTTP-клиент вместо JSON получает заглушку-лоадер.
class RanepaClient {
  static const scheduleUrl = 'https://my.ranepa.ru/lk/student/schedule';
  static const studentGroupsUrl =
      'https://my.ranepa.ru/lk/n-api/manual/student-groups';

  /// Перехватывает запрос расписания, который делает сама страница: в нём уже
  /// есть uid_org, все группы и подгруппы студента и нужные заголовки.
  static const _hookJs = r'''
(function () {
  if (window.__rtHooked) return;
  window.__rtHooked = true;
  function report(url, headers) {
    try {
      var abs = new URL(url, location.href).href;
      if (abs.indexOf('/n-api/schedule?') === -1) return;
      var payload = { url: abs, headers: headers || {} };
      var send = function () { window.flutter_inappwebview.callHandler('scheduleRequest', payload); };
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) send();
      else window.addEventListener('flutterInAppWebViewPlatformReady', send, { once: true });
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
''';

  static final userScripts = UnmodifiableListView([
    UserScript(
      source: _hookJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: _noZoomJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
    ),
  ]);

  /// iOS игнорирует настройки зума WebView, поэтому запрещаем его через
  /// viewport. Nuxt может переписать мету при навигации — следим за `<head>`.
  static const _noZoomJs = r'''
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
''';

  static final settings = InAppWebViewSettings(
    domStorageEnabled: true,
    javaScriptEnabled: true,
    isInspectable: false,
    supportZoom: false,
    builtInZoomControls: false,
    displayZoomControls: false,
  );

  static void attach(
    InAppWebViewController controller,
    void Function(ScheduleTemplate template) onTemplate,
  ) {
    controller.addJavaScriptHandler(
      handlerName: 'scheduleRequest',
      callback: (args) {
        final data = args.first as Map;
        onTemplate(
          ScheduleTemplate(
            url: data['url'] as String,
            headers: {
              for (final e in (data['headers'] as Map).entries)
                e.key.toString(): e.value.toString(),
            },
          ),
        );
        return null;
      },
    );
  }

  static bool isLoginPage(Uri? url) => url?.path.contains('/login') ?? false;

  /// Скачивает [weeks] недель начиная с [monday] в уже авторизованной странице.
  static Future<FetchResult> fetch(
    InAppWebViewController controller,
    ScheduleTemplate template,
    DateTime monday,
    int weeks,
  ) async {
    final urls = [
      for (var w = 0; w < weeks; w++)
        template.withDates([
          for (var d = 0; d < 7; d++) monday.add(Duration(days: w * 7 + d)),
        ]),
    ];
    final headers = Map.of(template.headers)
      ..removeWhere((k, _) => k.toLowerCase() == 'authorization');

    final result = await controller.callAsyncJavaScript(
      functionBody: r'''
const auth = { authorization: 'Bearer ' + localStorage.getItem('access_token') };
async function get(url) {
  const r = await fetch(url, { headers: Object.assign({}, headers, auth) });
  const ct = r.headers.get('content-type') || '';
  if (r.status === 401) throw new Error('auth');
  if (!r.ok || ct.indexOf('json') === -1) throw new Error('http ' + r.status);
  return r.json();
}
try {
  const days = [];
  for (const u of urls) days.push(...((await get(u)).days || []));
  let group = null;
  try {
    const sg = await get(groupsUrl);
    group = sg.items && sg.items[0] && sg.items[0].academic_group;
  } catch (e) {}
  return JSON.stringify({ days: days, group: group });
} catch (e) {
  return JSON.stringify({ error: String(e.message || e) });
}
''',
      arguments: {
        'urls': urls,
        'headers': headers,
        'groupsUrl': studentGroupsUrl,
      },
    );
    if (result == null || result.error != null) {
      throw RanepaException('Ошибка WebView: ${result?.error}');
    }
    final data = jsonDecode(result.value as String) as Map<String, dynamic>;
    if (data['error'] == 'auth') throw NeedLoginException();
    if (data['error'] != null) {
      throw RanepaException('Сайт ответил ошибкой: ${data['error']}');
    }
    return FetchResult(
      days: data['days'] as List<dynamic>,
      group: data['group'] as String?,
    );
  }

  /// Обновление в фоне: невидимый WebView открывает ЛК с сохранёнными cookie и
  /// токенами. Страница сама обновит токен и запросит расписание.
  static Future<FetchResult> refresh(DateTime monday, int weeks) async {
    final ready = Completer<ScheduleTemplate>();
    InAppWebViewController? controller;

    void checkLogin(Uri? url) {
      if (isLoginPage(url) && !ready.isCompleted) {
        ready.completeError(NeedLoginException());
      }
    }

    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(scheduleUrl)),
      initialUserScripts: userScripts,
      initialSettings: settings,
      onWebViewCreated: (c) {
        controller = c;
        attach(c, (t) {
          if (!ready.isCompleted) ready.complete(t);
        });
      },
      onLoadStop: (c, url) => checkLogin(url),
      onUpdateVisitedHistory: (c, url, _) => checkLogin(url),
    );
    await view.run();
    try {
      final template = await ready.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
            throw RanepaException('ЛК не ответил за минуту, попробуй позже'),
      );
      return await fetch(controller!, template, monday, weeks);
    } finally {
      await view.dispose();
    }
  }

  /// Стирает cookie и localStorage (там лежат токены ЛК) у всех WebView.
  static Future<void> logout() async {
    await CookieManager.instance().deleteAllCookies();
    final storage = WebStorageManager.instance();
    if (Platform.isIOS) {
      // deleteAllData есть только на Android.
      await storage.removeDataModifiedSince(
        dataTypes: WebsiteDataType.ALL.toSet(),
        date: DateTime.fromMillisecondsSinceEpoch(0),
      );
    } else {
      await storage.deleteAllData();
    }
  }
}

class ScheduleTemplate {
  ScheduleTemplate({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;

  String withDates(List<DateTime> days) {
    final uri = Uri.parse(url);
    final params = <String, List<String>>{};
    for (final e in uri.queryParametersAll.entries) {
      if (e.key != 'dates[]') params[e.key] = e.value;
    }
    params['dates[]'] = [
      for (final d in days)
        '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}T00:00:00.000',
    ];
    return uri.replace(queryParameters: params).toString();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

class FetchResult {
  FetchResult({required this.days, this.group});

  final List<dynamic> days;
  final String? group;
}

class RanepaException implements Exception {
  RanepaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NeedLoginException extends RanepaException {
  NeedLoginException() : super('Сессия истекла, войди в ЛК заново');
}
