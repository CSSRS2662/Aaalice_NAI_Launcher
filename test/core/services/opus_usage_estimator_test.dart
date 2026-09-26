import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/opus_usage_estimator.dart';

void main() {
  group('OpusUsageEstimator', () {
    test('大图一张按面积档位消耗多份配额', () {
      expect(OpusUsageEstimator.quotaUnitsForArea(832 * 1216), 1);
      expect(OpusUsageEstimator.quotaUnitsForArea(1024 * 1536), 2);
      expect(OpusUsageEstimator.quotaUnitsForArea(1472 * 1472), 3);
      expect(OpusUsageEstimator.quotaUnitsForArea(1920 * 1088), 3);
      expect(OpusUsageEstimator.quotaUnitsForArea(4096 * 4096), 4);
    });

    test('估算张数随面积折算，透支时为 0', () {
      expect(
        OpusUsageEstimator.estimateImages(percent: 86, area: 832 * 1216),
        1488,
      );
      expect(
        OpusUsageEstimator.estimateImages(percent: 86, area: 1024 * 1536),
        744,
      );
      expect(OpusUsageEstimator.estimateImages(percent: 0, area: 1), 0);
      expect(OpusUsageEstimator.estimateImages(percent: -3, area: 1), 0);
    });

    test('已满或超出上限时回满时间为 0', () {
      expect(
        OpusUsageEstimator.timeToFull(percent: 100, secondsUntilNextPercent: 0),
        Duration.zero,
      );
      expect(
        OpusUsageEstimator.timeToFull(
          percent: 130,
          secondsUntilNextPercent: 7888,
        ),
        Duration.zero,
      );
    });

    test('回满时间以下一个 1% 的剩余秒数与较慢的回充周期推算', () {
      // 缺 14 个百分点；剩余秒数超过最快周期，说明当前回充更慢，整段按它计。
      expect(
        OpusUsageEstimator.timeToFull(
          percent: 86,
          secondsUntilNextPercent: 6780,
        ),
        const Duration(seconds: 6780 * 14),
      );
      // 剩余秒数短于最快周期时，其余百分点按最快周期估算。
      expect(
        OpusUsageEstimator.timeToFull(
          percent: 98.5,
          secondsUntilNextPercent: 600,
        ),
        const Duration(
          seconds: 600 + OpusUsageEstimator.fastestSecondsPerPercent,
        ),
      );
    });
  });
}
