import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/cache/local_image_aspect_ratio_cache.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/gallery/local_image_record.dart';
import '../../screens/online_gallery/online_gallery_masonry_layout.dart';
import '../../selection/card_drag_select.dart';
import 'draggable_image_card.dart';
import 'local_image_card_3d.dart';
import 'local_image_context_menu.dart';

class ResponsiveLayout {
  ResponsiveLayout._();

  static const double fixedCardWidth = 180;
  static const double fixedCardHeight = 220;

  static int calculateColumns(
    double screenWidth, {
    double spacing = 12,
    double padding = 16,
  }) {
    final availableWidth = screenWidth - padding * 2;
    final columns = ((availableWidth + spacing) / (fixedCardWidth + spacing))
        .floor();
    return columns.clamp(1, 8);
  }

  static double calculateGridWidth(int columns, {double spacing = 12}) {
    return columns * fixedCardWidth + (columns - 1) * spacing;
  }
}

enum _ScrollDirection { idle, up, down }

class GalleryGrid extends StatefulWidget {
  final List<LocalImageRecord> images;
  final int columns;
  final double spacing;
  final EdgeInsets padding;
  final void Function(LocalImageRecord record, int index)? onTap;
  final void Function(LocalImageRecord record, int index)? onDoubleTap;
  final void Function(LocalImageRecord record, int index)? onLongPress;
  final void Function(LocalImageRecord record, int index, TapUpDetails details)?
  onSecondaryTapUp;
  final void Function(LocalImageRecord record, int index)? onFavoriteToggle;
  final Future<void> Function(
    LocalImageRecord record,
    int index,
    LocalImageContextAction action,
  )?
  onSendAction;
  final bool isKritaConnected;
  final Set<int>? selectedIndices;
  final double preloadScreens;
  final bool enableDrag;

  const GalleryGrid({
    super.key,
    required this.images,
    this.columns = 4,
    this.spacing = 12,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.onFavoriteToggle,
    this.onSendAction,
    this.isKritaConnected = false,
    this.selectedIndices,
    this.preloadScreens = 2.0,
    this.enableDrag = true,
  });

  @override
  State<GalleryGrid> createState() => _GalleryGridState();
}

class _GalleryGridState extends State<GalleryGrid> {
  final Set<int> _visibleIndices = {};
  final Set<int> _preloadIndices = {};
  late final ScrollController _scrollController;
  _ScrollDirection _scrollDirection = _ScrollDirection.idle;
  double _lastScrollOffset = 0;
  double _viewportHeight = 0;

