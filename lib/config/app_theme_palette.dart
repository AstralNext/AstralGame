import 'package:flutter/material.dart';

import 'app_theme_id.dart';

/// 单套主题的完整色板（业务 Widget 通过 [astralPalette] 读取）。
class AppThemePalette {
  const AppThemePalette({
    required this.background,
    required this.card,
    required this.accent,
    required this.onAccent,
    required this.canvas,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.accentMuted,
    required this.accentMutedStrong,
    required this.shadowSoft,
    required this.shadowLift,
    required this.shadowHairline,
    required this.error,
    required this.onError,
    required this.morandi,
  });

  final Color background;
  final Color card;
  final Color accent;
  final Color onAccent;
  final Color canvas;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color accentMuted;
  final Color accentMutedStrong;
  final Color shadowSoft;
  final Color shadowLift;
  final Color shadowHairline;
  final Color error;
  final Color onError;
  final List<Color> morandi;

  Color get iconPlaceholder => textTertiary.withValues(alpha: 0.5);

  Color get textTertiarySoft => textTertiary.withValues(alpha: 0.8);

  /// 主题切换动画时与另一套色板插值。
  AppThemePalette lerp(AppThemePalette other, double t) {
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;

    final count = morandi.length > other.morandi.length
        ? morandi.length
        : other.morandi.length;

    return AppThemePalette(
      background: c(background, other.background),
      card: c(card, other.card),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      canvas: c(canvas, other.canvas),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      divider: c(divider, other.divider),
      accentMuted: c(accentMuted, other.accentMuted),
      accentMutedStrong: c(accentMutedStrong, other.accentMutedStrong),
      shadowSoft: c(shadowSoft, other.shadowSoft),
      shadowLift: c(shadowLift, other.shadowLift),
      shadowHairline: c(shadowHairline, other.shadowHairline),
      error: c(error, other.error),
      onError: c(onError, other.onError),
      morandi: List.generate(
        count,
        (i) => c(
          morandi[i % morandi.length],
          other.morandi[i % other.morandi.length],
        ),
      ),
    );
  }

  static AppThemePalette of(AppThemeId id) => switch (id) {
        AppThemeId.insCream => _insCream,
        AppThemeId.elegantGreen => _elegantGreen,
        AppThemeId.mistBlue => _mistBlue,
        AppThemeId.lavenderGrey => _lavenderGrey,
        AppThemeId.cementGrey => _cementGrey,
        AppThemeId.darkCoffee => _darkCoffee,
        AppThemeId.cyber2077 => _cyber2077,
      };

