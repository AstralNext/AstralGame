import 'dart:async';

import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:flutter/material.dart';

OverlayEntry? _activeEntry;
Timer? _dismissTimer;

/// 全项目统一的轻提示：iOS 风格底部胶囊。
///
/// 不再使用 SnackBar / ScaffoldMessenger：提示直接插入根 Overlay，
/// 因此会浮在底部导航之上，页面切换或弹窗关闭时也不会排队。
/// 同一时间只显示一条，后到的提示会立即替换前一条。
///
/// [duration] 为提示停留时长，默认 2.2 秒。
/// [actionLabel] + [onAction] 同时提供时，右侧显示操作文字（如「撤销」）。
void showAppToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2200),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  _dismissTimer?.cancel();
  final previous = _activeEntry;
  _activeEntry = null;
  if (previous != null) {
    previous.remove();
    previous.dispose();
  }

  final key = GlobalKey<_ToastViewState>();
  late final OverlayEntry entry;

  void handleDismissed() {
    if (!identical(_activeEntry, entry)) return;
    _activeEntry = null;
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) => _ToastView(
      key: key,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      onDismissed: handleDismissed,
    ),
  );
  _activeEntry = entry;
  overlay.insert(entry);
  _dismissTimer = Timer(duration, () => key.currentState?.dismiss());
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    super.key,
    required this.message,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curve;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(curve);
    _controller.forward();
  }

  void dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _controller.reverse().whenComplete(widget.onDismissed);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final palette = context.astralPalette;
    final textTheme = Theme.of(context).textTheme;
    // 手机端提示要抬到底部导航胶囊之上；其余端贴近底部即可。
    final isCompact = media.size.width < AppBreakpoints.narrow;
    final bottom = media.padding.bottom + (isCompact ? 96.0 : 28.0);
    final hasAction = widget.actionLabel != null && widget.onAction != null;

    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Semantics(
                liveRegion: true,
                child: GlassCapsule(
                  radius: BorderRadius.circular(999),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: dismiss,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                widget.message,
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            if (hasAction) ...[
                              const SizedBox(width: 12),
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () {
                                  widget.onAction?.call();
                                  dismiss();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    widget.actionLabel!,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: palette.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
