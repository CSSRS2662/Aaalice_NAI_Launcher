import '../common/image_card_batch_scope.dart';
import '../common/image_card_action.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/local_gallery_provider.dart';
import '../../providers/selection_mode_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../bulk_action_bar.dart';
import '../common/translated_tag_text.dart';
import '../gallery_filter_panel.dart';
import 'gallery_sidebar.dart';
import 'gallery_library_toolbar.dart';
import 'local_gallery_scope_bar.dart';

import '../autocomplete/autocomplete_config.dart';
import '../autocomplete/autocomplete_wrapper.dart';

/// Local gallery toolbar with search, filter and actions
/// 本地画廊工具栏
///
/// 按职责分三行：标题行（名称、数量、多选与“更多”菜单）、搜索行（搜索与
/// 高级筛选）、范围行（全部 / 收藏一键切换，日期与分类条件）。刷新、撤销、
/// 日期分组等低频操作收进“更多”菜单。
class LocalGalleryToolbar extends ConsumerStatefulWidget {
  /// Whether 3D card view mode is active
  /// 是否启用3D卡片视图模式
  final bool use3DCardView;

  /// Callback when view mode is toggled
  /// 视图模式切换回调
  final VoidCallback? onToggleViewMode;

  /// Callback when open folder button is pressed
  /// 打开文件夹按钮回调
  final VoidCallback? onOpenFolder;

  /// Callback when refresh button is pressed
  /// 刷新按钮回调
  final VoidCallback? onRefresh;

  /// Callback when enter selection mode button is pressed
  /// 进入选择模式按钮回调
  final VoidCallback? onEnterSelectionMode;

  /// Callback when undo button is pressed
  /// 撤销按钮回调
  final VoidCallback? onUndo;

  /// Callback when redo button is pressed
  /// 重做按钮回调
  final VoidCallback? onRedo;

  /// Whether undo is available
  /// 是否可撤销
  final bool canUndo;

  /// Whether redo is available
  /// 是否可重做
  final bool canRedo;

  /// Whether category panel is visible
  /// 是否显示分类面板
  final bool showCategoryPanel;

  /// Callback when category panel toggle is pressed
  /// 分类面板切换按钮回调
  final VoidCallback? onToggleCategoryPanel;

  /// 范围切换：显示全部图片 / 只显示收藏。
  final VoidCallback? onShowAll;
  final VoidCallback? onShowFavorites;

  /// 清除当前分类或相簿条件。
  final VoidCallback? onClearCollection;

  /// 选择日期并跳转到对应的日期分组。
  final VoidCallback? onJumpToDate;

  /// 当前选中的分类或相簿名称，显示在范围栏的分类条件上。
  final String? collectionLabel;

  /// Whether search autocomplete is enabled.
  /// 是否启用搜索自动补全。
  final bool enableSearchAutocomplete;

  /// Controls whether the shared collection toolbar includes page identity.
  final bool showPageTitle;
  final List<ImageCardAction> batchActions;

  const LocalGalleryToolbar({
    super.key,
    this.use3DCardView = true,
    this.onToggleViewMode,
    this.onOpenFolder,
    this.onRefresh,
    this.onEnterSelectionMode,
    this.onUndo,
    this.onRedo,
    this.canUndo = false,
    this.canRedo = false,
    this.batchActions = const [],
    this.showCategoryPanel = true,
    this.onToggleCategoryPanel,
    this.onShowAll,
    this.onShowFavorites,
    this.onClearCollection,
    this.onJumpToDate,
    this.collectionLabel,
    this.enableSearchAutocomplete = true,
    this.showPageTitle = true,
  });

  @override
  ConsumerState<LocalGalleryToolbar> createState() =>
      _LocalGalleryToolbarState();
}

