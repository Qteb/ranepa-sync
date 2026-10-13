import 'package:flutter/cupertino.dart';

// Размеры списков iOS 26 («Настройки»): строка 52 pt, отступ 16 pt,
// иконка 30 pt по центру строки, разделитель начинается от текста.
const _rowInset = 16.0;
const _glyphSize = 30.0;
const _glyphToTitle = 14.0;
const _rowMinHeight = 52.0;
const _sectionRadius = 26.0;

/// Цветная иконка-плашка, как в «Настройках» iPhone.
class Glyph extends StatelessWidget {
  const Glyph(this.icon, this.color, {super.key});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: color,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(8)),
    ),
    child: SizedBox.square(
      dimension: _glyphSize,
      child: Icon(icon, size: 19, color: CupertinoColors.white),
    ),
  );
}

/// Блок строк со скруглёнными углами, подписью сверху и пояснением снизу.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.icons = true,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  /// У строк есть иконки: разделитель тогда начинается от текста.
  final bool icons;

  @override
  Widget build(BuildContext context) {
    final divider = Padding(
      padding: EdgeInsetsDirectional.only(
        start: icons ? _rowInset + _glyphSize + _glyphToTitle : _rowInset,
      ),
      child: Container(
        height: 1 / MediaQuery.devicePixelRatioOf(context),
        color: CupertinoColors.separator.resolveFrom(context),
      ),
    );
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(_rowInset, 0, _rowInset, 7),
              child: Text(
                header!.toUpperCase(),
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ),
          ClipRSuperellipse(
            borderRadius: BorderRadius.circular(_sectionRadius),
            child: ColoredBox(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) divider,
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(_rowInset, 7, _rowInset, 0),
              child: Text(
                footer!,
                style: TextStyle(fontSize: 13, color: secondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка настроек: иконка, название, значение справа и стрелка или
/// переключатель. Подсвечивается при нажатии, как ячейка UITableView.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
  });

  final Widget title;
  final Widget? leading;
  final Widget? subtitle;

  /// Текущее значение серым справа: «Авто», «За 10 мин».
  final Widget? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _pressed = false;

  void _press(bool value) {
    if (widget.onTap != null && value != _pressed) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      child: ColoredBox(
        color: _pressed
            ? CupertinoColors.systemGrey4.resolveFrom(context)
            : const Color(0x00000000),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowMinHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _rowInset,
              vertical: 10,
            ),
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  SizedBox.square(
                    dimension: _glyphSize,
                    child: Center(child: widget.leading),
                  ),
                  const SizedBox(width: _glyphToTitle),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle.merge(
                        style: TextStyle(fontSize: 17, color: label),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        child: widget.title,
                      ),
                      if (widget.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(fontSize: 13, color: secondary),
                            child: widget.subtitle!,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.value != null) ...[
                  const SizedBox(width: 8),
                  DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 17, color: secondary),
                    maxLines: 1,
                    child: widget.value!,
                  ),
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: 6),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Стрелка у строки, которая открывает следующий экран.
class SettingsChevron extends StatelessWidget {
  const SettingsChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.chevron_forward,
    size: 17,
    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
  );
}

/// Подпись под блоком: 13 pt, вторичный цвет, как в «Настройках».
class SectionFooter extends StatelessWidget {
  const SectionFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    ),
  );
}

/// Стрелка ↗ у строки, которая открывает ссылку вне приложения.
class ExternalLinkMark extends StatelessWidget {
  const ExternalLinkMark({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.arrow_up_right,
    size: 15,
    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
  );
}

/// Скругление листов и окон, как в iOS 26.
const sheetRadius = 36.0;

/// Отступ кнопок от краёв листа: одинаковый сверху и сбоку.
const _barInset = 20.0;

/// Круглая кнопка листа, как в iOS 26: «Назад», «Закрыть». 44 pt.
class BarCircleButton extends StatelessWidget {
  const BarCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.plain = false,
  });

  /// Кнопка «Назад» для экранов внутри листа: Flutter её там не ставит.
  const BarCircleButton.back({
    super.key,
    required this.onPressed,
    this.plain = false,
  }) : icon = CupertinoIcons.chevron_back,
       label = 'Назад';

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Экран с обычным (не серым) фоном: кнопка серая, а не белая.
  final bool plain;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(44),
      onPressed: onPressed,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              (plain
                      ? CupertinoColors.tertiarySystemFill
                      : CupertinoColors.secondarySystemGroupedBackground)
                  .resolveFrom(context),
        ),
        child: Icon(
          icon,
          size: 20,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      ),
    ),
  );
}

/// Верх листа как в iOS 26: круглые кнопки 44 pt в 20 pt от краёв,
/// заголовок по центру между ними, без линии снизу.
class SettingsBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const SettingsBar({
    super.key,
    this.leading,
    this.middle,
    this.trailing,
    this.plain = false,
  });

  final Widget? leading;
  final Widget? middle;
  final Widget? trailing;

  /// Фон обычный, а не серый, как у списков.
  final bool plain;

  @override
  Size get preferredSize => const Size.fromHeight(_barInset + 44 + 8);

  @override
  bool shouldFullyObstruct(BuildContext context) => true;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color:
        (plain
                ? CupertinoColors.systemBackground
                : CupertinoColors.systemGroupedBackground)
            .resolveFrom(context),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        _barInset,
        MediaQuery.paddingOf(context).top + _barInset,
        _barInset,
        8,
      ),
      child: SizedBox(
        height: 44,
        child: NavigationToolbar(
          leading: leading,
          trailing: trailing,
          middleSpacing: 12,
          middle: middle == null
              ? null
              : DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: middle!,
                ),
        ),
      ),
    ),
  );
}
