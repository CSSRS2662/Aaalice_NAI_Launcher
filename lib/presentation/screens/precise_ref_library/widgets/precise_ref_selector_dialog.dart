import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';

import '../../../../core/cache/image_file_aspect_ratio_cache.dart';
import '../../../../core/enums/precise_ref_type.dart';
import '../../../../core/extensions/precise_ref_type_extensions.dart';
import '../../../../data/models/precise_ref/precise_ref_library_entry.dart';
import '../../../../data/services/precise_ref_library_storage_service.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../providers/precise_ref_library_provider.dart';
import '../../../widgets/gallery/gallery_scope_controls.dart';
import '../../../widgets/gallery/library_masonry_grid.dart';

enum PreciseRefSelectorPurpose { add, export }

/// 精准参考库条目选择器对话框
///
/// 供生成页「从库导入」及精准参考库导出使用：网格 + 搜索 + 类型过滤。
/// [multiSelect] 为 false 时点击条目直接返回单个条目。
/// 导出用途默认全选，并提供当前筛选结果的全选与全不选操作。
/// 搜索与类型过滤为对话框内部状态，不影响库页面的过滤条件。
class PreciseRefSelectorDialog extends ConsumerStatefulWidget {
  const PreciseRefSelectorDialog({
    super.key,
    this.multiSelect = true,
    this.purpose = PreciseRefSelectorPurpose.add,
    this.scrollController,
  });

  final bool multiSelect;
  final PreciseRefSelectorPurpose purpose;
  final ScrollController? scrollController;

  static Future<List<PreciseRefLibraryEntry>?> show(
    BuildContext context, {
    bool multiSelect = true,
    PreciseRefSelectorPurpose purpose = PreciseRefSelectorPurpose.add,
  }) {
    return AdaptivePresenter.showForm<List<PreciseRefLibraryEntry>>(
      context: context,
      titleBuilder: (panelContext) => Text(
        purpose == PreciseRefSelectorPurpose.export
            ? panelContext.l10n.preciseRefLib_exportTitle
            : panelContext.l10n.preciseRefLib_selectorTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(panelContext).textTheme.titleLarge,
      ),
      dialogWidth: 720,
      expandCompact: true,
      builder: (panelContext, scrollController) => PreciseRefSelectorDialog(
        multiSelect: multiSelect,
        purpose: purpose,
        scrollController: scrollController,
      ),
    );
  }

  @override
  ConsumerState<PreciseRefSelectorDialog> createState() =>
      _PreciseRefSelectorDialogState();
}

