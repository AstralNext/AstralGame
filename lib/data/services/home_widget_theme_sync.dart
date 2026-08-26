import 'dart:io';

import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/config/app_theme_palette.dart';
import 'package:astral_game/config/home_widget_keys.dart';
import 'package:astral_game/utils/runtime_platform.dart';
import 'package:home_widget/home_widget.dart';

/// 将当前 App 主题色写入小组件 SharedPreferences。
Future<void> syncHomeWidgetTheme(AppThemeId themeId) async {
  if (!RuntimePlatform.isAndroid) return;

  final palette = AppThemePalette.of(themeId);
  await HomeWidget.saveWidgetData<int>(
    HomeWidgetKeys.themeCard,
    palette.card.toARGB32(),
  );
  await HomeWidget.saveWidgetData<int>(
    HomeWidgetKeys.themeCanvas,
    palette.canvas.toARGB32(),
  );
  await HomeWidget.saveWidgetData<int>(
    HomeWidgetKeys.themeTextPrimary,
    palette.textPrimary.toARGB32(),
  );
  await HomeWidget.saveWidgetData<int>(
    HomeWidgetKeys.themeTextSecondary,
    palette.textSecondary.toARGB32(),
  );
  await HomeWidget.saveWidgetData<int>(
    HomeWidgetKeys.themeAccent,
    palette.accent.toARGB32(),
  );
}
