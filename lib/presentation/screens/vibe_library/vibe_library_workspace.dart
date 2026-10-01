import '../../widgets/common/image_card_batch_scope.dart';
import '../../utils/card_drop_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/library_sidebar_move_service.dart';
import '../../../core/constants/storage_keys.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../data/models/vibe/vibe_import_progress.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../providers/selection_mode_provider.dart';
import '../../providers/vibe_library_category_provider.dart';
import '../../providers/vibe_library_provider.dart';
import '../../widgets/bulk_action_bar.dart';
import '../../widgets/common/pagination_bar.dart';
import '../../widgets/gallery/gallery_state_views.dart';
import '../../widgets/gallery/gallery_album_tree_view.dart';
import '../../widgets/gallery/gallery_library_toolbar.dart';
import '../../widgets/gallery/gallery_scope_controls.dart';
import '../../widgets/gallery/library_masonry_grid.dart';
import '../../widgets/gallery/gallery_sidebar.dart';
import '../../widgets/gallery/gallery_sidebar_sort_control.dart';
import '../../providers/library_sidebar_sort_provider.dart';
import 'vibe_library_commands.dart';
import 'vibe_library_screen_controller.dart';
import 'widgets/category/vibe_category_tree_view.dart';
import 'widgets/vibe_library_content_view.dart';
import 'widgets/vibe_library_empty_view.dart';

class VibeLibraryWorkspace extends StatelessWidget {
  const VibeLibraryWorkspace({
    super.key,
    required this.libraryState,
    required this.categoryState,
    required this.selectionState,
    required this.currentModel,
    required this.controller,
    required this.onCommand,
  });

  final VibeLibraryState libraryState;
  final VibeLibraryCategoryState categoryState;
  final SelectionModeState selectionState;
  final String currentModel;
  final VibeLibraryScreenController controller;
  final Future<void> Function(VibeLibraryCommand) onCommand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final persistent = constraints.maxWidth >= 1000;
        final showCategories = controller.showCategoryPanel && persistent;

        final content = Stack(
          children: [
            GalleryCollectionWorkspace(
              sidebarWidthKey: StorageKeys.vibeLibrarySidebarWidth,
              toolbar: _Toolbar(
                libraryState: libraryState,
                categoryState: categoryState,
                selectionState: selectionState,
                currentModel: currentModel,
                controller: controller,
                showPageTitle: true,
                showCategoryPanel: showCategories,
                usePersistentCategories: persistent,
                onCommand: onCommand,
              ),
              sidebar: showCategories
                  ? _CategoryPanel(
                      libraryState: libraryState,
                      categoryState: categoryState,
                      onCommand: onCommand,
                    )
                  : null,
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = (constraints.maxWidth - 32).clamp(
                    0.0,
                    double.infinity,
                  );
                  final columns = libraryMasonryColumns(
                    gridWidth,
                    spacing: vibeLibraryGridSpacing,
                    textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
                  );
                  return _Body(
                    state: libraryState,
                    itemWidth:
                        (gridWidth - vibeLibraryGridSpacing * (columns - 1)) /
                        columns,
                    onCommand: onCommand,
                  );
                },
              ),
              footer:
                  !libraryState.isLoading &&
                      libraryState.filteredEntries.isNotEmpty &&
                      libraryState.totalPages > 0
                  ? LayoutBuilder(
                      builder: (context, constraints) => PaginationBar(
                        currentPage: libraryState.currentPage,
                        totalPages: libraryState.totalPages,
                        totalItems: libraryState.filteredCount,
                        itemsPerPage: libraryState.pageSize,
                        itemsPerPageOptions: const [20, 50, 100],
                        onPageChanged: (page) =>
                            onCommand(ChangePageCommand(page)),
                        onItemsPerPageChanged: (size) =>
                            onCommand(ChangePageSizeCommand(size)),
                        showItemsPerPage: true,
                        showTotalInfo: true,
                        compact: constraints.maxWidth < 680,
                        loading: libraryState.isLoading,
                        totalIcon: Icons.auto_awesome_outlined,
                        totalItemsLabel: context.l10n.vibeLibrary_totalCount(
                          libraryState.filteredCount.toString(),
                        ),
                        tonalCard: true,
                      ),
                    )
                  : null,
            ),
            if (controller.isDragging) const _DropOverlay(),
            if (controller.isImporting)
              _ImportOverlay(progress: controller.importProgress),
          ],
        );

        if (!PlatformCapabilities.current.supportsExternalFileDrop) {
          return content;
        }
        return DropRegion(
          formats: cardDropFormats,
          hitTestBehavior: HitTestBehavior.opaque,
          onDropOver: (event) {
            if (!event.session.allowedOperations.contains(DropOperation.copy) ||
                !const CardDropPolicy(
                  allowVibes: true,
                ).accepts(event.session.items)) {
              return DropOperation.none;
            }
            controller.setDragging(true);
            return DropOperation.copy;
          },
          onDropLeave: (_) => controller.setDragging(false),
          onPerformDrop: (event) async {
            controller.setDragging(false);
            await onCommand(PerformVibeDropCommand(event));
          },
          child: content,
        );
      },
    );
  }
}

