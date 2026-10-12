import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../app_state.dart';
import '../format.dart';
import '../ranepa_client.dart';

/// Вход идёт на настоящей странице ЛК: пароль вводится на сайте,
/// приложение его не видит и не хранит.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state, required this.onBack});

  final AppState state;
  final VoidCallback onBack;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? _controller;
  bool _pageLoading = true;
  bool _sawLoginForm = false;
  bool _fetching = false;
  bool _requested = false;
  Timer? _timeout;
  String? _error;

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _onUrl(Uri? url) {
    if (RanepaClient.isLoginPage(url)) {
      _sawLoginForm = true;
      if (_fetching && !_requested) _fail('Не удалось войти, попробуй ещё раз');
    } else if (_sawLoginForm) {
      // Ушли с формы входа — значит, вход прошёл. Сайт дальше грузится под
      // экраном загрузки: нам нужен только его запрос расписания.
      _showLoading();
    }
  }

  void _showLoading() {
    if (_fetching) return;
    setState(() {
      _fetching = true;
      _error = null;
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 60), () {
      if (!_requested) _fail('ЛК не ответил за минуту, попробуй ещё раз');
    });
  }

  void _fail(String message) {
    _timeout?.cancel();
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _requested = false;
      _error = message;
    });
  }

  Future<void> _onTemplate(ScheduleTemplate template) async {
    if (_requested) return;
    _requested = true;
    _showLoading();
    try {
      final monday = mondayOf(DateTime.now());
      final result = await RanepaClient.fetch(
        _controller!,
        template,
        monday,
        fetchWeeks,
        withPhoto: true,
      );
      _timeout?.cancel();
      await widget.state.completeLogin(result, monday);
    } catch (e) {
      _fail(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        transitionBetweenRoutes: false,
        leading: _fetching
            ? null
            : CupertinoNavigationBarBackButton(
                previousPageTitle: 'Назад',
                onPressed: widget.onBack,
              ),
        middle: Text(_fetching ? 'Расписание' : 'Вход в ЛК'),
        trailing: _pageLoading && !_fetching
            ? const CupertinoActivityIndicator()
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(RanepaClient.scheduleUrl),
              ),
              initialUserScripts: RanepaClient.userScripts,
              initialSettings: RanepaClient.settings,
              onWebViewCreated: (c) {
                _controller = c;
                RanepaClient.attach(c, _onTemplate);
              },
              onLoadStart: (_, url) {
                setState(() => _pageLoading = true);
                _onUrl(url);
              },
              onLoadStop: (_, url) {
                setState(() => _pageLoading = false);
                _onUrl(url);
              },
              onUpdateVisitedHistory: (_, url, _) => _onUrl(url),
            ),
            if (_fetching)
              Positioned.fill(
                child: ColoredBox(
                  color: CupertinoColors.systemBackground.resolveFrom(context),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(radius: 14),
                        const SizedBox(height: 16),
                        Text(
                          'Загружаю расписание…',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Обычно это занимает несколько секунд',
                          style: TextStyle(fontSize: 15, color: secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Color(0x26000000), blurRadius: 20),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_circle_fill,
                        color: CupertinoColors.systemRed.resolveFrom(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