  static const _insCream = AppThemePalette(
    // 浅色：页底/凹槽压深，白卡靠色差浮起（对齐通用版台阶感）
    background: Color(0xFFE6DED6),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF9A7F70),
    onAccent: Color(0xFFFFFFFF),
    canvas: Color(0xFFD6CBC2),
    textPrimary: Color(0xFF3D3835),
    textSecondary: Color(0xFF7A716A),
    textTertiary: Color(0xFFA89F96),
    divider: Color(0xFFC9BDB3),
    accentMuted: Color(0x249A7F70),
    accentMutedStrong: Color(0x389A7F70),
    shadowSoft: Color(0x1A3D3835),
    shadowLift: Color(0x263D3835),
    shadowHairline: Color(0x0D3D3835),
    error: Color(0xFFC17B7B),
    onError: Color(0xFFFFFFFF),
    morandi: [
      Color(0xFFC4B5A8),
      Color(0xFFA8B5B2),
      Color(0xFFB5A8A8),
      Color(0xFFA8B0B5),
      Color(0xFFC9C0B5),
      Color(0xFFB8ADA3),
      Color(0xFFADB5B0),
    ],
  );

  static const _elegantGreen = AppThemePalette(
    background: Color(0xFFD8E6DE),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF5F8A6C),
    onAccent: Color(0xFFFFFFFF),
    canvas: Color(0xFFC5D8CC),
    textPrimary: Color(0xFF2A3430),
    textSecondary: Color(0xFF5E6E66),
    textTertiary: Color(0xFF8A9B92),
    divider: Color(0xFFB5C8BC),
    accentMuted: Color(0x245F8A6C),
    accentMutedStrong: Color(0x385F8A6C),
    shadowSoft: Color(0x1A2E3834),
    shadowLift: Color(0x262E3834),
    shadowHairline: Color(0x0D2E3834),
    error: Color(0xFFC48888),
    onError: Color(0xFFFFFFFF),
    morandi: [
      Color(0xFFB5C4B8),
      Color(0xFFA8B5B0),
      Color(0xFF9EB5A8),
      Color(0xFFA8B8B5),
      Color(0xFFC0C9B5),
      Color(0xFFADB8A3),
      Color(0xFFA3B5AD),
    ],
  );

  static const _mistBlue = AppThemePalette(
    background: Color(0xFFD8E2EA),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF5A788A),
    onAccent: Color(0xFFFFFFFF),
    canvas: Color(0xFFC5D2DC),
    textPrimary: Color(0xFF2A3036),
    textSecondary: Color(0xFF5E6A74),
    textTertiary: Color(0xFF8A96A0),
    divider: Color(0xFFB4C2CC),
    accentMuted: Color(0x245A788A),
    accentMutedStrong: Color(0x385A788A),
    shadowSoft: Color(0x1A353A3D),
    shadowLift: Color(0x26353A3D),
    shadowHairline: Color(0x0D353A3D),
    error: Color(0xFFC17B7B),
    onError: Color(0xFFFFFFFF),
    morandi: [
      Color(0xFFB5C4CE),
      Color(0xFFA8B5C4),
      Color(0xFF9EB0B8),
      Color(0xFFA8B0B8),
      Color(0xFFC0C9D4),
      Color(0xFFADB8C4),
      Color(0xFFA3B0B8),
    ],
  );

  static const _lavenderGrey = AppThemePalette(
    background: Color(0xFFE0DAEA),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF7A6696),
    onAccent: Color(0xFFFFFFFF),
    canvas: Color(0xFFCFC6DC),
    textPrimary: Color(0xFF302C38),
    textSecondary: Color(0xFF6A6478),
    textTertiary: Color(0xFF968EAA),
    divider: Color(0xFFBDB4CC),
    accentMuted: Color(0x247A6696),
    accentMutedStrong: Color(0x387A6696),
    shadowSoft: Color(0x1A38353D),
    shadowLift: Color(0x2638353D),
    shadowHairline: Color(0x0D38353D),
    error: Color(0xFFC17B7B),
    onError: Color(0xFFFFFFFF),
    morandi: [
      Color(0xFFC9C0D4),
      Color(0xFFB8A8C4),
      Color(0xFFADA3B8),
      Color(0xFFB5A8B8),
      Color(0xFFD4C9E0),
      Color(0xFFC4B0C9),
      Color(0xFFB0A3B5),
    ],
  );

  static const _cementGrey = AppThemePalette(
    background: Color(0xFFDCDCDC),
    card: Color(0xFFFFFFFF),
    accent: Color(0xFF5C5C5C),
    onAccent: Color(0xFFFFFFFF),
    canvas: Color(0xFFC8C8C8),
    textPrimary: Color(0xFF242424),
    textSecondary: Color(0xFF5C5C5C),
    textTertiary: Color(0xFF8E8E8E),
    divider: Color(0xFFB8B8B8),
    accentMuted: Color(0x245C5C5C),
    accentMutedStrong: Color(0x385C5C5C),
    shadowSoft: Color(0x1A2C2C2C),
    shadowLift: Color(0x262C2C2C),
    shadowHairline: Color(0x0D2C2C2C),
    error: Color(0xFFC17B7B),
    onError: Color(0xFFFFFFFF),
    morandi: [
      Color(0xFFB8B8B8),
      Color(0xFFA8A8A8),
      Color(0xFF9E9E9E),
      Color(0xFFADADAD),
      Color(0xFFC9C9C9),
      Color(0xFFB0B0B0),
      Color(0xFFA3A3A3),
    ],
  );

  static const _darkCoffee = AppThemePalette(
    background: Color(0xFF1A1A1A),
    card: Color(0xFF252525),
    accent: Color(0xFFC4A882),
    onAccent: Color(0xFF1A1A1A),
    canvas: Color(0xFF2A2826),
    textPrimary: Color(0xFFF0EEEB),
    textSecondary: Color(0xFFA8A5A0),
    textTertiary: Color(0xFF6E6C68),
    divider: Color(0xFF353535),
    accentMuted: Color(0x33C4A882),
    accentMutedStrong: Color(0x4DC4A882),
    shadowSoft: Color(0x40000000),
    shadowLift: Color(0x59000000),
    shadowHairline: Color(0x26000000),
    error: Color(0xFFD48989),
    onError: Color(0xFF1A1A1A),
    morandi: [
      Color(0xFF8A8078),
      Color(0xFF7A7570),
      Color(0xFF6E6A65),
      Color(0xFF858078),
      Color(0xFF9A9088),
      Color(0xFF807870),
      Color(0xFF757068),
    ],
  );

  static const _cyber2077 = AppThemePalette(
    background: Color(0xFF0B0E14),
    card: Color(0xFF141822),
    accent: Color(0xFFFCEE0A),
    onAccent: Color(0xFF0B0E14),
    canvas: Color(0xFF1C2333),
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFF8B93A8),
    textTertiary: Color(0xFF5C6478),
    divider: Color(0xFF2A3347),
    accentMuted: Color(0x33FCEE0A),
    accentMutedStrong: Color(0x4DFCEE0A),
    shadowSoft: Color(0x40000000),
    shadowLift: Color(0x66000000),
    shadowHairline: Color(0x2600E5FF),
    error: Color(0xFFFF375F),
    onError: Color(0xFF0B0E14),
    morandi: [
      Color(0xFFFCEE0A),
      Color(0xFF00E5FF),
      Color(0xFFFF2A6D),
      Color(0xFFBD00FF),
      Color(0xFF5C6478),
      Color(0xFF2A3347),
      Color(0xFF1C2333),
    ],
  );

}
