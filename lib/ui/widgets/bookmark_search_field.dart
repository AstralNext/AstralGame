import 'package:astral_game/config/theme.dart';
import 'package:astral_game/data/state/bookmark_search_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/glass_capsule.dart';
import 'package:flutter/material.dart';

/// 顶栏中央的 MD3 搜索胶囊（收藏 Tab，桌面/平板）。
///
/// 宽度撑满顶栏中间区域（桌面端限宽居中），输入实时写入
/// [BookmarkSearchState.query]，收藏页据此过滤。
/// 外层包一层空 [GestureDetector] 抢占拖拽手势，避免在搜索框内
/// 选中文本时触发窗口拖动。
class BookmarkSearchField extends StatelessWidget {
  const BookmarkSearchField({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final state = getIt<BookmarkSearchState>();
    // 空手势处理抢占拖拽竞技场：搜索框内拖选文本不会触发窗口拖动。
    return GestureDetector(
      onPanStart: (_) {},
      child: TextField(
        controller: state.controller,
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.accentMuted,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18,
            color: palette.textSecondary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 18,
          ),
          // 有输入时显示清除按钮；ListenableBuilder 随 controller 文本显隐。
          suffixIcon: ListenableBuilder(
            listenable: state.controller,
            builder: (context, _) => state.controller.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 18,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 15),
                    color: palette.textSecondary,
                    onPressed: state.clear,
                  ),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 18,
          ),
          hintText: '搜索收藏',
          hintStyle: TextStyle(color: palette.textTertiary, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(19),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// 手机端浮在底部的搜索胶囊：点击底栏右侧搜索圆钮后展开，
/// 与导航胶囊同款磨砂玻璃，输入同样写入 [BookmarkSearchState.query]。
class BookmarkSearchBar extends StatelessWidget {
  const BookmarkSearchBar({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    final state = getIt<BookmarkSearchState>();
    final radius = BorderRadius.circular(32);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: GlassCapsule(
        radius: radius,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 18),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: state.controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: palette.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '搜索收藏',
                    hintStyle: TextStyle(
                      color: palette.textTertiary,
                      fontSize: 15,
                    ),
                  ),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                ),
              ),
              ListenableBuilder(
                listenable: state.controller,
                builder: (context, _) => state.controller.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: '清空',
                        onPressed: state.clear,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: palette.textSecondary,
                      ),
              ),
              IconButton(
                tooltip: '收起搜索',
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  onClose();
                },
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
                color: palette.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
