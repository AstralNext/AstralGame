import 'package:astral_game/config/theme.dart';
import 'package:flutter/material.dart';

/// 全站统一的状态语义，只用四种颜色，不叠加文字徽标。
enum AstralStatusTone {
  /// 亮绿：可加入 / 已就绪。
  ready,

  /// 暗绿：可加入，但进房时需要额外口令。
  secured,

  /// 黄：满员。
  full,

  /// 灰：不可加入 / 未就绪 / 离线 / 已关闭。
  unavailable,
}

/// 一个小圆点。没有底色、没有描边，颜色就是状态。
class AstralStatusDot extends StatelessWidget {
  const AstralStatusDot({
    super.key,
    required this.tone,
    this.size = 8,
    this.semanticLabel,
  });

  final AstralStatusTone tone;
  final double size;
  final String? semanticLabel;

  Color _color(AppThemePalette palette) {
    return switch (tone) {
      AstralStatusTone.ready => palette.online,
      AstralStatusTone.secured => Color.lerp(
        palette.online,
        Colors.black,
        0.38,
      )!,
      AstralStatusTone.full => palette.warning,
      AstralStatusTone.unavailable => palette.textTertiary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color(context.astralPalette),
        shape: BoxShape.circle,
      ),
    );
    if (semanticLabel == null) return dot;
    return Semantics(label: semanticLabel, child: dot);
  }
}

/// 「小圆点 + 短文字」：Steam 连接、传输就绪、成员在线等状态统一用这一种。
class AstralStatusLine extends StatelessWidget {
  const AstralStatusLine({super.key, required this.tone, required this.text});

  final AstralStatusTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.astralPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AstralStatusDot(tone: tone, semanticLabel: text),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: palette.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
