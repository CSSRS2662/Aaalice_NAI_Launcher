import 'package:flutter/material.dart';

/// Anlas 图标：NovelAI 标志（LobeHub 图标集，MIT），按主题色着色。官网的
/// Anlas 专用符号没有开放授权的来源，因此统一用官方标志表示 Anlas。
class AnlasIcon extends StatelessWidget {
  const AnlasIcon({super.key, this.size = 16, this.color});

  static const String asset = 'assets/icons/ai_brands/novelai.png';

  final double size;

  /// Defaults to the ambient [IconTheme] color.
  final Color? color;

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    width: size,
    height: size,
    color: color ?? IconTheme.of(context).color,
    colorBlendMode: BlendMode.srcIn,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}
