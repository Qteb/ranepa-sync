import 'dart:async';

import 'package:flutter/material.dart';
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
      );
      _timeout?.cancel();
      await widget.state.completeLogin(result, monday);
    } catch (e) {
      _fail(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: _fetching
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Назад',
                onPressed: widget.onBack,
              ),
        automaticallyImplyLeading: false,
        title: Text(_fetching ? 'Расписание' : 'Вход в личный кабинет'),
        bottom: _pageLoading && !_fetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Stack(
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
                color: theme.colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        'Загружаю расписание…',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Обычно это занимает несколько секунд',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
              bottom: 16,
              child: Material(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