class _LocalGalleryToolbarState extends ConsumerState<LocalGalleryToolbar> {
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode(onKeyEvent: _handleSearchKeyEvent);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    // Future 不需要 dispose
    super.dispose();
  }

  /// Search with debounce
  /// 搜索防抖
  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(value);
    });
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyA) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
    return KeyEventResult.handled;
  }

  Future<void> _selectAllFilteredImages() async {
    final paths = await ref
        .read(localGalleryNotifierProvider.notifier)
        .getFilteredImagePaths();
    if (!mounted) return;

    ref
        .read(localGallerySelectionNotifierProvider.notifier)
        .replaceSelection(paths);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localGalleryNotifierProvider);
    final selectionState = ref.watch(localGallerySelectionNotifierProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // Show bulk action bar when in selection mode
    // 选择模式时显示批量操作栏
    if (selectionState.isActive) {
      final currentPageImagePaths =
          (state.isGroupedView ? state.groupedImages : state.currentImages)
              .map((r) => r.path)
              .toList();
      final isCurrentPageSelected =
          currentPageImagePaths.isNotEmpty &&
          currentPageImagePaths.every(
            (p) => selectionState.selectedIds.contains(p),
          );
      final selectableResultCount = state.hasFilters
          ? state.filteredCount
          : state.totalCount;
      final isAllResultSelected =
          selectableResultCount > 0 &&
          selectionState.selectedIds.length == selectableResultCount;

      return BulkActionBar(
        selectedCount: selectionState.selectedIds.length,
        isAllSelected: isCurrentPageSelected,
        isAllAvailableSelected: isAllResultSelected,
        onExit: () =>
            ref.read(localGallerySelectionNotifierProvider.notifier).exit(),
        onSelectAll: () {
          if (isCurrentPageSelected) {
            ref
                .read(localGallerySelectionNotifierProvider.notifier)
                .deselectAll(currentPageImagePaths);
          } else {
            ref
                .read(localGallerySelectionNotifierProvider.notifier)
                .selectAll(currentPageImagePaths);
          }
        },
        onSelectAllAvailable: selectableResultCount > 0
            ? () {
                if (isAllResultSelected) {
                  ref
                      .read(localGallerySelectionNotifierProvider.notifier)
                      .clearSelection();
                } else {
                  unawaited(_selectAllFilteredImages());
                }
              }
            : null,
        selectAllLabel: l10n.localGallery_selectCurrentPage,
        deselectAllLabel: l10n.localGallery_deselectCurrentPage,
        selectAllAvailableLabel: l10n.localGallery_selectAllResults,
        deselectAllAvailableLabel: l10n.localGallery_deselectAllResults,
        actions: imageCardBulkItems(context, actions: widget.batchActions),
      );
    }

    // Normal toolbar
    // 普通工具栏
    final criteria = state.filterCriteria;
    return GalleryLibraryToolbar(
      key: const Key('local-gallery-toolbar'),
      title: widget.showPageTitle
          ? GalleryCollectionPageTitle(
              icon: Icons.photo_library_outlined,
              title: l10n.localGallery_title,
            )
          : const SizedBox.shrink(),
      count: state.isIndexing
          ? null
          : GalleryLibraryCountBadge(
              label: state.hasFilters
                  ? '${state.filteredCount}/${state.totalCount}'
                  : '${state.totalCount}',
            ),
      search: _buildSearchField(),
      primaryAction: _FilterPanelButton(
        active: criteria.hasMetadataFilters || criteria.hasAdvancedFilters,
        onPressed: () => showGalleryFilterPanel(context),
      ),
      titleActions: [
        IconButton(
          key: const ValueKey('local-gallery-select-action'),
          tooltip: l10n.localGallery_enterSelectionMode,
          onPressed: widget.onEnterSelectionMode,
          icon: const Icon(Icons.checklist_rounded),
        ),
        _buildMoreMenu(state),
      ],
      filters: LocalGalleryScopeBar(
        onShowAll: widget.onShowAll ?? () {},
        onShowFavorites: widget.onShowFavorites ?? () {},
        onPickDateRange: () => _selectDateRange(context, state),
        onClearDateRange: () => ref
            .read(localGalleryNotifierProvider.notifier)
            .setDateRange(null, null),
        onOpenCollections: widget.onToggleCategoryPanel ?? () {},
        onClearCollection: widget.onClearCollection ?? () {},
        collectionLabel: widget.collectionLabel,
      ),
      supplementary: state.filterCriteria.selectedTags.isEmpty
          ? null
          : _buildSelectedTagChips(theme, state),
    );
  }

  /// 低频操作：日期分组视图、跳转日期、撤销重做、刷新、打开文件夹与清除筛选。
  Widget _buildMoreMenu(LocalGalleryState state) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('local-gallery-more-group-by-date'),
          leadingIcon: const Icon(Icons.calendar_view_day_rounded),
          trailingIcon: state.isGroupedView
              ? Icon(Icons.check_rounded, color: colors.primary)
              : null,
          onPressed: () => notifier.setGroupedView(!state.isGroupedView),
          child: Text(l10n.localGallery_groupByDate),
        ),
        if (widget.onJumpToDate != null)
          MenuItemButton(
            key: const ValueKey('local-gallery-more-jump-to-date'),
            leadingIcon: const Icon(Icons.event_note_rounded),
            onPressed: widget.onJumpToDate,
            child: Text(l10n.shortcut_action_jump_to_date),
          ),
        const Divider(height: 1),
        if (widget.canUndo || widget.canRedo) ...[
          MenuItemButton(
            key: const ValueKey('local-gallery-more-undo'),
            leadingIcon: const Icon(Icons.undo_rounded),
            onPressed: widget.canUndo ? widget.onUndo : null,
            child: Text(l10n.common_undo),
          ),
          MenuItemButton(
            key: const ValueKey('local-gallery-more-redo'),
            leadingIcon: const Icon(Icons.redo_rounded),
            onPressed: widget.canRedo ? widget.onRedo : null,
            child: Text(l10n.common_redo),
          ),
        ],
        MenuItemButton(
          key: const ValueKey('local-gallery-more-refresh'),
          leadingIcon: const Icon(Icons.refresh_rounded),
          onPressed: widget.onRefresh,
          child: Text(l10n.common_refresh),
        ),
        if (widget.onOpenFolder != null)
          MenuItemButton(
            key: const ValueKey('local-gallery-more-open-folder'),
            leadingIcon: const Icon(Icons.folder_open_rounded),
            onPressed: widget.onOpenFolder,
            child: Text(l10n.shortcut_action_open_folder),
          ),
        if (state.hasFilters) ...[
          const Divider(height: 1),
          MenuItemButton(
            key: const ValueKey('local-gallery-more-clear-filters'),
            leadingIcon: Icon(
              Icons.filter_alt_off_rounded,
              color: colors.error,
            ),
            onPressed: () {
              _searchController.clear();
              notifier.clearAllFilters();
            },
            child: Text(
              l10n.localGallery_clearFilters,
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ],
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('local-gallery-more-action'),
        tooltip: l10n.common_moreActions,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.more_vert_rounded),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(localGalleryNotifierProvider.notifier).setSearchQuery('');
    setState(() {});
  }

  /// Build search field
  /// 构建搜索框 - 类似在线画廊的简洁圆角样式
  Widget _buildSearchField() {
    final searchField = GalleryLibrarySearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: context.l10n.localGallery_searchFilenamePromptPlaceholder,
      onChanged: _onSearchChanged,
      onClear: _clearSearch,
      onSubmitted: (value) {
        _debounceTimer?.cancel();
        ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(value);
      },
    );

    if (!widget.enableSearchAutocomplete) {
      return searchField;
    }

    return AutocompleteWrapper(
      controller: _searchController,
      focusNode: _searchFocusNode,
      config: const AutocompleteConfig(
        minQueryLength: 2,
        showTranslation: true,
        showCategory: true,
        showCount: true,
        autoInsertComma: false,
      ),
      onSuggestionSelected: (value) {
        // 选择补全建议后仍然作为搜索框文本处理，不转为标签 chip。
        _debounceTimer?.cancel();
        ref.read(localGalleryNotifierProvider.notifier).setSearchQuery(value);
      },
      child: searchField,
    );
  }

  Widget _buildSelectedTagChips(ThemeData theme, LocalGalleryState state) {
    final tags = state.filterCriteria.selectedTags;

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              context.l10n.localGallery_tagIntersection,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final tag in tags)
            InputChip(
              avatar: const Icon(Icons.tag, size: 14),
              label: TranslatedTagText(tag),
              onDeleted: () {
                ref
                    .read(localGalleryNotifierProvider.notifier)
                    .removeSelectedTag(tag);
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
        ],
      ),
    );
  }

  /// Select date range
  /// 选择日期范围
  Future<void> _selectDateRange(
    BuildContext context,
    LocalGalleryState state,
  ) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange:
          state.filterCriteria.dateStart != null &&
              state.filterCriteria.dateEnd != null
          ? DateTimeRange(
              start: state.filterCriteria.dateStart!,
              end: state.filterCriteria.dateEnd!,
            )
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      ref
          .read(localGalleryNotifierProvider.notifier)
          .setDateRange(picked.start, picked.end);
    }
  }
}

/// 高级筛选入口：与搜索框同高，存在模型、采样等筛选时换成强调色面并加圆点。
class _FilterPanelButton extends StatelessWidget {
  const _FilterPanelButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final extent = 48.0 + (textScale - 1).clamp(0.0, 2.0) * 8.0;
    return Badge(
      isLabelVisible: active,
      smallSize: 8,
      offset: const Offset(-6, 6),
      backgroundColor: colors.primary,
      child: IconButton(
        key: const ValueKey('local-gallery-filter-action'),
        tooltip: context.l10n.localGallery_openFilterPanel,
        isSelected: active,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: Size.square(extent),
          backgroundColor: active
              ? colors.primaryContainer
              : controlSurfaceColor(colors),
          foregroundColor: active
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.tune_rounded),
      ),
    );
  }
}
