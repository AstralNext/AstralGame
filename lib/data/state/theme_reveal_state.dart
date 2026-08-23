import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals.dart';

/// 主题选择结果：目标主题 + 点击位置（全局坐标，用于水滴展开）。
class ThemePickResult {
  const ThemePickResult(this.themeId, this.origin);

  final AppThemeId themeId;
  final Offset origin;
}

/// 主题水滴展开揭示状态。
class ThemeRevealState {
  const ThemeRevealState._({this.origin, this.previousThemeId});

  const ThemeRevealState.idle() : this._();

  const ThemeRevealState.revealing({
    required Offset origin,
    required AppThemeId previousThemeId,
  }) : this._(origin: origin, previousThemeId: previousThemeId);

  final Offset? origin;
  final AppThemeId? previousThemeId;

  bool get isActive => previousThemeId != null;
}

/// 主题水滴揭示（与 [SettingsState.appThemeId] 配合）。
class ThemeRevealController {
  ThemeRevealController(this._settings);

  final SettingsState _settings;
  final reveal = signal(const ThemeRevealState.idle());

  void beginReveal({required Offset origin, required AppThemeId newTheme}) {
    final previous = _settings.appThemeId.value;
    if (previous == newTheme) return;

    _settings.appThemeId.value = newTheme;
    reveal.value = ThemeRevealState.revealing(
      origin: origin,
      previousThemeId: previous,
    );
  }

  void finishReveal() {
    if (!reveal.value.isActive) return;
    reveal.value = const ThemeRevealState.idle();
  }
}
