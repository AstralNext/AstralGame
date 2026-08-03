import 'package:astral_game/config/app_theme_id.dart';
import 'package:astral_game/data/state/theme_reveal_state.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/grouped_tile_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 主题色板底部弹层；选中项提供水滴揭示原点。
Future<ThemePickResult?> showAppThemePickerSheet(
  BuildContext context, {
  required AppThemeId current,
}) {
  final themes = AppThemeId.values;

  return showModalBottomSheet<ThemePickResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final sheetTheme = Theme.of(context);
      final scheme = sheetTheme.colorScheme;
      final viewHeight = MediaQuery.sizeOf(context).height;
      final sheetHeight = (viewHeight * 0.72).clamp(360.0, viewHeight * 0.92);

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('选择主题', style: sheetTheme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: AstralCard(
                      padding: EdgeInsets.zero,
                      shadow: false,
                      child: Column(
                        children: [
                          for (var i = 0; i < themes.length; i++)
                            ListTile(
                              shape: groupedTileShape(
                                index: i,
                                count: themes.length,
                              ),
                              title: Text(themes[i].label),
                              subtitle: Text(themes[i].subtitle),
                              trailing: themes[i] == current
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: scheme.primary,
                                    )
                                  : null,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                final box =
                                    context.findRenderObject() as RenderBox?;
                                final origin = box != null
                                    ? box.localToGlobal(
                                        box.size.center(Offset.zero),
                                      )
                                    : Offset(
                                        MediaQuery.sizeOf(context).width / 2,
                                        MediaQuery.sizeOf(context).height / 2,
                                      );
                                Navigator.pop(
                                  context,
                                  ThemePickResult(themes[i], origin),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
