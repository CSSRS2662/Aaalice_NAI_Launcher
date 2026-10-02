import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/image/image_params.dart';
import '../../../data/models/user/user_subscription.dart';
import '../../providers/image_generation_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../themes/theme_extension.dart';
import 'opus_stamina_sheet.dart';

/// V5 体力在界面上的归一化读数。
class OpusStaminaLevel {
  OpusStaminaLevel.from(OpusUsageInfo usage)
    : exhausted = usage.isNegative || usage.percent <= 0,
      percent = usage.isNegative ? 0 : math.max(0, usage.percent);

  final bool exhausted;
  final double percent;

  /// 活动加成可让剩余量超过 100%。
  bool get overflow => percent > 100;
  bool get low => !exhausted && percent < 10;

  /// 超出上限时按实际值拉伸刻度，并在 100% 处画一条分界线。
  double get _scale => math.max(100, percent);
  double get fillFraction =>
      exhausted ? 0 : (percent / _scale).clamp(0, 1).toDouble();
  double? get capFraction => overflow ? 100 / _scale : null;
}

/// 读取当前是否需要展示体力：Opus 订阅、订阅响应携带 usage、当前模型受限。
OpusUsageInfo? watchVisibleOpusUsage(WidgetRef ref) {
  final usage = ref.watch(
    subscriptionNotifierProvider.select(
      (state) =>
          state.subscription?.isOpus == true ? state.subscription?.usage : null,
    ),
  );
  final limited = ref.watch(
    generationParamsNotifierProvider.select(
      (params) => params.capabilities.hasOpusUsageLimit,
    ),
  );
  return limited ? usage : null;
}

/// 生成按钮上方的体力读数：闪电图标、轨道与剩余百分比，点按打开详情。
/// 不显示时（非 Opus、无额度数据或模型不受限）不占空间。
class OpusStaminaBar extends ConsumerWidget {
  const OpusStaminaBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = watchVisibleOpusUsage(ref);
    if (usage == null) return const SizedBox.shrink();
    final level = OpusStaminaLevel.from(usage);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final percentText = level.exhausted
        ? context.l10n.stamina_stateExhausted
        : '${level.percent.round()}%';
    final accent = level.exhausted || level.low ? colors.error : colors.primary;
    return Semantics(
      button: true,
      label: context.l10n.stamina_barSemantics(percentText),
      onTap: () => showOpusStaminaSheet(context),
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('opus-stamina-bar'),
        onTap: () => showOpusStaminaSheet(context),
        borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: accent),
                const SizedBox(width: 6),
                Expanded(child: OpusStaminaTrack(level: level, height: 6)),
                const SizedBox(width: 10),
                Text(
                  percentText,
                  key: const ValueKey('opus-stamina-percent'),
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: level.exhausted ? colors.error : colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 体力轨道：底色轨道、填充与超出上限时的 100% 分界线。
class OpusStaminaTrack extends StatelessWidget {
  const OpusStaminaTrack({super.key, required this.level, this.height = 4});

  final OpusStaminaLevel level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appTheme = theme.appTheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : appTheme.slowDuration;
    final radius = BorderRadius.circular(height);
    final cap = level.capFraction;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: level.fillFraction),
              duration: duration,
              curve: appTheme.standardCurve,
              builder: (context, value, _) => FractionallySizedBox(
                key: const ValueKey('opus-stamina-fill'),
                alignment: Alignment.centerLeft,
                widthFactor: value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: level.exhausted ? colors.error : colors.primary,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
            if (cap != null)
              Align(
                alignment: Alignment(cap * 2 - 1, 0),
                child: SizedBox(
                  width: 2,
                  child: ColoredBox(color: colors.surface),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
