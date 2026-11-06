import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 右下角创建 / 加入一体胶囊按钮。
///
/// 视觉语言：
/// - 浮起阴影与 [AstralCard] 保持一致（同 blurRadius / offset）。
/// - 「创建」是主操作，整块 accent；「加入」压到次层级（次要文字色 + 小图标），
///   悬停时才浮现一层 accentMuted 底色。
/// - 两半点击区高度不低于 44，避免桌面端鼠标点不中。
///
/// 状态：
/// - [busy] 为 true（连接进行中）时两半都不可点，「创建」半图标换成进度圈；
/// - 连接失败 / 取消后由 `ConnectionService.isConnecting` 自动回落为 false，
///   按钮自行恢复可点，不依赖 toast 兜底。
class CreateJoinPill extends StatefulWidget {
  const CreateJoinPill({
    super.key,
    required this.onCreate,
    required this.onJoin,
    this.busy = false,
  });

  final VoidCallback? onCreate;
  final VoidCallback? onJoin;
  final bool busy;

  @override
  State<CreateJoinPill> createState() => _CreateJoinPillState();
}

class _CreateJoinPillState extends State<CreateJoinPill> {
  /// 可点击区域最小高度。
  static const double _minTapHeight = 44;

  static const double _iconSize = 18;

  bool _joinHovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final canCreate = !widget.busy && widget.onCreate != null;
    final canJoin = !widget.busy && widget.onJoin != null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDimensions.motionPage,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - t)),
            child: Transform.scale(
              scale: 0.98 + 0.02 * t,
              alignment: AlignmentDirectional.bottomEnd,
              child: child,
            ),
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
          boxShadow: [
            // 与 AstralCard 同一套浮起语言。
            BoxShadow(
              color: palette.shadowSoft,
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: palette.card,
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
          clipBehavior: Clip.antiAlias,
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
                _buildCreateHalf(context, canCreate),
                const SizedBox(width: 4),
                _buildJoinHalf(context, canJoin),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateHalf(BuildContext context, bool enabled) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapHeight),
      child: Material(
        color: palette.accent,
        borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? widget.onCreate : null,
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return palette.onAccent.withValues(
                alpha: AppInteraction.pressedOpacity,
              );
            }
            if (states.contains(WidgetState.hovered)) {
              return palette.onAccent.withValues(
                alpha: AppInteraction.hoverOpacity,
              );
            }
            if (states.contains(WidgetState.focused)) {
              return palette.onAccent.withValues(
                alpha: AppInteraction.focusOpacity,
              );
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.space16,
              vertical: AppDimensions.space12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: AnimatedSwitcher(
                    duration: AppDimensions.motionFast,
                    child: widget.busy
                        ? CircularProgressIndicator(
                            key: const ValueKey('busy'),
                            strokeWidth: 2,
                            color: palette.onAccent,
                          )
                        : Icon(
                            Icons.add_circle_outline,
                            key: const ValueKey('idle'),
                            size: _iconSize,
                            color: palette.onAccent,
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '创建',
                  style: textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                    color: palette.onAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinHalf(BuildContext context, bool enabled) {
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: enabled ? 1 : AppInteraction.disabledOpacity,
      child: AnimatedContainer(
        duration: AppDimensions.motionBase,
        constraints: const BoxConstraints(minHeight: _minTapHeight),
        decoration: BoxDecoration(
          color: _joinHovered && enabled
              ? palette.accentMuted
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? widget.onJoin : null,
            onHover: (hovering) {
              if (_joinHovered == hovering) return;
              setState(() => _joinHovered = hovering);
            },
            borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return palette.textPrimary.withValues(
                  alpha: AppInteraction.pressedOpacity,
                );
              }
              if (states.contains(WidgetState.focused)) {
                return palette.textPrimary.withValues(
                  alpha: AppInteraction.focusOpacity,
                );
              }
              return null;
            }),
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
                    size: 16,
                    color: palette.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '加入',
                    style: textTheme.labelLarge?.copyWith(
                      fontSize: 14,
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
