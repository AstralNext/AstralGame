import 'package:flutter/material.dart';

/// 统一 SnackBar 入口：全项目轻提示都走这里，保证样式与行为一致。
///
/// [actionLabel] + [onAction] 同时提供时显示右侧操作按钮（如「撤销」）。
/// [duration] 传短时长（个别轻提示用），默认走 SnackBar 标准时长。
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(milliseconds: 4000),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ),
  );
}
