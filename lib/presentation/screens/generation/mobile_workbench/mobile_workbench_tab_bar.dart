import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/common/horizontal_segmented_control.dart';
import 'mobile_workbench_state.dart';

/// 生成工作台的页签栏：等宽分段、滑动选中底，宽度不足时整行横向滚动。
class MobileWorkbenchTabBar extends StatelessWidget {
  const MobileWorkbenchTabBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.tabs = MobileWorkbenchTab.values,
    this.referenceCount = 0,
    this.hasUnseenResult = false,
  });

  /// 宽横屏时图像常驻左侧，页签栏只保留编辑类页签。
  static const editingTabs = [
    MobileWorkbenchTab.prompt,
    MobileWorkbenchTab.params,
    MobileWorkbenchTab.references,
    MobileWorkbenchTab.history,
  ];

  final MobileWorkbenchTab selected;
  final ValueChanged<MobileWorkbenchTab> onSelected;
  final List<MobileWorkbenchTab> tabs;
  final int referenceCount;
  final bool hasUnseenResult;

  static const double _padding = 4;
  static const double _badgeExtent = 26;
  static const double _dotExtent = 13;

  static String label(BuildContext context, MobileWorkbenchTab tab) {
    final l10n = context.l10n;
    return switch (tab) {
      MobileWorkbenchTab.image => l10n.mobileWorkbench_tabImage,
      MobileWorkbenchTab.prompt => l10n.mobileWorkbench_tabPrompt,
      MobileWorkbenchTab.params => l10n.mobileWorkbench_tabParams,
      MobileWorkbenchTab.references => l10n.mobileWorkbench_tabReferences,
      MobileWorkbenchTab.history => l10n.mobileWorkbench_tabHistory,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appTheme = theme.appTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = theme.textTheme.labelLarge ?? const TextStyle();
    final direction = Directionality.of(context);
    final selectedIndex = tabs.indexOf(selected).clamp(0, tabs.length - 1);

    double naturalWidth(MobileWorkbenchTab tab) {
      final painter = TextPainter(
        text: TextSpan(text: label(context, tab), style: labelStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      var width = painter.width + 24;
      if (tab == MobileWorkbenchTab.references && referenceCount > 0) {
        width += _badgeExtent;
      }
      if (tab == MobileWorkbenchTab.image && hasUnseenResult) {
        width += _dotExtent;
      }
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final widest = tabs.map(naturalWidth).reduce(math.max);
        final available = math.max(0.0, constraints.maxWidth - _padding * 2);
        final segmentWidth = math.max(available / tabs.length, widest);
        final segmentHeight = math.max(40.0, scaler.scale(14) * 1.4 + 18);
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : appTheme.normalDuration;
        final thumbColor = colors.brightness == Brightness.light
            ? colors.surfaceContainerLow
            : colors.surfaceContainerHighest;
        final radius = appTheme.controlRadius;

        return HorizontalSegmentedControl(
          child: Semantics(
            container: true,
            label: context.l10n.mobileWorkbench_tabsLabel,
            child: Container(
              key: const ValueKey('mobile-workbench-tab-bar'),
              width: segmentWidth * tabs.length + _padding * 2,
              padding: const EdgeInsets.all(_padding),
              decoration: BoxDecoration(
                color: controlSurfaceColor(colors),
                borderRadius: BorderRadius.circular(radius + _padding),
              ),
              child: SizedBox(
                height: segmentHeight,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: duration,
                      curve: appTheme.standardCurve,
                      left: segmentWidth * selectedIndex,
                      top: 0,
                      bottom: 0,
                      width: segmentWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: thumbColor,
                          borderRadius: BorderRadius.circular(radius),
                          boxShadow: colors.brightness == Brightness.light
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final tab in tabs)
                          SizedBox(
                            width: segmentWidth,
                            child: _Segment(
                              tab: tab,
                              label: label(context, tab),
                              selected: tab == selected,
                              radius: radius,
                              referenceCount: referenceCount,
                              showUnseenDot:
                                  hasUnseenResult &&
                                  tab == MobileWorkbenchTab.image &&
                                  tab != selected,
                              onTap: () => onSelected(tab),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.tab,
    required this.label,
    required this.selected,
    required this.radius,
    required this.referenceCount,
    required this.showUnseenDot,
    required this.onTap,
  });

  final MobileWorkbenchTab tab;
  final String label;
  final bool selected;
  final double radius;
  final int referenceCount;
  final bool showUnseenDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final showCount =
        tab == MobileWorkbenchTab.references && referenceCount > 0;
    final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: showUnseenDot
          ? '$label, ${context.l10n.mobileWorkbench_newResult}'
          : label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('mobile-workbench-tab-${tab.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : theme.appTheme.fastDuration,
                    style: (theme.textTheme.labelLarge ?? const TextStyle())
                        .copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                    child: Text(label, maxLines: 1, softWrap: false),
                  ),
                ),
                if (showCount) ...[
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      child: Text(
                        referenceCount > 99 ? '99+' : '$referenceCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
                if (showUnseenDot) ...[
                  const SizedBox(width: 6),
                  DecoratedBox(
                    key: const ValueKey('mobile-workbench-unseen-dot'),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 7),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
