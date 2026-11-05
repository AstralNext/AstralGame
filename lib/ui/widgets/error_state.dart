import 'package:astral_game/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';

/// 全站统一错误态：图标 + 标题 + 原因，可选重试操作。
///
/// 与 [EmptyState] 共用同一套版式，避免各页面自行拼标题、说明与按钮。
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = '重试',
    this.icon = Icons.error_outline_rounded,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: icon,
      title: title,
      subtitle: message,
      actionLabel: onRetry == null ? null : retryLabel,
      actionIcon: Icons.refresh_rounded,
      onAction: onRetry,
    );
  }
}
