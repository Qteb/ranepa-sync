import 'package:flutter/cupertino.dart';

/// Цветная иконка-плашка, как в «Настройках» iPhone.
class Glyph extends StatelessWidget {
  const Glyph(this.icon, this.color, {super.key});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: SizedBox.square(
      dimension: 29,
      child: Icon(icon, size: 18, color: CupertinoColors.white),
    ),
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