class _PreciseRefSelectorDialogState
    extends ConsumerState<PreciseRefSelectorDialog> {
  final Set<String> _selectedIds = {};
  String _query = '';
  PreciseRefType? _typeFilter;
  bool _favoritesOnly = false;
  Timer? _searchDebounceTimer;
  List<PreciseRefLibraryEntry>? _cachedSourceEntries;
  String? _cachedQuery;
  PreciseRefType? _cachedTypeFilter;
  bool? _cachedFavoritesOnly;
  Object? _ratioRequest;
  List<PreciseRefLibraryEntry> _cachedVisibleEntries = const [];
  bool _initializedExportSelection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(preciseRefLibraryNotifierProvider.notifier).initialize();
    });
  }

  void _confirm(List<PreciseRefLibraryEntry> entries) {
    final selected = entries.where((e) => _selectedIds.contains(e.id)).toList();
    Navigator.of(context).pop(selected);
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _query != value) {
        setState(() => _query = value);
      }
    });
  }

  List<PreciseRefLibraryEntry> _visibleEntries(
    List<PreciseRefLibraryEntry> source,
  ) {
    if (identical(_cachedSourceEntries, source) &&
        _cachedQuery == _query &&
        _cachedTypeFilter == _typeFilter &&
        _cachedFavoritesOnly == _favoritesOnly) {
      return _cachedVisibleEntries;
    }

    var entries = source.search(_query);
    final typeFilter = _typeFilter;
    if (typeFilter != null) {
      entries = entries.where((entry) => entry.type == typeFilter).toList();
    }
    if (_favoritesOnly) {
      entries = entries.where((entry) => entry.isFavorite).toList();
    }
    _cachedSourceEntries = source;
    _cachedQuery = _query;
    _cachedTypeFilter = typeFilter;
    _cachedFavoritesOnly = _favoritesOnly;
    _cachedVisibleEntries = entries.sortedByCreatedAt();
    return _cachedVisibleEntries;
  }

  /// 没有尺寸的原图先按方形排版，读到文件头尺寸后统一重排一次。
  void _resolveAspectRatios(List<PreciseRefLibraryEntry> entries) {
    final cache = ImageFileAspectRatioCache.instance;
    final missing = [
      for (final entry in entries)
        if (cache.ratioOf(entry.imagePath) == null) entry.imagePath,
    ];
    if (missing.isEmpty) return;
    final request = Object.hashAll(missing);
    if (_ratioRequest == request) return;
    _ratioRequest = request;
    cache.resolve(missing).then((_) {
      if (mounted) setState(() => _ratioRequest = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(preciseRefLibraryNotifierProvider);
    final entries = _visibleEntries(state.entries);
    if (widget.purpose == PreciseRefSelectorPurpose.export &&
        !_initializedExportSelection &&
        !state.isLoading) {
      _selectedIds.addAll(state.entries.map((entry) => entry.id));
      _initializedExportSelection = true;
    }

    return LayoutBuilder(
      key: const Key('precise-ref-selector-dialog'),
      builder: (context, constraints) {
        final columns = libraryMasonryColumns(
          constraints.maxWidth - 32,
          spacing: 8,
        );
        final shrinkWrapContent =
            MediaQuery.sizeOf(context).width >= 600 &&
            entries.length <= columns * 2;
        _resolveAspectRatios(entries);
        final ratios = ImageFileAspectRatioCache.instance;
        final actions = Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.common_cancel),
            ),
            if (widget.multiSelect)
              FilledButton(
                key: const Key('precise-ref-selector-confirm'),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _confirm(state.entries),
                child: Text(
                  widget.purpose == PreciseRefSelectorPurpose.export
                      ? l10n.preciseRefLib_exportConfirm(_selectedIds.length)
                      : l10n.preciseRefLib_selectorConfirm(_selectedIds.length),
                ),
              ),
          ],
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: CustomScrollView(
                controller: widget.scrollController,
                shrinkWrap: shrinkWrapContent,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    sliver: SliverList.list(
                      children: [
                        if (widget.purpose ==
                            PreciseRefSelectorPurpose.export) ...[
                          Text(
                            l10n.preciseRefLib_exportSelectionHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextField(
                          key: const Key('precise-ref-selector-search'),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText: l10n.preciseRefLib_searchHint,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                        const SizedBox(height: 8),
                        GalleryScopeRow(
                          key: const Key('precise-ref-selector-type-scroll'),
                          children: [
                            GalleryScopeToggle(
                              favorites: _favoritesOnly,
                              onShowAll: () =>
                                  setState(() => _favoritesOnly = false),
                              onShowFavorites: () =>
                                  setState(() => _favoritesOnly = true),
                              allKey: const Key(
                                'precise-ref-selector-scope-all',
                              ),
                              favoritesKey: const Key(
                                'precise-ref-selector-scope-favorites',
                              ),
                            ),
                            GalleryFilterMenuChip<PreciseRefType?>(
                              chipKey: const Key(
                                'precise-ref-selector-type-chip',
                              ),
                              clearKey: const Key(
                                'precise-ref-selector-type-clear',
                              ),
                              icon: Icons.category_outlined,
                              placeholder: l10n.preciseRef_referenceType,
                              value: _typeFilter,
                              options: [
                                for (final type in PreciseRefType.values)
                                  GalleryFilterOption<PreciseRefType?>(
                                    key: Key(
                                      'precise-ref-selector-type-option-${type.name}',
                                    ),
                                    value: type,
                                    icon: type.icon,
                                    label: type.getDisplayName(
                                      character: l10n.preciseRef_typeCharacter,
                                      style: l10n.preciseRef_typeStyle,
                                      characterAndStyle:
                                          l10n.preciseRef_typeCharacterAndStyle,
                                    ),
                                  ),
                              ],
                              onSelected: (type) =>
                                  setState(() => _typeFilter = type),
                            ),
                          ],
                        ),
                        if (widget.purpose ==
                            PreciseRefSelectorPurpose.export) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton(
                                key: const Key('precise-ref-export-select-all'),
                                onPressed: entries.isEmpty
                                    ? null
                                    : () => setState(
                                        () => _selectedIds.addAll(
                                          entries.map((entry) => entry.id),
                                        ),
                                      ),
                                child: Text(l10n.common_selectAll),
                              ),
                              TextButton(
                                key: const Key(
                                  'precise-ref-export-deselect-all',
                                ),
                                onPressed: _selectedIds.isEmpty
                                    ? null
                                    : () => setState(_selectedIds.clear),
                                child: Text(l10n.common_deselectAll),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (state.isLoading)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 160,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: MediaQuery.disableAnimationsOf(context)
                                ? 0.72
                                : null,
                          ),
                        ),
                      ),
                    )
                  else if (state.error != null)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 160,
                        child: _buildErrorView(state.error!),
                      ),
                    )
                  else if (entries.isEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 160,
                        child: Center(
                          child: Text(
                            l10n.preciseRefLib_emptyTouch,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: LibraryMasonrySliverGrid(
                        scaleWithText: false,
                        itemCount: entries.length,
                        aspectRatioOf: (index) =>
                            ratios.ratioOf(entries[index].imagePath) ?? 1.0,
                        itemBuilder: (context, index, _) {
                          final entry = entries[index];
                          return _SelectorItem(
                            entry: entry,
                            selected:
                                widget.multiSelect &&
                                _selectedIds.contains(entry.id),
                            onTap: () {
                              if (!widget.multiSelect) {
                                Navigator.of(context).pop([entry]);
                                return;
                              }
                              setState(() {
                                if (!_selectedIds.remove(entry.id)) {
                                  _selectedIds.add(entry.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 12)),
                  if (!shrinkWrapContent)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverToBoxAdapter(child: actions),
                    ),
                ],
              ),
            ),
            if (shrinkWrapContent)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: actions,
              ),
          ],
        );
      },
    );
  }

  Widget _buildErrorView(String error) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(
            l10n.preciseRefLib_loadFailed(error),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => ref
                .read(preciseRefLibraryNotifierProvider.notifier)
                .reload(showLoading: true),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.common_retry),
          ),
        ],
      ),
    );
  }
}

