import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../common/app_toast.dart';
import '../common/horizontal_segmented_control.dart';
import '../common/translated_tag_text.dart';
import 'fixed_tags_dialog_models.dart';

/// Shows everything about one fixed tag except the on/off state, which the
/// grid toggles directly.
Future<void> showFixedTagDetails({
  required BuildContext context,
  required FixedTagEntry entry,
  required FixedTagsDialogCommands commands,
}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    titleBuilder: (context) =>
        Text(entry.displayName, style: Theme.of(context).textTheme.titleLarge),
    dialogWidth: 440,
    builder: (_, scrollController) => FixedTagDetailsBody(
      entryId: entry.id,
      commands: commands,
      scrollController: scrollController,
    ),
  );
}

class FixedTagDetailsBody extends ConsumerWidget {
  const FixedTagDetailsBody({
    super.key,
    required this.entryId,
    required this.commands,
    this.scrollController,
  });

  final String entryId;
  final FixedTagsDialogCommands commands;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fixedTagsNotifierProvider);
    final entry = state.entries.where((item) => item.id == entryId).firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    final linked = entry.promptType == FixedTagPromptType.positive
        ? state.linkedNegativesOf(entry.id)
        : state.linkedPositivesOf(entry.id);

    // Actions that open another surface close the details first, so sheets
    // never stack on a phone.
    void closeThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return ContentSizedAdaptiveForm(
      key: const ValueKey('fixed-tag-details'),
      scrollController: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: [
        _DetailsMeta(entry: entry),
        const SizedBox(height: 12),
        _ContentPreview(entry: entry),
        const SizedBox(height: 16),
        _PositionSelector(
          entry: entry,
          onChanged: () => commands.togglePosition(entry),
        ),
        const SizedBox(height: 12),
        _LinksRow(
          linked: linked,
          onPressed: () => closeThen(() => commands.showLinkManager(entry)),
        ),
      ],
      footer: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('fixed-tag-details-delete'),
                onPressed: () => closeThen(() => commands.deleteEntry(entry)),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(context.l10n.common_delete),
              ),
              TextButton.icon(
                key: const ValueKey('fixed-tag-details-copy'),
                // Secondary action: neutral, so only delete reads as a risk.
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: entry.content.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: entry.content),
                        );
                        if (context.mounted) {
                          AppToast.success(context, context.l10n.common_copied);
                        }
                      },
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: Text(context.l10n.common_copy),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('fixed-tag-details-edit'),
                onPressed: () => closeThen(
                  () => commands.editEntry(entry, entry.promptType),
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.l10n.common_edit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsMeta extends StatelessWidget {
  const _DetailsMeta({required this.entry});

  final FixedTagEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scope = entry.promptType == FixedTagPromptType.positive
        ? context.l10n.fixedTags_positiveTitle
        : context.l10n.fixedTags_negativeTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$scope · ${context.l10n.fixedTags_weight} '
          '${entry.weight.toStringAsFixed(2)}',
          style: style,
        ),
        if (entry.sourceEntryId != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.sync_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  context.l10n.fixedTags_linkedFromLibrary,
                  style: style,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ContentPreview extends StatelessWidget {
  const _ContentPreview({required this.entry});

  final FixedTagEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('fixed-tag-details-content'),
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: entry.content.isEmpty
              ? Text(
                  context.l10n.common_emptyValue,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              : TranslatedPromptText(
                  entry.content,
                  originalText: entry.content.replaceAll('\n', ' '),
                  selectable: false,
                  maxLines: 12,
                  style: theme.textTheme.bodyMedium,
                ),
        ),
      ),
    );
  }
}

class _PositionSelector extends StatelessWidget {
  const _PositionSelector({required this.entry, required this.onChanged});

  final FixedTagEntry entry;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.fixedTags_position,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        HorizontalSegmentedControl(
          child: SegmentedButton<FixedTagPosition>(
            key: const ValueKey('fixed-tag-details-position'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: FixedTagPosition.prefix,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(context.l10n.fixedTags_prefix),
              ),
              ButtonSegment(
                value: FixedTagPosition.suffix,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: Text(context.l10n.fixedTags_suffix),
              ),
            ],
            selected: {entry.position},
            onSelectionChanged: (selection) {
              if (selection.first != entry.position) onChanged();
            },
          ),
        ),
      ],
    );
  }
}

class _LinksRow extends StatelessWidget {
  const _LinksRow({required this.linked, required this.onPressed});

  final List<FixedTagEntry> linked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: controlSurfaceColor(theme.colorScheme),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('fixed-tag-details-links'),
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.link_rounded,
                  size: 20,
                  color: linked.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.fixedTags_manageLinks,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        linked.isEmpty
                            ? context.l10n.fixedTags_linkCount(0)
                            : context.l10n.fixedTags_linkedToNames(
                                linked
                                    .map((item) => item.displayName)
                                    .join(', '),
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
