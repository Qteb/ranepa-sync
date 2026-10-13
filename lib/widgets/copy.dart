import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// Долгое нажатие показывает меню «Скопировать», как в «Контактах» iOS.
/// Пока меню открыто, элемент подсвечен; отдельного уведомления нет —
/// подтверждением служит выбранная команда.
class CopyOnLongPress extends StatefulWidget {
  const CopyOnLongPress({super.key, required this.text, required this.child});

  final String text;
  final Widget child;

  @override
  State<CopyOnLongPress> createState() => _CopyOnLongPressState();
}

class _CopyOnLongPressState extends State<CopyOnLongPress> {
  OverlayEntry? _menu;

  @override
  void dispose() {
    _menu?.remove();
    super.dispose();
  }

  void _close() {
    _menu?.remove();
    _menu = null;
    if (mounted) setState(() {});
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || _menu != null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    unawaited(HapticFeedback.mediumImpact());
    _menu = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Нажатие мимо меню закрывает его, как в iOS.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (_) => _close(),
              onPanDown: (_) => _close(),
            ),
          ),
          CupertinoTextSelectionToolbar(
            anchorAbove: rect.topCenter,
            anchorBelow: rect.bottomCenter,
            children: [
              CupertinoTextSelectionToolbarButton.text(
                text: 'Скопировать',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.text));
                  _close();
                },
              ),
            ],
          ),
        ],
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_menu!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: _open,
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        color: _menu == null
            ? null
            : CupertinoColors.systemFill.resolveFrom(context),
      ),
      child: widget.child,
    ),
  );
}
