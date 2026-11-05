import 'package:astral_game/config/app_dimensions.dart';
import 'package:astral_game/data/models/transport_mode.dart';
import 'package:astral_game/ui/widgets/pear_transport_panel.dart';
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
    final isNarrow = MediaQuery.sizeOf(context).width < AppBreakpoints.narrow;
    final startPad = isNarrow
        ? AppDimensions.pagePaddingHMobile
        : AppDimensions.pagePaddingHWithSideNav;
    final endPad = isNarrow
        ? AppDimensions.pagePaddingHMobile
        : AppDimensions.pagePaddingH;

    return ListView(
      controller: scrollController,
      padding: EdgeInsetsDirectional.fromSTEB(
        startPad,
        AppDimensions.sectionGap,
        endPad,
        AppDimensions.listBottomWithNav(context),
      ),
      children: [
        switch (mode) {
          TransportMode.steam => const SteamTransportPanel(),
          TransportMode.pear => const PearTransportPanel(),
          TransportMode.easytier => const SizedBox.shrink(),
        },
      ],
    );
  }
}
