import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import 'prompt_group_controller.dart';
import 'prompt_input_controller.dart';
import 'prompt_input_models.dart';

class PromptEditorModeSwitch extends StatelessWidget {
  const PromptEditorModeSwitch({
    super.key,
    required this.controller,
    required this.commands,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;

  @override
  Widget build(BuildContext context) => SegmentedButton<PromptEditorMode>(
    key: const ValueKey('generation_prompt_editor_mode_switch'),
    showSelectedIcon: false,
    expandedInsets: EdgeInsets.zero,
    style: const ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, 48)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      visualDensity: VisualDensity.compact,
    ),
    segments: [
      ButtonSegment(
        value: PromptEditorMode.single,
        label: Text(
          context.l10n.prompt_singleEditorMode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      ButtonSegment(
        value: PromptEditorMode.grouped,
        label: Text(
          context.l10n.prompt_groupedEditorMode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
    selected: {controller.editorMode},
    onSelectionChanged: (selection) {
      if (selection.isNotEmpty) commands.setEditorMode(selection.first);
    },
  );
}
