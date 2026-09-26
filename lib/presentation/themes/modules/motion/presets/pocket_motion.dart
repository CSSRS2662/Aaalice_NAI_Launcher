/// Pocket Motion - 单向减速，无回弹与过冲
///
/// 高频状态 150ms，面板与页面 240–300ms；动效只用来解释状态变化。
library;

import 'package:flutter/animation.dart';
import 'package:nai_launcher/presentation/themes/modules/motion/motion_module.dart';

class PocketMotion extends BaseMotionModule {
  const PocketMotion();

  @override
  Duration get fastDuration => const Duration(milliseconds: 150);

  @override
  Duration get normalDuration => const Duration(milliseconds: 240);

  @override
  Duration get slowDuration => const Duration(milliseconds: 300);

  @override
  Curve get enterCurve => const Cubic(0.2, 0, 0, 1);

  @override
  Curve get exitCurve => const Cubic(0.3, 0, 1, 1);

  @override
  Curve get standardCurve => const Cubic(0.2, 0, 0, 1);
}