  /// 瀑布流几何只在图片、列数或宽度变化时重算，可见性刷新不触发重排。
  OnlineGalleryMasonryLayoutSnapshot? _layout;
  Object? _layoutKey;
  int _ratioGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _resolveAspectRatios();
  }

  @override
  void didUpdateWidget(GalleryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 图片列表变化时清理索引（如翻页时）
    if (oldWidget.images.length != widget.images.length ||
        (oldWidget.images.isNotEmpty &&
            widget.images.isNotEmpty &&
            oldWidget.images.first.path != widget.images.first.path)) {
      _visibleIndices.clear();
      _preloadIndices.clear();
    }
    if (!identical(oldWidget.images, widget.images)) _resolveAspectRatios();
  }

  /// 没有元数据尺寸的图片先按方形排版，读到文件头尺寸后统一重排一次。
  void _resolveAspectRatios() {
    final cache = LocalImageAspectRatioCache.instance;
    final images = widget.images;
    if (images.every((record) => cache.ratioOf(record) != null)) return;
    cache.resolve(images).then((_) {
      if (!mounted || !identical(widget.images, images)) return;
      setState(() => _ratioGeneration++);
    });
  }

  OnlineGalleryMasonryLayoutSnapshot _layoutFor({
    required int columns,
    required double itemWidth,
  }) {
    final key = (
      identityHashCode(widget.images),
      widget.images.length,
      columns,
      itemWidth,
      widget.spacing,
      _ratioGeneration,
    );
    final cached = _layout;
    if (cached != null && _layoutKey == key) return cached;
    final cache = LocalImageAspectRatioCache.instance;
    _layoutKey = key;
    return _layout = OnlineGalleryMasonryLayoutSnapshot(
      aspectRatios: [
        for (final record in widget.images) cache.ratioOf(record) ?? 1.0,
      ],
      placeholderCount: 0,
      columnCount: columns,
      itemWidth: itemWidth,
      mainAxisSpacing: widget.spacing,
      crossAxisSpacing: widget.spacing,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final currentOffset = _scrollController.offset;
    if (currentOffset > _lastScrollOffset) {
      _scrollDirection = _ScrollDirection.down;
    } else if (currentOffset < _lastScrollOffset) {
      _scrollDirection = _ScrollDirection.up;
    } else {
      _scrollDirection = _ScrollDirection.idle;
    }
    _lastScrollOffset = currentOffset;
  }

  int _getPriority(int index) {
    if (_visibleIndices.contains(index)) return 1;
    if (_preloadIndices.contains(index)) return 3;
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              context.l10n.localGallery_noImagesFound,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        final minimumHorizontalPadding = widget.padding.left;
        final availableWidth =
            (constraints.maxWidth -
                    minimumHorizontalPadding -
                    widget.padding.right)
                .clamp(0.0, double.infinity);
        final maximumColumns =
            ((availableWidth + widget.spacing) / (96 + widget.spacing))
                .floor()
                .clamp(1, 8);
        final columns = widget.columns.clamp(1, maximumColumns);
        final actualItemWidth =
            (availableWidth - widget.spacing * (columns - 1)) / columns;
        // 瀑布流：每张图按自身宽高比完整显示，放进当前最短的一列。
        final layout = _layoutFor(columns: columns, itemWidth: actualItemWidth);

        return GridView.builder(
          key: const PageStorageKey<String>('gallery-grid-scroll-view'),
          controller: _scrollController,
          primary: false,
          padding: widget.padding,
          gridDelegate: OnlineGalleryMasonryGridDelegate(snapshot: layout),
          itemCount: widget.images.length,
          // 限制缓存范围，减少内存占用和重建开销
          scrollCacheExtent: ScrollCacheExtent.pixels(
            _viewportHeight * widget.preloadScreens,
          ),
          itemBuilder: (context, index) {
            final record = widget.images[index];
            final isSelected = widget.selectedIndices?.contains(index) ?? false;
            final isVisible = _visibleIndices.contains(index);
            final priority = _getPriority(index);

            return CardDragSelectTarget(
              id: record.path,
              child: VisibilityDetector(
                key: ValueKey('v_${record.path}'),
                onVisibilityChanged: (info) {
                  // 检查 mounted 避免 dispose 后调用 setState
                  if (!mounted) return;

                  final isNowVisible = info.visibleFraction > 0.05;
                  final wasVisible = _visibleIndices.contains(index);

                  if (isNowVisible != wasVisible) {
                    setState(() {
                      if (isNowVisible) {
                        _visibleIndices.add(index);
                      } else {
                        _visibleIndices.remove(index);
                      }
                    });
                    if (isNowVisible) _updatePreloadRange(index);
                  }
                },
                child: RepaintBoundary(
                  child: _GalleryImageCard(
                    key: ValueKey(record.path),
                    record: record,
                    width: actualItemWidth,
                    height: layout.placementFor(index).mainAxisExtent,
                    isSelected: isSelected,
                    isVisible: isVisible,
                    priority: priority,
                    enableDrag: widget.enableDrag,
                    onTap: () => widget.onTap?.call(record, index),
                    onDoubleTap: widget.onDoubleTap == null
                        ? null
                        : () => widget.onDoubleTap!(record, index),
                    onLongPress: () => widget.onLongPress?.call(record, index),
                    onSecondaryTapUp: (details) =>
                        widget.onSecondaryTapUp?.call(record, index, details),
                    onFavoriteToggle: widget.onFavoriteToggle != null
                        ? () => widget.onFavoriteToggle!(record, index)
                        : null,
                    onSendAction: widget.onSendAction != null
                        ? (action) =>
                              widget.onSendAction!(record, index, action)
                        : null,
                    enableAddToAgent: widget.enableDrag,
                    isKritaConnected: widget.isKritaConnected,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updatePreloadRange(int visibleIndex) {
    final itemsPerRow = widget.columns;
    final rowsPerScreen = (_viewportHeight / ResponsiveLayout.fixedCardHeight)
        .ceil()
        .clamp(2, 10);
    final itemsPerScreen = itemsPerRow * rowsPerScreen;
    final preloadCount = (itemsPerScreen * widget.preloadScreens).round();

    final (
      int forwardPreload,
      int backwardPreload,
    ) = switch (_scrollDirection) {
      _ScrollDirection.down => (preloadCount, preloadCount ~/ 3),
      _ScrollDirection.up => (preloadCount ~/ 3, preloadCount),
      _ScrollDirection.idle => (preloadCount, preloadCount ~/ 2),
    };

    final newPreloadIndices = <int>{};

    for (var i = visibleIndex - backwardPreload; i < visibleIndex; i++) {
      if (i >= 0 && i < widget.images.length) newPreloadIndices.add(i);
    }

    for (var i = visibleIndex + 1; i <= visibleIndex + forwardPreload; i++) {
      if (i >= 0 && i < widget.images.length) newPreloadIndices.add(i);
    }

    if ((_preloadIndices.difference(newPreloadIndices).isNotEmpty ||
            newPreloadIndices.difference(_preloadIndices).isNotEmpty) &&
        mounted) {
      setState(() {
        _preloadIndices
          ..clear()
          ..addAll(newPreloadIndices);
      });
    }
  }
}

class _GalleryImageCard extends StatefulWidget {
  final LocalImageRecord record;
  final double width;
  final double height;
  final bool isSelected;
  final bool isVisible;
  final int priority;
  final bool enableDrag;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final void Function(TapUpDetails)? onSecondaryTapUp;
  final VoidCallback? onFavoriteToggle;
  final Future<void> Function(LocalImageContextAction action)? onSendAction;
  final bool enableAddToAgent;
  final bool isKritaConnected;

  const _GalleryImageCard({
    super.key,
    required this.record,
    required this.width,
    required this.height,
    this.isSelected = false,
    this.isVisible = false,
    this.priority = 5,
    this.enableDrag = true,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTapUp,
    this.onFavoriteToggle,
    this.onSendAction,
    this.enableAddToAgent = true,
    this.isKritaConnected = false,
  });

  @override
  State<_GalleryImageCard> createState() => _GalleryImageCardState();
}

class _GalleryImageCardState extends State<_GalleryImageCard> {
  @override
  Widget build(BuildContext context) {
    return LocalImageCard3D(
      record: widget.record,
      width: widget.width,
      height: widget.height,
      isSelected: widget.isSelected,
      isVisible: widget.isVisible,
      priority: widget.priority,
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress,
      onSecondaryTapUp: widget.onSecondaryTapUp,
      onFavoriteToggle: widget.onFavoriteToggle,
      onSendAction: widget.onSendAction,
      enableAddToAgent: widget.enableAddToAgent,
      isKritaConnected: widget.isKritaConnected,
      // 使用 dragWrapper 将拖拽功能注入到卡片内部
      // 解决 GestureDetector 与拖拽手势的冲突问题
      dragWrapper: widget.enableDrag
          ? DraggableImageCard.createDragWrapper(record: widget.record)
          : null,
    );
  }
}
