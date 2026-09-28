import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/resources/agent_chat_resource_reference.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../data/models/tag_library/tag_library_entry.dart';
import '../../adaptive/interaction_policy.dart';
import '../../agent_chat/widgets/agent_resource_drop_region.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/grid_columns_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../common/grid_column_count.dart';
import '../common/themed_input.dart';
import '../tag_library/tag_library_entry_hover_preview.dart';
import 'fixed_tag_chip.dart';
import 'fixed_tags_dialog_controller.dart';
import 'fixed_tags_dialog_models.dart';

const fixedTagColumnGap = 28.0;
const _gridSpacing = 8.0;
const _gridPadding = 12.0;

enum _AddAction { create, library }

class FixedTagsColumns extends ConsumerWidget {
  const FixedTagsColumns({
    super.key,
    required this.data,
    required this.commands,
    required this.controller,
    required this.isCompact,
  });

  final FixedTagsDialogViewData data;
  final FixedTagsDialogCommands commands;
  final FixedTagsDialogController controller;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = ref.watch(
      gridColumnsProvider(GridColumnsSurface.fixedTags),
    );
    void cycleColumns() => ref
        .read(gridColumnsProvider(GridColumnsSurface.fixedTags).notifier)
        .cycle();
    FixedTagColumnConfig configFor(FixedTagPromptType promptType) =>
        _configFor(context, promptType, columns, cycleColumns);

    if (isCompact) {
      final promptType = controller.mobilePromptType;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
            child: Row(
              children: [
                for (final type in FixedTagPromptType.values) ...[
                  if (type == FixedTagPromptType.negative)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _PromptTypeTab(
                      promptType: type,
                      selected: promptType == type,
                      count: type == FixedTagPromptType.positive
                          ? data.state.positiveEntries.length
                          : data.state.negativeEntries.length,
                      onTap: () => controller.selectMobilePromptType(type),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: FixedTagColumn(config: configFor(promptType))),
        ],
      );
    }
    if (!data.state.negativePanelExpanded) {
      return FixedTagColumn(config: configFor(FixedTagPromptType.positive));
    }
    return Row(
      children: [
        Expanded(
          child: FixedTagColumn(config: configFor(FixedTagPromptType.positive)),
        ),
        VerticalDivider(
          key: const ValueKey('fixed-tags-column-divider'),
          width: fixedTagColumnGap,
          thickness: 1,
          indent: 12,
          endIndent: 12,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
        Expanded(
          child: FixedTagColumn(config: configFor(FixedTagPromptType.negative)),
        ),
      ],
    );
  }

  FixedTagColumnConfig _configFor(
    BuildContext context,
    FixedTagPromptType promptType,
    int columns,
    VoidCallback cycleColumns,
  ) {
    return FixedTagColumnConfig(
      title: promptType == FixedTagPromptType.positive
          ? context.l10n.fixedTags_positiveTitle
          : context.l10n.fixedTags_negativeTitle,
      promptType: promptType,
      entries: data.entriesFor(
        promptType,
        controller.searchQueryFor(promptType),
        enabledOnly: controller.enabledOnly,
      ),
      allEntries: promptType == FixedTagPromptType.positive
          ? data.state.positiveEntries
          : data.state.negativeEntries,
      libraryEntries: data.libraryEntries,
      searchController: controller.searchControllerFor(promptType),
      searchQuery: controller.searchQueryFor(promptType),
      scrollController: controller.listControllerFor(promptType),
      controller: controller,
      commands: commands,
      data: data,
      compact: isCompact,
      columns: columns,
      onCycleColumns: cycleColumns,
    );
  }
}

@immutable
class FixedTagColumnConfig {
  const FixedTagColumnConfig({
    required this.title,
    required this.promptType,
    required this.entries,
    required this.allEntries,
    required this.libraryEntries,
    required this.searchController,
    required this.searchQuery,
    required this.scrollController,
    required this.controller,
    required this.commands,
    required this.data,
    required this.compact,
    required this.columns,
    required this.onCycleColumns,
  });

  final String title;
  final FixedTagPromptType promptType;
  final List<FixedTagEntry> entries;
  final List<FixedTagEntry> allEntries;
  final List<TagLibraryEntry> libraryEntries;
  final TextEditingController searchController;
  final String searchQuery;
  final ScrollController scrollController;
  final FixedTagsDialogController controller;
  final FixedTagsDialogCommands commands;
  final FixedTagsDialogViewData data;
  final bool compact;
  final int columns;
  final VoidCallback onCycleColumns;

