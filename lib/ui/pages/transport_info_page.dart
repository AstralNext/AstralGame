import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/data/models/transport_mode.dart';
import 'package:astral_game/data/state/settings_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/page_header.dart';
import 'package:astral_game/ui/widgets/steam_transport_panel.dart';
import 'package:flutter/material.dart';

/// 非 EasyTier 驱动的一级 Tab 页面：服务器 Tab 在当前驱动下没有意义，
/// 直接展示该驱动的运行时、房间与成员信息。
class TransportInfoPage extends StatelessWidget {
  const TransportInfoPage({
    super.key,
    required this.mode,
    this.scrollController,
  });

  final TransportMode mode;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    // 统一判定入口：即使外部传入了 Steam，当前平台/开关不允许时也回落成
    // EasyTier 分支，不会渲染 Steam 面板。
    final effectiveMode = getIt<SettingsState>().transportGate.fallback(mode);
    final isNarrow = MediaQuery.sizeOf(context).width < AppBreakpoints.narrow;
    final startPad = isNarrow
        ? AppDimensions.pagePaddingHMobile
        : AppDimensions.pagePaddingHWithSideNav;
    final endPad = isNarrow
        ? AppDimensions.pagePaddingHMobile
        : AppDimensions.pagePaddingH;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          padding: EdgeInsetsDirectional.fromSTEB(startPad, 12, endPad, 8),
          subtitle: '${effectiveMode.menuLabel} 组网状态',
        ),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: EdgeInsetsDirectional.fromSTEB(
              startPad,
              4,
              endPad,
              // 窄屏为悬浮胶囊留出余量；宽屏没有底栏，只保留页面底部留白。
              isNarrow
                  ? AppDimensions.listBottomWithNav(context)
                  : AppDimensions.pagePaddingBottom,
            ),
            children: [
              switch (effectiveMode) {
                TransportMode.steam => const SteamTransportPanel(),
                TransportMode.easytier => const SizedBox.shrink(),
              },
            ],
          ),
        ),
      ],
    );
  }
}
