import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/config/app_theme_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'app_theme_id.dart';
export 'app_theme_palette.dart';

/// 优先系统 Noto Sans，中文回退微软雅黑。
abstract final class AppFonts {
  static const String family = 'Noto Sans';

  static const List<String> fallback = [
    'Noto Sans SC',
    'Microsoft YaHei',
    'Microsoft YaHei UI',
    '微软雅黑',
  ];
}

/// 弹窗遮罩统一用 35% 黑，避免各弹窗 32% / 40% / 默认 54% 混用。
const astralDialogBarrierColor = Color(0x59000000);

/// 全站统一的交互态透明度，避免各组件各写一套悬停/按压/禁用值。
abstract final class AppInteraction {
  static const hoverOpacity = 0.04;
  static const pressedOpacity = 0.08;
  static const focusOpacity = 0.06;
  static const disabledOpacity = 0.5;
}

/// 延迟配色阈值（毫秒），全站统一，避免同一成员在服务器页与房间页一绿一黄。
abstract final class LatencyTone {
  /// ≤ 该值为绿色（良好）。
  static const double goodMs = 80;

  /// ≤ 该值为黄色（一般）；超过为红色（较差）。
  static const double fairMs = 160;
}

/// 按 [LatencyTone] 把延迟映射成语义色。
Color latencyColor(AppThemePalette palette, double latencyMs) {
  if (latencyMs <= LatencyTone.goodMs) return palette.online;
  if (latencyMs <= LatencyTone.fairMs) return palette.warning;
  return palette.error;
}

/// 主题切换与水滴揭示动画参数。
abstract final class AppThemeAnimation {
  static const revealCurve = Curves.easeOutCubic;

  /// Material 主题色插值（已改用水滴揭示，保持为 0）。
  static const duration = Duration.zero;
  static const curve = Curves.linear;
}

/// Material 3 主题构建。
abstract final class AstralGameTheme {
  static ThemeData build(AppThemeId id) => _createThemeData(id);

  static ThemeData get defaultTheme => build(AppThemeId.insCream);

  static ThemeData _createThemeData(AppThemeId id) {
    final palette = AppThemePalette.of(id);
    // 与通用版一致：按页底亮度决定 Brightness，避免深色主题仍走 light 默认紫容器色。
    final isDarkSurface = palette.background.computeLuminance() < 0.45;
    final brightness = isDarkSurface ? Brightness.dark : Brightness.light;

    final page = palette.background;
    final raised = palette.card;
    final inset = palette.canvas;
    final insetDeep = Color.lerp(inset, palette.textPrimary, 0.06)!;
    final mid = Color.lerp(page, inset, 0.55)!;
    // ColorScheme 的 *Container 必须是不透明色。accentMuted* 带 alpha，只适合
    // splash/hover；若直接塞进 primaryContainer，FAB 会半透明并透出阴影。
    final primaryContainer = Color.lerp(raised, palette.accent, 0.22)!;
    final secondaryContainer = Color.lerp(raised, palette.accent, 0.12)!;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      secondary: palette.accent,
      onSecondary: palette.onAccent,
      error: palette.error,
      onError: palette.onError,
      surface: raised,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.divider,
      outlineVariant: Color.lerp(palette.divider, page, 0.35)!,
      primaryContainer: primaryContainer,
      onPrimaryContainer: palette.textPrimary,
      // Game 成员 chip / 选中态还会用到 secondary / tertiary container。
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: palette.textPrimary,
      tertiaryContainer: Color.lerp(inset, palette.accent, 0.14)!,
      onTertiaryContainer: palette.textSecondary,
      surfaceContainerLowest: page,
      surfaceContainerLow: raised,
      surfaceContainer: mid,
      surfaceContainerHigh: inset,
      surfaceContainerHighest: insetDeep,
    );

    final splash = palette.accentMuted;
    final highlight = palette.accent.withValues(alpha: 0.06);
    final overlayStyle = isDarkSurface
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppFonts.family,
      fontFamilyFallback: AppFonts.fallback,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      dividerColor: palette.divider,
      splashColor: splash,
      highlightColor: highlight,
      hoverColor: palette.accent.withValues(alpha: 0.04),
      extensions: [AstralPaletteExtension(palette)],
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.accent,
        textColor: palette.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: page,
        foregroundColor: palette.textPrimary,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.family,
          fontFamilyFallback: AppFonts.fallback,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: palette.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: raised,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        ),
      ),
      iconTheme: IconThemeData(
        size: AppDimensions.iconSize,
        color: palette.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          elevation: 0,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
          minimumSize: const Size(0, 44),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusLg),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.canvas,
        // 透明描边保留 outline 缺口，避免浮动标签被填充色裁掉汉字上半截。
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          borderSide: const BorderSide(color: Colors.transparent),
          gapPadding: 6,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          borderSide: const BorderSide(color: Colors.transparent),
          gapPadding: 6,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
          gapPadding: 6,
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        floatingLabelAlignment: FloatingLabelAlignment.start,
        labelStyle: TextStyle(
          fontFamily: AppFonts.family,
          fontFamilyFallback: AppFonts.fallback,
          color: palette.textSecondary,
          height: 1.3,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: AppFonts.family,
          fontFamilyFallback: AppFonts.fallback,
          color: palette.textSecondary,
          height: 1.3,
        ),
        hintStyle: TextStyle(
          fontFamily: AppFonts.family,
          fontFamilyFallback: AppFonts.fallback,
          color: palette.textTertiary,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.onAccent;
          return palette.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.accent;
          }
          return palette.divider;
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: -1,
          color: palette.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.5,
          color: palette.textPrimary,
        ),
        displaySmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.5,
          color: palette.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: -0.3,
          color: palette.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: palette.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: -0.2,
          color: palette.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: palette.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: palette.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: palette.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: palette.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: palette.textTertiary,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: palette.textSecondary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: palette.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: palette.textTertiary,
        ),
      ),
    );
  }
}

@immutable
class AstralPaletteExtension extends ThemeExtension<AstralPaletteExtension> {
  const AstralPaletteExtension(this.palette);

  final AppThemePalette palette;

  @override
  AstralPaletteExtension copyWith({AppThemePalette? palette}) {
    return AstralPaletteExtension(palette ?? this.palette);
  }

  @override
  AstralPaletteExtension lerp(
    covariant ThemeExtension<AstralPaletteExtension>? other,
    double t,
  ) {
    if (other is! AstralPaletteExtension) return this;
    return AstralPaletteExtension(palette.lerp(other.palette, t));
  }
}

extension AstralThemeContext on BuildContext {
  AppThemePalette get astralPalette {
    final extension = Theme.of(this).extension<AstralPaletteExtension>();
    if (extension != null) return extension.palette;
    return AppThemePalette.of(AppThemeId.insCream);
  }
}
