import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import '../../../prompt_assistant/widgets/prompt_assistant_overlay.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/core/input_surface_style.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/autocomplete/autocomplete.dart';
import '../../../widgets/prompt/unified/unified_prompt_config.dart';
import '../../../widgets/prompt/unified/unified_prompt_input.dart';
import 'prompt_group_controller.dart';
import 'prompt_input_controller.dart';
import 'prompt_input_models.dart';

class PromptGroupEditor extends ConsumerWidget {
  const PromptGroupEditor({
    super.key,
    required this.controller,
    required this.commands,
    required this.viewData,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final PromptInputViewData viewData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final negative = controller.isNegativeMode;
    final groups = controller.groupsFor(negative);
    final sections = groups.sections;
    final list = ReorderableListView.builder(
      key: ValueKey(
        negative
            ? 'generation_negative_prompt_groups'
            : 'generation_positive_prompt_groups',
      ),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: sections.length,
      onReorder: (oldIndex, newIndex) {
        FocusManager.instance.primaryFocus?.unfocus();
        groups.reorder(oldIndex, newIndex);
        _commit(negative);
      },
      proxyDecorator: (child, _, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Material(
          color: Colors.transparent,
          elevation: 8 * animation.value,
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
        child: child,
      ),
      itemBuilder: (context, index) => Padding(
        key: ValueKey('prompt_group_${sections[index].id}'),
        padding: const EdgeInsets.only(bottom: 8),
        child: _PromptGroupCard(
          section: sections[index],
          index: index,
          negative: negative,
          viewData: viewData,
          onChanged: () => _commit(negative),
          onEnabledChanged: (enabled) {
            groups.setEnabled(sections[index].id, enabled);
            _commit(negative);
          },
          onToggleCollapsed: () => groups.toggleCollapsed(sections[index].id),
          onDelete: () => _delete(context, groups, sections[index], negative),
          onOpenAssistantSettings: commands.openAssistantSettings,
          onComfyuiImport: negative ? null : commands.importComfyuiPrompt,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        if (bounded) {
          return list;
        }
        return ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: sections.length,
          onReorder: (oldIndex, newIndex) {
            groups.reorder(oldIndex, newIndex);
            _commit(negative);
          },
          itemBuilder: (context, index) => Padding(
            key: ValueKey('prompt_group_unbounded_${sections[index].id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _PromptGroupCard(
              section: sections[index],
              index: index,
              negative: negative,
              viewData: viewData,
              onChanged: () => _commit(negative),
              onEnabledChanged: (enabled) {
                groups.setEnabled(sections[index].id, enabled);
                _commit(negative);
              },
              onToggleCollapsed: () =>
                  groups.toggleCollapsed(sections[index].id),
              onDelete: () =>
                  _delete(context, groups, sections[index], negative),
              onOpenAssistantSettings: commands.openAssistantSettings,
              onComfyuiImport: negative ? null : commands.importComfyuiPrompt,
            ),
          ),
        );
      },
    );
  }

  void _commit(bool negative) {
    final prompt = controller.commitGroupedPrompt(negative: negative);
    if (negative) {
      commands.updateNegativePrompt(prompt);
    } else {
      commands.updatePrompt(prompt);
    }
  }

  Future<void> _delete(
    BuildContext context,
    PromptGroupCollection groups,
    PromptGroupSection section,
    bool negative,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.prompt_deleteGroup),
        content: Text(context.l10n.prompt_deleteGroupConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    groups.remove(section.id);
    _commit(negative);
  }
}

class _PromptGroupCard extends ConsumerWidget {
  const _PromptGroupCard({
    required this.section,
    required this.index,
    required this.negative,
    required this.viewData,
    required this.onChanged,
    required this.onEnabledChanged,
    required this.onToggleCollapsed,
    required this.onDelete,
    required this.onOpenAssistantSettings,
    required this.onComfyuiImport,
  });

  final PromptGroupSection section;
  final int index;
  final bool negative;
  final PromptInputViewData viewData;
  final VoidCallback onChanged;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onDelete;
  final VoidCallback onOpenAssistantSettings;
  final PromptImportCallback? onComfyuiImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final enableAutocomplete = ref.watch(autocompleteSettingsProvider);
    final enableHighlight = ref.watch(highlightEmphasisSettingsProvider);
    final enableAutoFormat = ref.watch(autoFormatPromptSettingsProvider);
    final enableSdSyntaxAutoConvert = ref.watch(
      sdSyntaxAutoConvertSettingsProvider,
    );
    final modeSessionId = negative
        ? PromptHistorySessionIds.generationNegative
        : PromptHistorySessionIds.generationPrompt;
    final historySessionId = '${modeSessionId}_group_${section.id}';
    final summaryParts = section.controller.text
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final summary = summaryParts.isEmpty
        ? context.l10n.prompt_emptyGroup
        : summaryParts.first;
    final remainingSummaryCount = summaryParts.length - 1;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: section.enabled ? 1 : 0.58,
      child: Material(
        color: sectionSurfaceColor(colors),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Checkbox(
                  key: ValueKey('prompt_group_enabled_${section.id}'),
                  value: section.enabled,
                  onChanged: (value) => onEnabledChanged(value ?? false),
                ),
                Tooltip(
                  message: context.l10n.prompt_reorderGroup,
                  child: ReorderableDragStartListener(
                    index: index,
                    child: const SizedBox.square(
                      dimension: 48,
                      child: Icon(Icons.drag_indicator_rounded, size: 22),
                    ),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          summary,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                      if (remainingSummaryCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '+$remainingSummaryCount',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                PromptAssistantOverlay(
                  key: ValueKey('prompt_group_assistant_${section.id}'),
                  placement: PromptAssistantPlacement.inline,
                  expandInPlace: false,
                  iconOnly: true,
                  compactDesktopToolbar: true,
                  supportsTagMode: true,
                  tagModeSessionId: modeSessionId,
                  sessionId: historySessionId,
                  controller: section.controller,
                  onChanged: (_) => onChanged(),
                  onOpenSettings: onOpenAssistantSettings,
                ),
                PopupMenuButton<String>(
                  key: ValueKey('prompt_group_menu_${section.id}'),
                  tooltip: context.l10n.common_moreActions,
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            color: colors.error,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.l10n.common_delete,
                            style: TextStyle(color: colors.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  key: ValueKey('prompt_group_collapse_${section.id}'),
                  tooltip: section.collapsed
                      ? context.l10n.prompt_expandGroup
                      : context.l10n.prompt_collapseGroup,
                  onPressed: onToggleCollapsed,
                  icon: Icon(
                    section.collapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                  ),
                ),
              ],
            ),
            if (!section.collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  height: viewData.isMaximized
                      ? (MediaQuery.sizeOf(context).height * 0.42).clamp(
                          220.0,
                          460.0,
                        )
                      : null,
                  child: UnifiedPromptInput(
                    key: ValueKey('prompt_group_input_${section.id}'),
                    controller: section.controller,
                    focusNode: section.focusNode,
                    sessionId: historySessionId,
                    tagModeSessionId: modeSessionId,
                    surfaceColor: inputSurfaceFillColor(colors),
                    config: UnifiedPromptConfig(
                      enableSyntaxHighlight: enableHighlight,
                      numericEmphasisEnabled: viewData.numericEmphasisEnabled,
                      enableAutocomplete: enableAutocomplete,
                      enableAutoFormat: enableAutoFormat,
                      enableSdSyntaxAutoConvert: enableSdSyntaxAutoConvert,
                      enableComfyuiImport: !negative,
                      enableTagMode: true,
                      autocompleteConfig: AutocompleteConfig(
                        showTranslation: true,
                        showCategory: !negative,
                        showCount: !negative,
                        autoInsertComma: true,
                      ),
                      hintText: context.l10n.prompt_groupHint,
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(12),
                    ),
                    minLines: viewData.isMaximized ? null : 4,
                    maxLines: null,
                    expands: viewData.isMaximized,
                    fitContent: !viewData.isMaximized,
                    enableAssistant: false,
                    showTagModeSwitch: false,
                    onOpenAssistantSettings: onOpenAssistantSettings,
                    onComfyuiImport: onComfyuiImport,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
