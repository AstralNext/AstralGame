import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/config/app_theme_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'app_theme_id.dart';
export 'app_theme_palette.dart';

/// 主题切换与水滴揭示动画参数。
abstract final class AppThemeAnimation {
  static const revealDuration = Duration(milliseconds: 580);
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
    final brightness =
        isDarkSurface ? Brightness.dark : Brightness.light;

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
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: raised,
        indicatorColor: palette.accent.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? palette.accent : palette.textSecondary,
            letterSpacing: 0.1,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: AppDimensions.iconSize,
            color: selected ? palette.accent : palette.textTertiary,
          );
        }),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.accent),
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
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          borderSide: const BorderSide(color: Colors.transparent, width: 1),
          gapPadding: 6,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          borderSide: const BorderSide(color: Colors.transparent, width: 1),
          gapPadding: 6,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
          gapPadding: 6,
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        floatingLabelAlignment: FloatingLabelAlignment.start,
        labelStyle: TextStyle(color: palette.textSecondary, height: 1.3),
        floatingLabelStyle: TextStyle(color: palette.textSecondary, height: 1.3),
        hintStyle: TextStyle(color: palette.textTertiary),
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
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: palette.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
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
