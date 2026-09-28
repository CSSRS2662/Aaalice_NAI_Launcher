import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/theme_extension.dart';

/// 图库类页面的快捷筛选行：横向滚动，控件之间统一间距。
class GalleryScopeRow extends StatelessWidget {
  const GalleryScopeRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// 全部 / 收藏两段切换，与生成页页签栏同一套控件语言。
class GalleryScopeToggle extends StatelessWidget {
  const GalleryScopeToggle({
    super.key,
    required this.favorites,
    required this.onShowAll,
    required this.onShowFavorites,
    required this.allKey,
    required this.favoritesKey,
  });

  final bool favorites;
  final VoidCallback onShowAll;
  final VoidCallback onShowFavorites;
  final Key allKey;
  final Key favoritesKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = theme.appTheme.controlRadius;
    final light = colors.brightness == Brightness.light;
    // 整条与筛选条件同高（触屏 48，指针 44），单段命中区不小于 40 / 44。
    final extent = context.interactionPolicy.minimumControlExtent.clamp(
      44.0,
      48.0,
    );
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
            constraints: BoxConstraints(minWidth: 64, minHeight: extent - 4),
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
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: controlSurfaceColor(colors),
          borderRadius: BorderRadius.circular(radius + 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              key: allKey,
              selected: !favorites,
              label: l10n.localGallery_scopeAll,
              onTap: onShowAll,
            ),
            segment(
              key: favoritesKey,
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
    this.trailingIcon,
    this.labelWidget,
  });

  final IconData icon;
  final String label;

  /// 需要异步译名等自定义呈现时代替 [label] 显示，沿用同一套文字样式。
  final Widget? labelWidget;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback? onClear;
  final String? clearTooltip;
  final Key? clearKey;

  /// 打开选项菜单的条件在标签后显示下拉箭头。
  final IconData? trailingIcon;

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
                    end: onClear == null ? (trailingIcon == null ? 14 : 8) : 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: DefaultTextStyle.merge(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w600,
                          ),
                          child: labelWidget ?? Text(label),
                        ),
                      ),
                      if (trailingIcon != null && onClear == null) ...[
                        const SizedBox(width: 2),
                        Icon(trailingIcon, size: 18, color: foreground),
                      ],
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

@immutable
class GalleryFilterOption<T> {
  const GalleryFilterOption({
    required this.value,
    required this.label,
    this.icon,
    this.key,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Key? key;
}

/// 单选条件：点击展开选项菜单；[clearValue] 不为 null 时，选中其他值后显示清除按钮。
class GalleryFilterMenuChip<T> extends StatelessWidget {
  const GalleryFilterMenuChip({
    super.key,
    required this.icon,
    required this.placeholder,
    required this.value,
    required this.options,
    required this.onSelected,
    this.clearValue,
    this.clearKey,
    this.chipKey,
    this.selectedIcon = Icons.check_rounded,
  });

  final IconData icon;

  /// 当前值等于 [clearValue]（未筛选）时显示的条件名。
  final String placeholder;
  final T value;
  final List<GalleryFilterOption<T>> options;
  final ValueChanged<T> onSelected;
  final T? clearValue;
  final Key? clearKey;
  final Key? chipKey;

  /// 当前选项的尾部图标，例如排序方向。
  final IconData selectedIcon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final clearable = clearValue != null || null is T;
    final active = clearable && value != clearValue;
    final current = options.where((option) => option.value == value);
    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            key: option.key,
            leadingIcon: option.icon == null ? null : Icon(option.icon),
            trailingIcon: option.value == value
                ? Icon(selectedIcon, color: colors.primary)
                : null,
            onPressed: () => onSelected(option.value),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => GalleryFilterChipButton(
        key: chipKey,
        clearKey: clearKey,
        icon: icon,
        label: active || !clearable
            ? (current.isEmpty ? placeholder : current.first.label)
            : placeholder,
        active: active,
        trailingIcon: Icons.arrow_drop_down_rounded,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        onClear: active ? () => onSelected(clearValue as T) : null,
        clearTooltip: context.l10n.common_clear,
      ),
    );
  }
}
