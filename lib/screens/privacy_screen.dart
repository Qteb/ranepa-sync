import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../links.dart';

/// Политика конфиденциальности: свежая версия из репозитория, без сети —
/// копия из приложения. Показывается русская часть, до `---`.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.leading});

  final Widget leading;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final Future<List<md.Node>> _document = _load();
  final _links = <TapGestureRecognizer>[];

  static Future<List<md.Node>> _load() async {
    var text =
        await _download(Links.privacyRaw) ??
        await _download(Links.privacyCdn) ??
        await rootBundle.loadString('PRIVACY.md');
    text = text.split(RegExp(r'^---\s*$', multiLine: true)).first;
    return md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        .parseLines(const LineSplitter().convert(text));
  }

  static Future<String?> _download(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return body.trimLeft().startsWith('#') ? body : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    for (final link in _links) {
      link.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      automaticallyImplyLeading: false,
      transitionBetweenRoutes: false,
      border: null,
      leading: widget.leading,
      middle: const Text('Конфиденциальность'),
    ),
    child: FutureBuilder(
      future: _document,
      builder: (context, snapshot) {
        final nodes = snapshot.data;
        if (nodes == null) {
          return const Center(child: CupertinoActivityIndicator());
        }
        // Ссылки создаются заново при каждой сборке — старые больше не нужны.
        for (final link in _links) {
          link.dispose();
        }
        _links.clear();
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [for (final node in nodes) ..._block(context, node)],
          ),
        );
      },
    ),
  );

  Iterable<Widget> _block(BuildContext context, md.Node node) sync* {
    if (node is! md.Element) return;
    final label = CupertinoColors.label.resolveFrom(context);
    final body = TextStyle(fontSize: 17, height: 1.35, color: label);
    switch (node.tag) {
      // Заголовок документа дублирует навбар.
      case 'h1':
        return;
      case 'h2':
        yield Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Text(
            node.textContent,
            style: body.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        );
      case 'p':
        yield Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(_inline(context, node.children, body)),
        );
      case 'ul':
        for (final item in node.children ?? const <md.Node>[]) {
          if (item is! md.Element) continue;
          yield Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: body),
                Expanded(
                  child: Text.rich(_inline(context, item.children, body)),
                ),
              ],
            ),
          );
        }
        yield const SizedBox(height: 4);
    }
  }

  InlineSpan _inline(
    BuildContext context,
    List<md.Node>? nodes,
    TextStyle style,
  ) => TextSpan(
    style: style,
    children: [
      for (final node in nodes ?? const <md.Node>[])
        if (node is md.Text)
          TextSpan(text: node.text)
        else if (node is md.Element)
          switch (node.tag) {
            'strong' => _inline(
              context,
              node.children,
              style.copyWith(fontWeight: FontWeight.w600),
            ),
            'em' => _inline(
              context,
              node.children,
              style.copyWith(fontStyle: FontStyle.italic),
            ),
            'a' => TextSpan(
              text: node.textContent,
              style: TextStyle(color: CupertinoTheme.of(context).primaryColor),
              recognizer: _link(node.attributes['href'] ?? node.textContent),
            ),
            'p' => _inline(context, node.children, style),
            _ => TextSpan(text: node.textContent),
          },
    ],
  );

  TapGestureRecognizer _link(String url) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
    _links.add(recognizer);
    return recognizer;
  }
}
