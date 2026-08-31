import 'package:flutter/material.dart';
import 'package:signals/signals_core.dart';

/// 收藏搜索：顶栏胶囊与收藏页共享的单一状态。
///
/// [controller] 只被顶栏的搜索框持有（App 生命周期，随进程结束），
/// 输入实时同步到 [query]；收藏页只读 [query] 驱动过滤。
class BookmarkSearchState {
  BookmarkSearchState() {
    controller.addListener(() {
      if (query.value != controller.text) query.value = controller.text;
    });
  }

  final controller = TextEditingController();
  final query = signal<String>('');

  void clear() {
    controller.clear();
    query.value = '';
  }
}
