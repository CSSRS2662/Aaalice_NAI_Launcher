/// Pocket Shapes - 克制的圆角层级
///
/// - 控件与标签：10px
/// - 按钮与输入：12px
/// - 分组卡片：16px
/// - 对话框与底部面板：24px
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/modules/shape/shape_module.dart';

class PocketShapes extends BaseShapeModule {
  const PocketShapes();

  static const double _controlRadius = 12;

  @override
  double get smallRadius => 10;

  @override
  double get mediumRadius => 24;

  @override
  double get largeRadius => 16;

  @override
  double get menuRadius => 12;

  @override
  ShapeBorder get cardShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(largeRadius));

  @override
  ShapeBorder get buttonShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_controlRadius),
  );

  @override
  ShapeBorder get inputShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_controlRadius),
  );

  @override
  ShapeBorder get menuShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(menuRadius));
}