class _CategoryPanel extends ConsumerStatefulWidget {
  const _CategoryPanel({
    required this.libraryState,
    required this.categoryState,
    required this.onCommand,
  });

  final VibeLibraryState libraryState;
  final VibeLibraryCategoryState categoryState;
  final Future<void> Function(VibeLibraryCommand) onCommand;

  @override
  ConsumerState<_CategoryPanel> createState() => _CategoryPanelState();
}

class _CategoryPanelState extends ConsumerState<_CategoryPanel> {
  bool _categoriesExpanded = true;

  @override
  Widget build(BuildContext context) {
    return GallerySidebarSurface(
      child: Column(
        children: [
          const SizedBox(height: GalleryCollectionChrome.navigationTopPadding),
          GalleryAllImagesItem(
            key: const ValueKey('vibe-library-all'),
            label: context.l10n.vibeLibrary_allVibes,
            icon: Icons.auto_awesome_outlined,
            selectedIcon: Icons.auto_awesome_rounded,
            count: widget.libraryState.entries.length,
            isSelected: widget.categoryState.selectedCategoryId == null,
            onTap: () => widget.onCommand(const SelectCategoryCommand(null)),
          ),
          GallerySidebarSectionHeader(
            toggleKey: const ValueKey('vibe-library-categories-toggle'),
            icon: Icons.category_outlined,
            title: context.l10n.vibeLibrary_categories,
            trailing: const GallerySidebarSortControl(
              section: LibrarySidebarSection.vibeCategories,
            ),
            isExpanded: _categoriesExpanded,
            onToggle: () =>
                setState(() => _categoriesExpanded = !_categoriesExpanded),
            onCreate: () => widget.onCommand(const CreateCategoryCommand()),
          ),
          if (_categoriesExpanded)
            Expanded(
              child: VibeCategoryTreeView(
                categories: widget.categoryState.categories,
                onCategoryMoveToSlot: (id, targetId, slot) => ref
                    .read(librarySidebarMoveServiceProvider)
                    .moveVibeCategory(id, targetId, slot),
                totalEntryCount: widget.libraryState.entries.length,
                favoriteCount: widget.libraryState.favoriteCount,
                categoryEntryCounts: widget.libraryState.categoryEntryCounts,
                includeAll: false,
                selectedCategoryId: widget.categoryState.selectedCategoryId,
                onCategorySelected: (id) =>
                    widget.onCommand(SelectCategoryCommand(id)),
                onCategoryRename: (id, name) =>
                    widget.onCommand(RenameCategoryCommand(id, name)),
                onCategoryDelete: (id) =>
                    widget.onCommand(DeleteCategoryCommand(id)),
                onCreateCategory: () =>
                    widget.onCommand(const CreateCategoryCommand()),
                onEntryDrop: (entry, categoryId) => widget.onCommand(
                  ClassifyVibeEntryCommand(entry.id, categoryId),
                ),
                onFavoriteDrop: (entry) =>
                    widget.onCommand(FavoriteVibeEntryCommand(entry.id)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.libraryState,
    required this.categoryState,
    required this.selectionState,
    required this.currentModel,
    required this.controller,
    required this.showPageTitle,
    required this.showCategoryPanel,
    required this.usePersistentCategories,
    required this.onCommand,
  });

  final VibeLibraryState libraryState;
  final VibeLibraryCategoryState categoryState;
  final SelectionModeState selectionState;
  final String currentModel;
  final VibeLibraryScreenController controller;
  final bool showPageTitle;
  final bool showCategoryPanel;
  final bool usePersistentCategories;
  final Future<void> Function(VibeLibraryCommand) onCommand;

  @override
  Widget build(BuildContext context) {
    if (selectionState.isActive) return _buildBulkBar(context);
    final l10n = context.l10n;
    final category = libraryState.favoritesOnly
        ? null
        : categoryState.selectedCategory;
    return GalleryLibraryToolbar(
      key: const Key('vibe-library-toolbar'),
      title: showPageTitle
          ? GalleryCollectionPageTitle(
              icon: Icons.auto_awesome_outlined,
              title: l10n.vibeLibrary_title,
            )
          : const SizedBox.shrink(),
      count: libraryState.isLoading
          ? null
          : GalleryLibraryCountBadge(
              label: libraryState.hasFilters
                  ? '${libraryState.filteredCount}/${libraryState.totalCount}'
                  : '${libraryState.totalCount}',
            ),
      search: GalleryLibrarySearchField(
        controller: controller.searchController,
        hintText: l10n.vibeLibrary_searchHint,
        onChanged: controller.searchChanged,
        onClear: controller.clearSearch,
        onSubmitted: controller.submitSearch,
      ),
      primaryAction: GestureDetector(
        onSecondaryTapUp: controller.isBusy
            ? null
            : (details) =>
                  onCommand(ShowImportMenuCommand(details.globalPosition)),
        child: GalleryLibrarySearchAction(
          key: const Key('vibe-library-import-button'),
          icon: Icons.file_download_outlined,
          label: l10n.common_import,
          // Right-click opens the import options only with a mouse; on
          // touch the tap itself shows them.
          tooltip: context.interactionPolicy.precisePointerAvailable
              ? l10n.vibeLibrary_importTooltip
              : l10n.vibeLibrary_importTooltipTouch,
          isLoading: controller.isPickingFile,
          onPressed: controller.isBusy
              ? null
              : () => _handleImportPressed(context),
        ),
      ),
      titleActions: [
        IconButton(
          key: const Key('vibe-library-select-action'),
          tooltip: l10n.vibeLibrary_enterSelectionMode,
          onPressed: () => onCommand(const EnterSelectionModeCommand()),
          icon: const Icon(Icons.checklist_rounded),
        ),
        _buildMoreMenu(context),
      ],
      filters: GalleryScopeRow(
        key: const Key('vibe-library-scope-bar'),
        children: [
          GalleryScopeToggle(
            favorites: libraryState.favoritesOnly,
            onShowAll: () => onCommand(const SelectCategoryCommand(null)),
            onShowFavorites: () =>
                onCommand(const SelectCategoryCommand('favorites')),
            allKey: const Key('vibe-library-scope-all'),
            favoritesKey: const Key('vibe-library-scope-favorites'),
          ),
          GalleryFilterChipButton(
            key: const Key('vibe-library-category-chip'),
            clearKey: const Key('vibe-library-category-clear'),
            icon: Icons.folder_outlined,
            label: category?.name ?? l10n.common_categories,
            active: category != null,
            onPressed: () => onCommand(
              usePersistentCategories
                  ? const ToggleCategoryPanelCommand()
                  : const ShowCategoryPanelCommand(),
            ),
            onClear: category == null
                ? null
                : () => onCommand(const SelectCategoryCommand(null)),
            clearTooltip: l10n.common_clear,
          ),
          GalleryFilterMenuChip<VibeLibrarySortOrder>(
            chipKey: const Key('vibe-library-sort-chip'),
            icon: Icons.sort_rounded,
            placeholder: l10n.vibeLibrary_sortTooltip,
            value: libraryState.sortOrder,
            selectedIcon: libraryState.sortDescending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            options: [
              for (final order in VibeLibrarySortOrder.values)
                GalleryFilterOption(
                  value: order,
                  label: switch (order) {
                    VibeLibrarySortOrder.createdAt =>
                      l10n.vibeSelectorSortCreated,
                    VibeLibrarySortOrder.lastUsed =>
                      l10n.vibeSelectorSortLastUsed,
                    VibeLibrarySortOrder.usedCount =>
                      l10n.vibeSelectorSortUsedCount,
                    VibeLibrarySortOrder.name => l10n.vibeSelectorSortName,
                  },
                ),
            ],
            onSelected: (order) => onCommand(ChangeSortCommand(order)),
          ),
        ],
      ),
    );
  }

  /// 低频操作：导出、打开目录、刷新、分类栏开关与清除筛选。
  Widget _buildMoreMenu(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const Key('vibe-library-more-export'),
          leadingIcon: const Icon(Icons.file_upload_outlined),
          onPressed: libraryState.entries.isEmpty
              ? null
              : () => onCommand(const ExportVibesCommand()),
          child: Text(l10n.vibeLibrary_exportTooltip),
        ),
        if (PlatformCapabilities.current.supportsOpenFolder)
          MenuItemButton(
            key: const Key('vibe-library-more-open-folder'),
            leadingIcon: const Icon(Icons.folder_open_outlined),
            onPressed: () => onCommand(const OpenLibraryFolderCommand()),
            child: Text(l10n.vibeLibrary_openFolderTooltip),
          ),
        MenuItemButton(
          key: const Key('vibe-library-more-refresh'),
          leadingIcon: const Icon(Icons.refresh_rounded),
          onPressed: libraryState.isLoading
              ? null
              : () => onCommand(const RefreshLibraryCommand()),
          child: Text(l10n.vibeLibrary_refresh),
        ),
        if (usePersistentCategories)
          MenuItemButton(
            key: const Key('vibe-library-more-category-panel'),
            leadingIcon: Icon(
              showCategoryPanel
                  ? Icons.view_sidebar
                  : Icons.view_sidebar_outlined,
            ),
            onPressed: () => onCommand(const ToggleCategoryPanelCommand()),
            child: Text(
              showCategoryPanel
                  ? l10n.vibeLibrary_hideCategoryPanel
                  : l10n.vibeLibrary_showCategoryPanel,
            ),
          ),
        if (libraryState.hasFilters) ...[
          const Divider(height: 1),
          MenuItemButton(
            key: const Key('vibe-library-more-clear-filters'),
            leadingIcon: Icon(
              Icons.filter_alt_off_rounded,
              color: colors.error,
            ),
            onPressed: () {
              controller.clearSearch();
              onCommand(const SelectCategoryCommand(null));
            },
            child: Text(
              l10n.localGallery_clearFilters,
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ],
      builder: (context, controller, _) => IconButton(
        key: const Key('vibe-library-more-action'),
        tooltip: l10n.common_moreActions,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.more_vert_rounded),
      ),
    );
  }

  void _handleImportPressed(BuildContext context) {
    onCommand(
      context.interactionPolicy.prefersTouchPresentation
          ? const ShowImportMenuCommand(Offset.zero)
          : const ImportVibesCommand(),
    );
  }

  Widget _buildBulkBar(BuildContext context) {
    final ids = libraryState.currentEntries.map((entry) => entry.id).toList();
    final allSelected =
        ids.isNotEmpty && ids.every(selectionState.selectedIds.contains);
    return BulkActionBar(
      selectedCount: selectionState.selectedIds.length,
      isAllSelected: allSelected,
      onExit: () => onCommand(const ExitSelectionModeCommand()),
      onSelectAll: () =>
          onCommand(ToggleCurrentPageSelectionCommand(select: !allSelected)),
      actions: imageCardBulkItems(context),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.itemWidth,
    required this.onCommand,
  });

  final VibeLibraryState state;
  final double itemWidth;
  final Future<void> Function(VibeLibraryCommand) onCommand;

  @override
  Widget build(BuildContext context) {
    if (state.error != null) {
      return GalleryErrorView(
        error: state.error,
        onRetry: () => onCommand(const RefreshLibraryCommand()),
      );
    }
    if (state.isInitializing && state.entries.isEmpty) {
      return const GalleryLoadingView();
    }
    if (state.entries.isEmpty) {
      return VibeLibraryEmptyView(
        onImport: () => onCommand(const ImportVibesCommand()),
      );
    }
    return VibeLibraryContentView(itemWidth: itemWidth);
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_upload_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(context.l10n.vibeLibrary_dropImportHint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImportOverlay extends StatelessWidget {
  const _ImportOverlay({required this.progress});

  final ImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 4,
                          value:
                              progress.progress ??
                              (MediaQuery.disableAnimationsOf(context)
                                  ? 0.5
                                  : null),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.vibeLibrary_importing,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (progress.isActive) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${progress.current} / ${progress.total}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                      if (progress.message.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          progress.message,
                          style: const TextStyle(color: Colors.white70),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
