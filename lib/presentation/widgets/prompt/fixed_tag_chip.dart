import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/prompt_semantic_colors.dart';

/// One fixed tag in the management grid: the name only.
///
/// Tapping toggles whether the tag is applied; everything else (content,
/// position, links, edit, delete) lives in the details opened by long-press on
/// touch or right-click with a mouse.
class FixedTagChip extends StatefulWidget {
  const FixedTagChip({
    super.key,
    required this.entry,
    required this.onToggle,
    required this.onShowDetails,
    this.linkCount = 0,
    this.maxLines = 2,
  });

  final FixedTagEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onShowDetails;

  /// Linked tags switch together, so the chip marks that a tap affects more.
  final int linkCount;
  final int maxLines;

  @override
  State<FixedTagChip> createState() => _FixedTagChipState();
}

class _FixedTagChipState extends State<FixedTagChip> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = widget.entry;
    final accent = entry.promptType == FixedTagPromptType.positive
        ? theme.promptSemanticColors.positiveFixedTag
        : theme.promptSemanticColors.negativeFixedTag;
    final resting = controlSurfaceColor(colors);
    final base = entry.enabled
        ? Color.alphaBlend(accent.withValues(alpha: 0.22), resting)
        : resting;
    final background = _hovering
        ? Color.alphaBlend(accent.withValues(alpha: 0.08), base)
        : base;
    final radius = BorderRadius.circular(12);
    return Semantics(
      selected: entry.enabled,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: ValueKey('fixed-tag-entry-${entry.id}'),
          borderRadius: radius,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: accent.withValues(alpha: 0.14),
          onTap: widget.onToggle,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            widget.onShowDetails();
          },
          onSecondaryTapUp: (_) => widget.onShowDetails(),
          onHover: context.interactionPolicy.precisePointerAvailable
              ? (value) => setState(() => _hovering = value)
              : null,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Ink(
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: Border.all(
                color: _focused ? colors.primary : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: Row(
              children: [
                if (entry.enabled) ...[
                  Icon(Icons.check_circle_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    entry.displayName,
                    maxLines: widget.maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.25,
                      fontWeight: entry.enabled
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: entry.enabled
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.linkCount > 0) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.link_rounded,
                    key: ValueKey('fixed-tag-link-mark-${entry.id}'),
                    size: 14,
                    color: colors.outline,
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
