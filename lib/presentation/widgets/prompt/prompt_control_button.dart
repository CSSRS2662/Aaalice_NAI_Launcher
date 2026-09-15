import 'package:flutter/material.dart';

import '../../adaptive/interaction_policy.dart';
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
