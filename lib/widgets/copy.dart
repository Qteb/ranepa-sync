import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'banner.dart';

/// Копирует [text] и показывает, что именно скопировано.
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  await HapticFeedback.selectionClick();
  if (!context.mounted) return;
  showBanner(
    context,
    title: 'Скопировано',
    message: text,
    icon: CupertinoIcons.doc_on_clipboard_fill,
    duration: const Duration(seconds: 2),
  );
}
