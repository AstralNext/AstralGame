import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 头像形状
enum AvatarShape {
  circle,
  roundedSquare,
}

/// 头像组件
///
/// 统一的头像显示组件，支持圆形和圆角方形
class AvatarWidget extends StatelessWidget {
  /// 头像数据
  final Uint8List? avatar;
  
  /// 头像大小
  final double size;
  
  /// 点击回调
  final VoidCallback? onTap;
  
  /// 头像形状
  final AvatarShape shape;
  
  /// 圆角半径（仅当 shape 为 roundedSquare 时有效）
  final double? borderRadius;
  
  /// 占位图标
  final IconData placeholderIcon;
  
  /// 边框宽度
  final double borderWidth;
  
  /// 是否显示边框
  final bool showBorder;

  const AvatarWidget({
    super.key,
    this.avatar,
    this.size = 40,
    this.onTap,
    this.shape = AvatarShape.circle,
    this.borderRadius,
    this.placeholderIcon = Icons.person,
    this.borderWidth = 1,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget avatarContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: shape == AvatarShape.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: shape == AvatarShape.roundedSquare 
            ? BorderRadius.circular(borderRadius ?? size * 0.25)
            : null,
        color: colorScheme.primaryContainer,
        border: showBorder 
            ? Border.all(color: colorScheme.outline, width: borderWidth)
            : null,
      ),
      child: avatar != null
          ? ClipRRect(
              borderRadius: shape == AvatarShape.circle 
                  ? BorderRadius.circular(size / 2)
                  : BorderRadius.circular(borderRadius ?? size * 0.25),
              child: Image.memory(
                avatar!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
              ),
            )
          : Icon(
              placeholderIcon,
              size: size * 0.5,
              color: colorScheme.onPrimaryContainer,
            ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }

    return avatarContent;
  }
}