class _SelectorItem extends ConsumerStatefulWidget {
  const _SelectorItem({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final PreciseRefLibraryEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<_SelectorItem> createState() => _SelectorItemState();
}

class _SelectorItemState extends ConsumerState<_SelectorItem> {
  Uint8List? _thumbnail;
  bool _requested = false;

  @override
  void didUpdateWidget(covariant _SelectorItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _thumbnail = null;
      _requested = false;
    }
  }

  void _loadThumbnail() {
    if (_requested) return;
    _requested = true;
    final id = widget.entry.id;
    final storage = ref.read(preciseRefLibraryStorageServiceProvider);
    // 内存缓存同步命中时直接赋值，让卡片重建后的首帧就有图
    final cached = storage.peekDisplayThumbnail(id);
    if (cached != null && cached.isNotEmpty) {
      _thumbnail = cached;
      return;
    }
    storage.getDisplayThumbnail(id).then((bytes) {
      if (!mounted || widget.entry.id != id) return;
      setState(() => _thumbnail = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    _loadThumbnail();
    final theme = Theme.of(context);
    final entry = widget.entry;

    return InkWell(
      key: Key('precise-ref-selector-item-${entry.id}'),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: widget.selected
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_thumbnail != null)
              Image.memory(
                _thumbnail!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              Icon(
                Icons.image_outlined,
                size: 24,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 18, 6, 5),
                  child: Row(
                    children: [
                      Icon(entry.type.icon, size: 12, color: Colors.white70),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.selected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
