import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import 'mobile_workbench_state.dart';

/// 生成工作台的页签栏：页签等分整行宽度，选中底跟随横滑位置连续移动。
///
/// 页签数量固定且少，任何宽度下都不横向滚动：文字最多放大到 1.6 倍，
/// 仍放不下时在各自分段内等比缩小。
class MobileWorkbenchTabBar extends StatelessWidget {
  const MobileWorkbenchTabBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.tabs = MobileWorkbenchTab.values,
    this.referenceCount = 0,
    this.hasUnseenResult = false,
    this.position,
  });

  /// 宽横屏时图像常驻左侧，页签栏只保留编辑类页签。
  static const editingTabs = [
    MobileWorkbenchTab.prompt,
    MobileWorkbenchTab.params,
    MobileWorkbenchTab.references,
    MobileWorkbenchTab.history,
  ];

  static const double maxTextScale = 1.6;

  final MobileWorkbenchTab selected;
  final ValueChanged<MobileWorkbenchTab> onSelected;
  final List<MobileWorkbenchTab> tabs;
  final int referenceCount;
  final bool hasUnseenResult;

  /// 以 [tabs] 下标计的连续位置（横滑中为小数）；为 null 时选中底停在
  /// [selected] 并以动画过渡。
  final ValueListenable<double>? position;

  static const double _padding = 4;

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
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: Builder(builder: _buildBar),
    );
  }

  Widget _buildBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appTheme = theme.appTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final selectedIndex = tabs.indexOf(selected).clamp(0, tabs.length - 1);
    final segmentHeight = (scaler.scale(14) * 1.4 + 16).clamp(44.0, 64.0);
    final light = colors.brightness == Brightness.light;
    final radius = appTheme.controlRadius;
    final thumb = DecoratedBox(
      decoration: BoxDecoration(
        color: light
            ? colors.surfaceContainerLowest
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: light
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
    );

    return Semantics(
      container: true,
      label: context.l10n.mobileWorkbench_tabsLabel,
      child: Container(
        key: const ValueKey('mobile-workbench-tab-bar'),
        padding: const EdgeInsets.all(_padding),
        decoration: BoxDecoration(
          color: controlSurfaceColor(colors),
          borderRadius: BorderRadius.circular(radius + _padding),
        ),
        child: SizedBox(
          height: segmentHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / tabs.length;
              return Stack(
                children: [
                  _Thumb(
                    position: position,
                    selectedIndex: selectedIndex,
                    segmentWidth: segmentWidth,
                    lastIndex: tabs.length - 1,
                    child: thumb,
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
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 选中底：有连续位置时逐帧跟随，否则按选中项做一次过渡。
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.position,
    required this.selectedIndex,
    required this.segmentWidth,
    required this.lastIndex,
    required this.child,
  });

  final ValueListenable<double>? position;
  final int selectedIndex;
  final double segmentWidth;
  final int lastIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final position = this.position;
    if (position == null) {
      final appTheme = Theme.of(context).appTheme;
      return AnimatedPositioned(
        key: const ValueKey('mobile-workbench-tab-thumb'),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : appTheme.normalDuration,
        curve: appTheme.standardCurve,
        left: segmentWidth * selectedIndex,
        top: 0,
        bottom: 0,
        width: segmentWidth,
        child: child,
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: position,
      child: child,
      builder: (context, value, child) => Positioned(
        key: const ValueKey('mobile-workbench-tab-thumb'),
        left: segmentWidth * value.clamp(0, lastIndex.toDouble()),
        top: 0,
        bottom: 0,
        width: segmentWidth,
        child: child!,
      ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
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
                    if (showCount) ...[
                      const SizedBox(width: 5),
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
                      const SizedBox(width: 5),
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
        ),
      ),
    );
  }
}
