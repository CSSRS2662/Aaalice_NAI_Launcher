import 'dart:math' as math;

/// V5 Opus 使用上限（界面称“体力”）的估算。
///
/// 服务端只返回剩余百分比、是否透支与距下一个 1% 的秒数；张数与回满时间
/// 都是按网页端口径推算的近似值，界面必须标注“约”或“估算”。
abstract final class OpusUsageEstimator {
  /// 网页端按 1% ≈ 17.3 张估算（1MP 以内、每张计 1 份）。
  static const double imagesPerPercent = 17.3;

  /// 回充最快约每天 14%，即每个 1% 至少约 6171 秒。
  static const int fastestSecondsPerPercent = 6171;

  /// 网页端的面积扣份档位：大图一张消耗多份配额。
  static const List<(int, int)> _quotaUnitTiers = [
    (1048576, 1),
    (1747627, 2),
    (2446678, 3),
    (3145728, 4),
  ];

  static int quotaUnitsForArea(int area) {
    for (final (maxArea, units) in _quotaUnitTiers) {
      if (area <= maxArea) return units;
    }
    return _quotaUnitTiers.last.$2;
  }

  /// 以当前计费面积估算剩余可生成张数；透支或无余量时为 0。
  static int estimateImages({required double percent, required int area}) {
    if (percent <= 0) return 0;
    return (percent * imagesPerPercent / quotaUnitsForArea(area)).round();
  }

  /// 估算回满所需时间；已满或超出上限时返回 [Duration.zero]。
  ///
  /// 第一个 1% 使用服务端给出的剩余秒数；之后每个 1% 的周期取“最快回充
  /// 周期”与该剩余秒数中的较大者（剩余秒数更长说明当前回充更慢）。
  static Duration timeToFull({
    required double percent,
    required double secondsUntilNextPercent,
  }) {
    if (percent >= 100) return Duration.zero;
    final missingPercents = (100 - math.max(0, percent)).ceil();
    final next = math.max(0, secondsUntilNextPercent);
    final period = math.max(fastestSecondsPerPercent.toDouble(), next);
    final seconds = next + (missingPercents - 1) * period;
    return Duration(seconds: seconds.round());
  }
}
