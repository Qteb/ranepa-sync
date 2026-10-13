import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'banner.dart';

/// Открывает письмо на [address]. Если почтового приложения нет (его можно
/// удалить с iPhone), копирует адрес, чтобы написать из другого.
Future<void> openMail(
  BuildContext context,
  String address, {
  String? subject,
}) async {
  final uri = Uri(
    scheme: 'mailto',
    path: address,
    query: subject == null ? null : 'subject=${Uri.encodeComponent(subject)}',
  );
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {}
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: address));
  if (!context.mounted) return;
  showBanner(
    context,
    title: 'Адрес скопирован',
    message: address,
    icon: CupertinoIcons.doc_on_clipboard_fill,
  );
}
