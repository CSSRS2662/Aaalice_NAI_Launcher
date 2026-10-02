import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/anlas/anlas_balance_chip.dart';
import '../../../widgets/anlas/opus_stamina_bar.dart';

/// 底栏上方的额度条：左侧 V5 体力（有额度数据时）与剩余百分比，右侧 Anlas
/// 余额，同在一块低对比色面上。点体力看详情，点余额刷新。窄屏或大字号下
/// 两者在同一色面内分为上下两行。
class MobileGenerationStatusStrip extends ConsumerWidget {
  const MobileGenerationStatusStrip({super.key});

  /// Width per text-scale unit below which stamina and balance stack.
  static const double _inlineWidth = 260;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final showStamina = watchVisibleOpusUsage(ref) != null;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final balance = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: const Center(child: AnlasBalanceChip(embedded: true)),
    );
    return DecoratedBox(
      key: const ValueKey('generation-mobile-status-strip'),
      decoration: BoxDecoration(
        color: controlSurfaceColor(colors),
        borderRadius: BorderRadius.circular(theme.appTheme.controlRadius + 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (showStamina &&
                constraints.maxWidth < _inlineWidth * textScale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OpusStaminaBar(),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: balance,
                  ),
                ],
              );
            }
            return _inline(colors, showStamina, balance);
          },
        ),
      ),
    );
  }

  static Widget _inline(ColorScheme colors, bool showStamina, Widget balance) =>
      Row(
        children: [
          if (showStamina) ...[
            const Expanded(child: OpusStaminaBar()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                width: 1,
                height: 20,
                child: ColoredBox(
                  color: colors.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          ] else
            const Spacer(),
          balance,
        ],
      );
}
