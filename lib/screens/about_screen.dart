import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../links.dart';
import '../widgets/mail.dart';
import 'privacy_screen.dart';
import '../widgets/settings.dart';

/// Версия, открытый код, контакты и лицензии. Открывается из листа аккаунта.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
                  children: [
                    CupertinoListTile(
                      leading: const _GitHubGlyph(),
                      title: const Text('GitHub'),
                      trailing: const ExternalLinkMark(),
                      onTap: () => launchUrl(
                        Uri.parse(Links.repo),
                        mode: LaunchMode.inAppBrowserView,
                      ),
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
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => const PrivacyScreen(
                            leading: _BackButton('Назад'),
                          ),
                        ),
                      ),
                    ),
                    CupertinoListTile(
                      leading: const Glyph(
                        CupertinoIcons.mail_solid,
                        CupertinoColors.systemOrange,
                      ),
                      title: const Text('Написать разработчику'),
                      trailing: const ExternalLinkMark(),
                      onTap: () => openMail(
                        context,
                        Links.email,
                        subject: 'Расписание РАНХиГС $version',
                      ),
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

/// Плашка с логотипом GitHub в стиле остальных иконок настроек.
class _GitHubGlyph extends StatelessWidget {
  const _GitHubGlyph();

  // Octicons mark-github, 16×16.
  static const _mark =
      '<svg viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">'
      '<path fill="#fff" d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 '
      '7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-'
      '1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02'
      '-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 '
      '.27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 '
      '1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21'
      '-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19'
      '.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45'
      '-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"/></svg>';

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF1F2328),
      borderRadius: BorderRadius.circular(7),
    ),
    child: SizedBox.square(
      dimension: 29,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: SvgPicture.string(_mark),
      ),
    ),
  );
}
