import 'dart:typed_data';
import 'package:astral_game/config/theme.dart';
import 'package:astral_game/ui/widgets/avatar_widget.dart';
import 'package:astral_game/ui/widgets/chrome_bar.dart';
import 'package:flutter/material.dart';

/// 桌面端不支持时的手机/平板顶栏：模拟桌面标题栏，头像落在窗口按钮区域。
///
/// [center] 非空时隐藏应用名，中间区域显示该组件（如收藏页搜索胶囊）。
class MobileChromeBar extends StatelessWidget {
  const MobileChromeBar({
    super.key,
    required this.avatar,
    required this.username,
    required this.onAvatarTap,
    this.center,
  });

  final Uint8List? avatar;
  final String username;
  final VoidCallback onAvatarTap;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return ChromeBar(
      center: center,
      background: context.astralPalette.canvas,
      applySafeArea: true,
      trailing: ProfileCapsule(
        avatar: avatar,
        username: username.trim().isEmpty ? '玩家' : username.trim(),
        onTap: onAvatarTap,
      ),
    );
  }
}
