import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 右下角创建 / 加入一体胶囊按钮。
class CreateJoinPill extends StatelessWidget {
  const CreateJoinPill({
    super.key,
    required this.onCreate,
    required this.onJoin,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;

    return Material(
      color: palette.card,
      elevation: 3,
      shadowColor: palette.shadowSoft,
      borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.space8,
          AppDimensions.space8,
          AppDimensions.space12,
          AppDimensions.space8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: palette.accent,
              borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
              child: InkWell(
                onTap: onCreate,
                borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.space16,
                    vertical: AppDimensions.space12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: palette.onAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '创建',
                        style: TextStyle(
                          color: palette.onAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onJoin,
              borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.space12,
                  vertical: AppDimensions.space12,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_add_alt_1_outlined,
                      size: 18,
                      color: palette.textPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '加入',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
