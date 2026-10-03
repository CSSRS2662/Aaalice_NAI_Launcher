import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../providers/subscription_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/anlas/anlas_balance_chip.dart';
import '../../../widgets/anlas/opus_stamina_bar.dart';

/// 顶栏右端的额度胶囊：V5 体力（闪电 + 剩余百分比，有额度数据时）与 Anlas
/// 余额。点体力看详情，点余额刷新。
class MobileQuotaPill extends ConsumerWidget {
  const MobileQuotaPill({super.key, required this.textStyle});

  /// Shared with the header's width estimate.
  final TextStyle? textStyle;

  // Horizontal space around each number, matching the child widgets.
  static const double _staminaChrome =
      OpusStaminaIndicator.horizontalPadding * 2 +
      OpusStaminaIndicator.iconSize +
      OpusStaminaIndicator.iconGap;
  static const double _balanceChrome = 8 + 14 + 4 + 8;
  static const double _divider = 1;

  /// The pill's natural width, for the header's fit decision.
  static double naturalWidth(
    BuildContext context,
    WidgetRef ref,
    TextStyle? style,
  ) {
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final usage = watchVisibleOpusUsage(ref);
    final balance = ref.watch(
      subscriptionNotifierProvider.select((state) => state.balance),
    );
    final balanceText = balance == null
        ? '--'
        : NumberFormat('#,###').format(balance);
    var width = _balanceChrome + measure(balanceText);
    if (usage != null) {
      final level = OpusStaminaLevel.from(usage);
      width +=
          _staminaChrome +
          _divider +
          measure(opusStaminaPercentText(context, level));
    }
    return width;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final showStamina = watchVisibleOpusUsage(ref) != null;
    return Material(
      key: const ValueKey('generation-mobile-quota'),
      color: controlSurfaceColor(colors),
      borderRadius: BorderRadius.circular(theme.appTheme.controlRadius + 2),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStamina) ...[
              OpusStaminaIndicator(textStyle: textStyle),
              SizedBox(
                width: _divider,
                height: 18,
                child: ColoredBox(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
            AnlasBalanceChip(
              compact: true,
              embedded: true,
              textStyle: textStyle,
            ),
          ],
        ),
      ),
    );
  }
}
