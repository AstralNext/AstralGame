import 'package:flutter/material.dart';

/// 简单的分页按钮（上一页 / 当前页-总页数 / 下一页）。
/// 做了最小化 API：当前页、总页数、页码变化回调。
/// 首/末页时相应按钮自动禁用。
class PageNavigator extends StatelessWidget {
  const PageNavigator({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  /// 0-based 当前页
  final int currentPage;

  /// 总页数（0 时不渲染）
  final int totalPages;

  /// 0-based 回调（返回已经过 clamp 的合法页码）
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final clamped = currentPage.clamp(0, totalPages - 1);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: clamped == 0
                  ? null
                  : () => onPageChanged(clamped - 1),
              child: const Text('上一页'),
            ),
            const SizedBox(width: 12),
            Text(
              '${clamped + 1} / $totalPages',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: clamped + 1 < totalPages
                  ? () => onPageChanged(clamped + 1)
                  : null,
              child: const Text('下一页'),
            ),
          ],
        ),
      ),
    );
  }
}
