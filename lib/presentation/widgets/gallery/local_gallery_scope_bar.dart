import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../providers/local_gallery_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/theme_extension.dart';

/// 本地图库的快捷范围栏：全部 / 收藏一键切换，日期与分类以可清除的条件
/// 显示当前取值。只负责呈现与转发，真实的过滤逻辑由调用方提供。
class LocalGalleryScopeBar extends ConsumerWidget {
  const LocalGalleryScopeBar({
    super.key,
    required this.onShowAll,
    required this.onShowFavorites,
    required this.onPickDateRange,
    required this.onClearDateRange,
    required this.onOpenCollections,
    required this.onClearCollection,
    this.collectionLabel,
  });

  /// 当前选中的分类或相簿名称；未选或正在看收藏时为 null。
  final String? collectionLabel;

  final VoidCallback onShowAll;
  final VoidCallback onShowFavorites;
  final VoidCallback onPickDateRange;
  final VoidCallback onClearDateRange;
  final VoidCallback onOpenCollections;
  final VoidCallback onClearCollection;

  static String formatDateRange(DateTime? start, DateTime? end) {
    final format = DateFormat('M/d');
    if (start != null && end != null) {
      return '${format.format(start)} ~ ${format.format(end)}';
    }
    if (start != null) return '${format.format(start)} ~';
    if (end != null) return '~ ${format.format(end)}';
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final criteria = ref.watch(
      localGalleryNotifierProvider.select((state) => state.filterCriteria),
    );
    final favorites = criteria.showFavoritesOnly;
    final hasDate = criteria.dateStart != null || criteria.dateEnd != null;
    final collection = favorites ? null : collectionLabel;

    return SingleChildScrollView(
      key: const ValueKey('local-gallery-scope-bar'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ScopeToggle(
            favorites: favorites,
            onShowAll: onShowAll,
            onShowFavorites: onShowFavorites,
          ),
          const SizedBox(width: 8),
          GalleryFilterChipButton(
            key: const ValueKey('local-gallery-date-chip'),
            clearKey: const ValueKey('local-gallery-date-clear'),
            icon: Icons.event_rounded,
            label: hasDate
                ? formatDateRange(criteria.dateStart, criteria.dateEnd)
                : l10n.common_date,
            active: hasDate,
            onPressed: onPickDateRange,
            onClear: hasDate ? onClearDateRange : null,
            clearTooltip: l10n.common_clear,
          ),
          const SizedBox(width: 8),
          GalleryFilterChipButton(
            key: const ValueKey('local-gallery-collection-chip'),
            clearKey: const ValueKey('local-gallery-collection-clear'),
            icon: Icons.folder_outlined,
            label: collection ?? l10n.common_categories,
            active: collection != null,
            onPressed: onOpenCollections,
            onClear: collection != null ? onClearCollection : null,
            clearTooltip: l10n.common_clear,
          ),
        ],
      ),
    );
  }
}

/// 全部 / 收藏两段切换，与生成页页签栏同一套控件语言。
class _ScopeToggle extends StatelessWidget {
  const _ScopeToggle({
    required this.favorites,
    required this.onShowAll,
    required this.onShowFavorites,
  });

  final bool favorites;
  final VoidCallback onShowAll;
  final VoidCallback onShowFavorites;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = theme.appTheme.controlRadius;
    final light = colors.brightness == Brightness.light;
    Widget segment({
      required Key key,
      required bool selected,
      required String label,
      required VoidCallback onTap,
      IconData? icon,
    }) {
      final foreground = selected ? colors.onSurface : colors.onSurfaceVariant;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : theme.appTheme.fastDuration,
            curve: theme.appTheme.standardCurve,
            constraints: BoxConstraints(
              minWidth: 64,
              minHeight: context.interactionPolicy.minimumControlExtent.clamp(
                40.0,
                48.0,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected
                  ? (light
                        ? colors.surfaceContainerLowest
                        : colors.surfaceContainerHighest)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: selected && light
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: selected && icon == Icons.favorite_rounded
                        ? colors.primary
                        : foreground,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: l10n.localGallery_scopeLabel,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: controlSurfaceColor(colors),
          borderRadius: BorderRadius.circular(radius + 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              key: const ValueKey('local-gallery-scope-all'),
              selected: !favorites,
              label: l10n.localGallery_scopeAll,
              onTap: onShowAll,
            ),
            segment(
              key: const ValueKey('local-gallery-scope-favorites'),
              selected: favorites,
              label: l10n.common_favorite,
              icon: favorites
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              onTap: onShowFavorites,
            ),
          ],
        ),
      ),
    );
  }
}

/// 可清除的筛选条件：未设置时显示条件名，设置后显示当前取值并附清除按钮。
class GalleryFilterChipButton extends StatelessWidget {
  const GalleryFilterChipButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
    this.onClear,
    this.clearTooltip,
    this.clearKey,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback? onClear;
  final String? clearTooltip;
  final Key? clearKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(theme.appTheme.controlRadius + 3);
    final background = active
        ? colors.primaryContainer
        : controlSurfaceColor(colors);
    final foreground = active
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    final extent = context.interactionPolicy.minimumControlExtent.clamp(
      44.0,
      48.0,
    );
    return Material(
      color: background,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: extent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onPressed,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: extent),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 12,
                    end: onClear == null ? 14 : 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (onClear != null)
              IconButton(
                key: clearKey,
                tooltip: clearTooltip,
                onPressed: onClear,
                constraints: BoxConstraints.tightFor(
                  width: extent,
                  height: extent,
                ),
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close_rounded, size: 18, color: foreground),
              ),
          ],
        ),
      ),
    );
  }
}
