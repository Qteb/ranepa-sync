import 'dart:async';

import 'package:flutter/cupertino.dart';

OverlayEntry? _current;

/// Баннер сверху, как уведомление внутри приложения в iOS: выезжает,
/// висит [duration] и уезжает; закрывается тапом или свайпом вверх.
void showBanner(
  BuildContext context, {
  required String title,
  String? message,
  IconData icon = CupertinoIcons.info_circle_fill,
  Duration duration = const Duration(seconds: 4),
}) {
  _current?.remove();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Banner(
      title: title,
      message: message,
      icon: icon,
      duration: duration,
      onDone: () {
        if (_current == entry) _current = null;
        entry.remove();
      },
    ),
  );
  _current = entry;
  Overlay.of(context).insert(entry);
}

class _Banner extends StatefulWidget {
  const _Banner({
    required this.title,
    required this.message,
    required this.icon,
    required this.duration,
    required this.onDone,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => setState(() => _visible = true),
    );
    _timer = Timer(widget.duration, _hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _hide() {
    _timer?.cancel();
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    // Под листом iOS MediaQuery обнуляет верхний отступ, поэтому берём
    // отступ экрана напрямую — иначе баннер залезает под Dynamic Island.
    final view = View.of(context);
    final top = view.padding.top / view.devicePixelRatio;
    return Positioned(
      left: 8,
      right: 8,
      top: top + 4,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, -1.6),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        onEnd: () {
          if (!_visible) widget.onDone();
        },
        child: GestureDetector(
          onTap: _hide,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < 0) _hide();
          },
          child: DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              decoration: BoxDecoration(
                color: CupertinoColors.secondarySystemGroupedBackground
                    .resolveFrom(context),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    widget.icon,
                    size: 24,
                    color: CupertinoTheme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: label,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (widget.message != null)
                          Text(
                            widget.message!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              color: secondary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
