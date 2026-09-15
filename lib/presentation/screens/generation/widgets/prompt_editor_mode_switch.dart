import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../themes/theme_extension.dart';
import 'prompt_group_controller.dart';
import 'prompt_input_controller.dart';
import 'prompt_input_models.dart';

class PromptEditorModeSwitch extends StatelessWidget {
  const PromptEditorModeSwitch({
    super.key,
    required this.controller,
    required this.commands,
    this.iconOnly = false,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final grouped = controller.isGroupedMode;
    final label = grouped
        ? context.l10n.prompt_groupedEditorMode
        : context.l10n.prompt_singleEditorMode;
    final nextMode = grouped
        ? PromptEditorMode.single
        : PromptEditorMode.grouped;
    final nextLabel = grouped
        ? context.l10n.prompt_singleEditorMode
        : context.l10n.prompt_groupedEditorMode;
    final icon = grouped ? Icons.view_agenda_rounded : Icons.subject_rounded;

    final button = Material(
      color: grouped
          ? colors.primaryContainer.withValues(alpha: 0.72)
          : colors.surfaceContainerHigh.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(
        Theme.of(context).appTheme.controlRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('generation_prompt_editor_mode_switch'),
        onTap: () => commands.setEditorMode(nextMode),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: iconOnly ? 48 : 0,
            minHeight: 48,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly ? 0 : 6,
              vertical: 6,
            ),
            child: iconOnly
                ? Icon(
                    icon,
                    size: 22,
                    color: grouped
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 19,
                        color: grouped
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: grouped
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: nextLabel,
      value: label,
      child: iconOnly ? Tooltip(message: nextLabel, child: button) : button,
    );
  }
}

class PromptAddGroupButton extends StatelessWidget {
  const PromptAddGroupButton({
    super.key,
    required this.controller,
    this.iconOnly = false,
  });

  final PromptInputController controller;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final button = Material(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(
        Theme.of(context).appTheme.controlRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey(
          controller.isNegativeMode
              ? 'add_negative_prompt_group'
              : 'add_positive_prompt_group',
        ),
        onTap: () {
          final group = controller.groupsFor(controller.isNegativeMode).add();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (group.focusNode.canRequestFocus) group.focusNode.requestFocus();
          });
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: iconOnly ? 48 : 0,
            minHeight: 48,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly ? 0 : 6,
              vertical: 6,
            ),
            child: iconOnly
                ? Icon(
                    Icons.playlist_add_rounded,
                    size: 22,
                    color: colors.onSurface,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 20,
                        color: colors.onSurface,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          context.l10n.prompt_addGroup,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (!iconOnly) return button;
    return Tooltip(message: context.l10n.prompt_addGroup, child: button);
  }
}

class PromptEditorModeControls extends StatelessWidget {
  const PromptEditorModeControls({
    super.key,
    required this.controller,
    required this.commands,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: PromptEditorModeSwitch(
          controller: controller,
          commands: commands,
        ),
      ),
      if (controller.isGroupedMode) ...[
        const SizedBox(width: 6),
        Expanded(child: PromptAddGroupButton(controller: controller)),
      ],
    ],
  );
}