  bool get hasSearch => searchQuery.trim().isNotEmpty;
  bool get isFiltered => hasSearch || controller.enabledOnly;
  bool get reordering => controller.reordering;
  int get enabledCount => allEntries.where((entry) => entry.enabled).length;
}

class FixedTagColumn extends StatelessWidget {
  const FixedTagColumn({super.key, required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    final body = config.reordering
        ? _ReorderList(config: config)
        : _EntryGrid(config: config);
    if (config.compact) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: config.reordering
                ? _ReorderBanner(config: config)
                : _CompactToolbar(config: config),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Column(
      children: [
        _ColumnHeader(config: config),
        if (!config.reordering)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _SearchField(config: config),
          ),
        Expanded(child: body),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controlExtent = context.interactionPolicy.minimumControlExtent;
    final totalText = config.isFiltered
        ? context.l10n.fixedTags_columnFilteredCount(
            config.enabledCount,
            config.allEntries.length,
            config.entries.length,
          )
        : context.l10n.fixedTags_columnCount(
            config.enabledCount,
            config.allEntries.length,
          );
    final enableAll = config.enabledCount != config.allEntries.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${config.title} · $totalText',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _ColumnActionButton(
            icon: Icons.add_rounded,
            label: context.l10n.fixedTags_new,
            tooltip: context.l10n.fixedTags_newTarget(config.title),
            onPressed: () => config.commands.editEntry(null, config.promptType),
          ),
          const SizedBox(width: 4),
          _ColumnActionButton(
            icon: Icons.playlist_add_rounded,
            label: context.l10n.fixedTags_library,
            tooltip: context.l10n.fixedTags_addFromLibraryToTarget(
              config.title,
            ),
            onPressed: () => config.commands.pickFromLibrary(config.promptType),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: ValueKey('fixed-tags-toggle-all-${config.promptType.name}'),
            onPressed: config.allEntries.isEmpty
                ? null
                : () => config.commands.setPromptTypeEnabled(
                    config.promptType,
                    enableAll,
                  ),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.standard,
              minimumSize: Size(0, controlExtent),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              enableAll
                  ? context.l10n.fixedTags_enableAll
                  : context.l10n.fixedTags_disableAll,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactToolbar extends StatelessWidget {
  const _CompactToolbar({required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SearchField(config: config)),
        const SizedBox(width: 4),
        GridColumnCountButton(
          key: const ValueKey('fixed-tags-columns-button'),
          columns: config.columns,
          onPressed: config.onCycleColumns,
        ),
        PopupMenuButton<_AddAction>(
          key: const ValueKey('fixed-tags-add-menu'),
          tooltip: context.l10n.fixedTags_addMenu,
          icon: const Icon(Icons.add_rounded),
          onSelected: (action) => switch (action) {
            _AddAction.create => config.commands.editEntry(
              null,
              config.promptType,
            ),
            _AddAction.library => config.commands.pickFromLibrary(
              config.promptType,
            ),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              key: const ValueKey('fixed-tags-add-new'),
              value: _AddAction.create,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_rounded),
                title: Text(context.l10n.fixedTags_newTarget(config.title)),
              ),
            ),
            PopupMenuItem(
              key: const ValueKey('fixed-tags-add-library'),
              value: _AddAction.library,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.playlist_add_rounded),
                title: Text(context.l10n.fixedTags_addFromLibrary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    return ThemedInput(
      key: ValueKey('fixed-tags-search-${config.promptType.name}'),
      controller: config.searchController,
      decoration: InputDecoration(
        hintText: context.l10n.fixedTags_searchTarget(config.title),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: config.hasSearch
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () =>
                    config.controller.clearSearch(config.promptType),
              )
            : null,
        isDense: true,
      ),
      onChanged: (value) =>
          config.controller.setSearchQuery(config.promptType, value),
    );
  }
}

class _ReorderBanner extends StatelessWidget {
  const _ReorderBanner({required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.swap_vert_rounded,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10n.fixedTags_reorderHint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          key: const ValueKey('fixed-tags-reorder-done'),
          onPressed: () => config.controller.setReordering(false),
          child: Text(context.l10n.fixedTags_reorderDone),
        ),
      ],
    );
  }
}

class _EntryGrid extends StatelessWidget {
  const _EntryGrid({required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = context.interactionPolicy;
    final linkCounts = _linkCounts(config.data.state);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final textScale = textScaler.scale(14) / 14;
        final width = math.max(0.0, constraints.maxWidth - _gridPadding * 2);
        final columns = GridColumnCount.resolve(
          width: width,
          preferred: config.columns,
          spacing: _gridSpacing,
          minCellWidth: 92 * textScale.clamp(1.0, 3.0),
        );
        final maxLines = columns == 1 ? 1 : 2;
        final lineHeight =
            textScaler.scale(theme.textTheme.bodyMedium?.fontSize ?? 14) * 1.25;
        final extent = math.max(
          policy.minimumControlExtent,
          maxLines * lineHeight + 16,
        );
        return CustomScrollView(
          key: ValueKey('fixed-tags-grid-${config.promptType.name}'),
          controller: config.scrollController,
          slivers: [
            if (config.entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      config.isFiltered
                          ? context.l10n.fixedTags_noMatching
                          : context.l10n.fixedTags_emptyTarget(config.title),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  _gridPadding,
                  4,
                  _gridPadding,
                  8,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: extent,
                    mainAxisSpacing: _gridSpacing,
                    crossAxisSpacing: _gridSpacing,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _gridItem(
                      context,
                      config.entries[index],
                      linkCounts[config.entries[index].id] ?? 0,
                      maxLines,
                    ),
                    childCount: config.entries.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    policy.touchAvailable
                        ? context.l10n.fixedTags_gridHintTouch
                        : context.l10n.fixedTags_gridHintPointer,
                    key: const ValueKey('fixed-tags-grid-hint'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _gridItem(
    BuildContext context,
    FixedTagEntry entry,
    int linkCount,
    int maxLines,
  ) {
    final chip = FixedTagChip(
      entry: entry,
      linkCount: linkCount,
      maxLines: maxLines,
      onToggle: () => config.commands.toggleEntry(entry),
      onShowDetails: () => config.commands.showDetails(entry),
    );
    if (!context.interactionPolicy.precisePointerAvailable) {
      return KeyedSubtree(key: ValueKey(entry.id), child: chip);
    }
    final libraryEntry = resolveFixedTagLibraryEntry(
      entry,
      config.libraryEntries,
    );
    return AgentResourceDragSource(
      key: ValueKey(entry.id),
      reference: AgentChatResourceReference(
        kind: AgentChatResourceKind.fixedTag,
        source: 'fixed_tags',
        resourceId: entry.id,
        display: {'name': entry.name},
      ),
      child: libraryEntry == null
          ? chip
          : TagLibraryEntryHoverPreview(entry: libraryEntry, child: chip),
    );
  }

  static Map<String, int> _linkCounts(FixedTagsState state) {
    final counts = <String, int>{};
    for (final link in state.links) {
      counts.update(
        link.positiveEntryId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      counts.update(
        link.negativeEntryId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }
}

/// Order matters when tags are joined into the prompt, so reordering lists
/// every tag of the type regardless of search or the enabled-only filter.
class _ReorderList extends StatelessWidget {
  const _ReorderList({required this.config});
  final FixedTagColumnConfig config;

  @override
  Widget build(BuildContext context) {
    final entries = config.allEntries.sortedByOrder();
    return ReorderableListView.builder(
      key: ValueKey('fixed-tags-reorder-${config.promptType.name}'),
      scrollController: config.scrollController,
      padding: const EdgeInsets.fromLTRB(_gridPadding, 4, _gridPadding, 16),
      buildDefaultDragHandles: false,
      itemCount: entries.length,
      itemBuilder: (context, index) => _ReorderRow(
        key: ValueKey(entries[index].id),
        entry: entries[index],
        index: index,
      ),
      onReorderItem: (oldIndex, newIndex) =>
          config.commands.reorder(config.promptType, oldIndex, newIndex),
    );
  }
}

class _ReorderRow extends StatelessWidget {
  const _ReorderRow({super.key, required this.entry, required this.index});

  final FixedTagEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extent = context.interactionPolicy.minimumControlExtent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: Material(
          color: controlSurfaceColor(theme.colorScheme),
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: extent),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: entry.enabled
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  key: ValueKey('fixed-tags-reorder-handle-${entry.id}'),
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: SizedBox.square(
                      dimension: extent,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptTypeTab extends StatelessWidget {
  const _PromptTypeTab({
    required this.promptType,
    required this.selected,
    required this.count,
    required this.onTap,
  });
  final FixedTagPromptType promptType;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = promptType == FixedTagPromptType.positive;
    final color = positive
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;
    return Material(
      key: ValueKey('fixed-tags-mobile-tab-${promptType.name}'),
      color: selected
          ? color.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                positive ? Icons.auto_awesome_rounded : Icons.block_rounded,
                size: 16,
                color: selected ? color : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  positive
                      ? context.l10n.fixedTags_positiveTitle
                      : context.l10n.fixedTags_negativeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? color
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(count.toString(), style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColumnActionButton extends StatelessWidget {
  const _ColumnActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}
