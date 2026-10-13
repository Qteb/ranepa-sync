import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../links.dart';
import '../widgets/settings.dart';

/// Версия, открытый код, контакты и лицензии. Открывается из листа аккаунта.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

  Future<void> _mail(String version) => launchUrl(
    Uri(
      scheme: 'mailto',
      path: Links.email,
      query: 'subject=${Uri.encodeComponent('Расписание РАНХиГС $version')}',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        leading: _BackButton('Аккаунт'),
        middle: Text('О приложении'),
      ),
      child: DefaultTextStyle(
        style: CupertinoTheme.of(context).textTheme.textStyle,
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            final version = info == null
                ? ''
                : '${info.version} (${info.buildNumber})';
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 72,
                          height: 72,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Расписание РАНХиГС',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Версия $version',
                        style: TextStyle(fontSize: 15, color: secondary),
                      ),
                    ],
                  ),
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('Открытый код'),
                  footer: const SectionFooter(
                    'Код приложения открыт: любой может проверить, '
                    'что оно делает с данными.',
                  ),
                  children: [
                    CupertinoListTile(
                      leading: const Glyph(
                        CupertinoIcons.chevron_left_slash_chevron_right,
                        CupertinoColors.systemPurple,
                      ),
                      title: const Text('Код на GitHub'),
                      trailing: const ExternalLinkMark(),
                      onTap: () => _open(Links.repo),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('Информация'),
                  children: [
                    CupertinoListTile(
                      leading: const Glyph(
                        CupertinoIcons.lock_fill,
                        CupertinoColors.systemBlue,
                      ),
                      title: const Text('Конфиденциальность'),
                      trailing: const ExternalLinkMark(),
                      onTap: () => _open(Links.privacy),
                    ),
                    CupertinoListTile(
                      leading: const Glyph(
                        CupertinoIcons.mail_solid,
                        CupertinoColors.systemOrange,
                      ),
                      title: const Text('Написать разработчику'),
                      trailing: const ExternalLinkMark(),
                      onTap: () => _mail(version),
                    ),
                    CupertinoListTile(
                      leading: const Glyph(
                        CupertinoIcons.doc_text_fill,
                        CupertinoColors.systemGrey,
                      ),
                      title: const Text('Лицензии'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const _LicensesScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 4, 32, 32),
                  child: Text(
                    'Неофициальное приложение.\nНе связано с РАНХиГС.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Лицензии библиотек: список пакетов → текст лицензии.
class _LicensesScreen extends StatelessWidget {
  const _LicensesScreen();

  static Future<Map<String, List<LicenseEntry>>> _load() async {
    final byPackage = <String, List<LicenseEntry>>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        byPackage.putIfAbsent(package, () => []).add(entry);
      }
    }
    return Map.fromEntries(
      byPackage.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground,
    navigationBar: const CupertinoNavigationBar(
      leading: _BackButton('Назад'),
      middle: Text('Лицензии'),
    ),
    child: DefaultTextStyle(
      style: CupertinoTheme.of(context).textTheme.textStyle,
      child: FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          final packages = snapshot.data;
          if (packages == null) {
            return const Center(child: CupertinoActivityIndicator());
          }
          return ListView(
            children: [
              CupertinoListSection.insetGrouped(
                children: [
                  for (final MapEntry(key: name, value: entries)
                      in packages.entries)
                    CupertinoListTile(
                      title: Text(name),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) =>
                              _LicenseText(package: name, entries: entries),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _LicenseText extends StatelessWidget {
  const _LicenseText({required this.package, required this.entries});

  final String package;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final text = entries
        .map((e) => e.paragraphs.map((p) => p.text).join('\n\n'))
        .join('\n\n————\n\n');
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const _BackButton('Лицензии'),
        middle: Text(package),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Внутри листа Flutter не подставляет кнопку «Назад» сам.
class _BackButton extends StatelessWidget {
  const _BackButton(this.previousPageTitle);

  final String previousPageTitle;

  @override
  Widget build(BuildContext context) => CupertinoNavigationBarBackButton(
    previousPageTitle: previousPageTitle,
    onPressed: () => Navigator.of(context).pop(),
  );
}
