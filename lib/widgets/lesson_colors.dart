import 'package:flutter/cupertino.dart';

/// Цвета типов пар. Системные цвета iOS, разнесённые по кругу, — не
/// бордовый акцент приложения, чтобы тип не путался с кнопками.
/// [bar] — полоска, [text] — подпись типа: в светлой теме темнее, чтобы
/// читалась на светлом фоне.
class LessonColors {
  const LessonColors(this.bar, this.text);

  final CupertinoDynamicColor bar;
  final CupertinoDynamicColor text;

  static LessonColors of(String kind) => switch (kind) {
    'лекция' => _blue,
    'семинар' => _green,
    'физкультура' => _orange,
    'лабораторная' => _purple,
    'консультация' => _teal,
    'экзамен' || 'зачёт' => _pink,
    _ => _grey,
  };

  static const _blue = LessonColors(
    CupertinoColors.systemBlue,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFF0062CC),
      darkColor: Color(0xFF409CFF),
    ),
  );
  static const _green = LessonColors(
    CupertinoColors.systemGreen,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFF248A3D),
      darkColor: Color(0xFF30D158),
    ),
  );
  static const _orange = LessonColors(
    CupertinoColors.systemOrange,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFFC93400),
      darkColor: Color(0xFFFF9F0A),
    ),
  );
  static const _purple = LessonColors(
    CupertinoColors.systemPurple,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFF8944AB),
      darkColor: Color(0xFFDA8FFF),
    ),
  );
  static const _teal = LessonColors(
    CupertinoColors.systemTeal,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFF0071A4),
      darkColor: Color(0xFF5DE6FF),
    ),
  );
  static const _pink = LessonColors(
    CupertinoColors.systemPink,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFFD30F45),
      darkColor: Color(0xFFFF6482),
    ),
  );
  static const _grey = LessonColors(
    CupertinoColors.systemGrey,
    CupertinoDynamicColor.withBrightness(
      color: Color(0xFF6C6C70),
      darkColor: Color(0xFFAEAEB2),
    ),
  );
}
