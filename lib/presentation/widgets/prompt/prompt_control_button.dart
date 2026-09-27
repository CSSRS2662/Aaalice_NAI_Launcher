import 'package:flutter/material.dart';

import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/prompt_control_colors.dart';
import '../../themes/theme_extension.dart';

/// Common interaction and tonal states for prompt tabs and source selectors.
/// The caller owns the action and content; keyboard, focus and touch feedback
/// use the same Material button behavior across all five entry points.
class PromptControlButton extends StatefulWidget {
  const PromptControlButton({
    super.key,
    required this.color,
    required this.active,
    required this.onPressed,
    required this.builder,
    required this.padding,
    this.onLongPress,
    this.selected,
  });

  final Color color;
  final bool active;
  final bool? selected;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final Widget Function(PromptControlColors colors) builder;

  @override
  State<PromptControlButton> createState() => _PromptControlButtonState();
}

class _PromptControlButtonState extends State<PromptControlButton> {
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    _states.addListener(_stateChanged);
  }

  void _stateChanged() => setState(() {});

  @override
  void dispose() {
    _states.removeListener(_stateChanged);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final states = _states.value;
    final interaction = context.interactionPolicy;
    final tokens = Theme.of(context).appTheme;
    final colors = PromptControlColors(
      Theme.of(context),
      widget.color,
      active: widget.active,
      hovered: interaction.isControlHighlighted(states),
    );
    final extent = context.interactionPolicy.minimumControlExtent.clamp(
      44.0,
      double.infinity,
    );
    return Semantics(
      selected: widget.selected,
      child: TextButton(
        statesController: _states,
        onPressed: widget.onPressed,
        onLongPress: widget.onLongPress,
        style: TextButton.styleFrom(
          minimumSize: Size.square(extent),
          padding: widget.padding,
          backgroundColor: colors.background,
          foregroundColor: colors.foreground,
          overlayColor: Colors.transparent,
          animationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : tokens.fastDuration,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
          ),
          side: interaction.isFocusVisible(states)
              ? BorderSide(color: colors.accent)
              : BorderSide.none,
        ),
        child: widget.builder(colors),
      ),
    );
  }
}

/// 移动端提示词页的“角色 / 固定词 / 质量词”按钮组。
///
/// 几个入口共用一块控件色面，分段之间只用短分隔线区分，不再各自铺色块、
/// 叠计数胶囊；状态由分段自身的图标颜色与数字表达。
class PromptRoleSegmentGroup extends StatelessWidget {
  const PromptRoleSegmentGroup({
    super.key,
    required this.children,
    this.height = 48,
  });

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final divider = SizedBox(
      width: 1,
      height: height * 0.4,
      child: ColoredBox(color: colors.outlineVariant),
    );
    return Material(
      key: const ValueKey('prompt-role-segment-group'),
      color: controlSurfaceColor(colors),
      borderRadius: BorderRadius.circular(theme.appTheme.controlRadius + 2),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) divider,
              Expanded(child: children[i]),
            ],
          ],
        ),
      ),
    );
  }
}

/// [PromptRoleSegmentGroup] 中的一个分段：无独立底色与描边，启用时图标取
/// 强调色；[count] 为 null 时只显示图标（开关类入口）。
class PromptRoleSegment extends StatelessWidget {
  const PromptRoleSegment({
    super.key,
    required this.icon,
    required this.active,
    required this.onPressed,
    required this.semanticLabel,
    this.onLongPress,
    this.count,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final String semanticLabel;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = this.count;
    return Semantics(
      button: true,
      toggled: count == null ? active : null,
      label: semanticLabel,
      value: count?.toString(),
      onTap: onPressed,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        onLongPress: onLongPress,
        child: SizedBox.expand(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: active ? colors.primary : colors.onSurfaceVariant,
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    count > 99 ? '99+' : '$count',
                    maxLines: 1,
                    style: (theme.textTheme.labelLarge ?? const TextStyle())
                        .copyWith(
                          color: active
                              ? colors.onSurface
                              : colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
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

/// Compact numeric status shared by the mobile prompt role controls.
class PromptControlCountBadge extends StatelessWidget {
  const PromptControlCountBadge({
    super.key,
    required this.count,
    required this.foregroundColor,
    this.active = false,
  });

  final int count;
  final Color foregroundColor;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: foregroundColor.withValues(alpha: active ? 0.12 : 0.07),
      borderRadius: BorderRadius.circular(999),
    ),
    alignment: Alignment.center,
    child: Text(
      '$count',
      maxLines: 1,
      style: TextStyle(
        color: foregroundColor,
        fontSize: 10,
        height: 1.15,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}
