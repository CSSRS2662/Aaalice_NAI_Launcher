import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../screens/online_gallery/online_gallery_masonry_layout.dart';

/// 库页面共用的列数：与本地图库一致，手机宽度为两列，更宽时按最小卡片宽度
/// 增加列数；卡片带文字叠层，放大文字时同步放宽最小宽度。
int libraryMasonryColumns(
  double availableWidth, {
  double spacing = 12,
  double textScale = 1,
}) {
  final scale = textScale.clamp(1.0, 3.0);
  final minimum = (availableWidth < 336 ? 136.0 : 160.0) + (scale - 1) * 44;
  return ((availableWidth + spacing) / (minimum + spacing)).floor().clamp(1, 8);
}

/// [LibraryMasonryGrid] 的 sliver 版本，供带搜索与筛选头部的
/// [CustomScrollView]（如选择器弹窗）使用；条目数量较少，每次布局重算几何。
class LibraryMasonrySliverGrid extends StatelessWidget {
  const LibraryMasonrySliverGrid({
    super.key,
    required this.itemCount,
    required this.aspectRatioOf,
    required this.itemBuilder,
    this.spacing = 8,
    this.scaleWithText = true,
  });

  final int itemCount;
  final double Function(int index) aspectRatioOf;
  final Widget Function(BuildContext context, int index, Size size) itemBuilder;
  final double spacing;

  /// 卡片只有单行叠字（如选择器）时关闭：放大文字不减少列数。
  final bool scaleWithText;

  @override
  Widget build(BuildContext context) {
    final textScale = scaleWithText
        ? MediaQuery.textScalerOf(context).scale(14) / 14
        : 1.0;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.crossAxisExtent;
        final columns = libraryMasonryColumns(
          available,
          spacing: spacing,
          textScale: textScale,
        );
        final itemWidth = (available - spacing * (columns - 1)) / columns;
        final snapshot = OnlineGalleryMasonryLayoutSnapshot(
          aspectRatios: [for (var i = 0; i < itemCount; i++) aspectRatioOf(i)],
          placeholderCount: 0,
          columnCount: columns,
          itemWidth: itemWidth,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
        );
        return SliverGrid(
          gridDelegate: OnlineGalleryMasonryGridDelegate(snapshot: snapshot),
          delegate: SliverChildBuilderDelegate(
            (context, index) => itemBuilder(
              context,
              index,
              Size(itemWidth, snapshot.placementFor(index).mainAxisExtent),
            ),
            childCount: itemCount,
          ),
        );
      },
    );
  }
}

/// 按图片宽高比排列的瀑布流：每张图完整显示，放进当前最短的一列。
///
/// 几何在构建卡片前就已确定，复用在线画廊的 [OnlineGalleryMasonryGridDelegate]，
/// 快速滚动时不必逐个测量卡片。
class LibraryMasonryGrid extends StatefulWidget {
  const LibraryMasonryGrid({
    super.key,
    required this.itemCount,
    required this.aspectRatioOf,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(12),
    this.spacing = 12,
    this.gridKey,
    this.scrollCacheExtent,
    this.addAutomaticKeepAlives = true,
  });

  final int itemCount;

  /// 宽高比（宽 / 高）；未知时返回占位值，得到真实值后由调用方重建。
  final double Function(int index) aspectRatioOf;
  final Widget Function(BuildContext context, int index, Size size) itemBuilder;
  final EdgeInsets padding;
  final double spacing;
  final Key? gridKey;
  final ScrollCacheExtent? scrollCacheExtent;
  final bool addAutomaticKeepAlives;

  @override
  State<LibraryMasonryGrid> createState() => _LibraryMasonryGridState();
}

class _LibraryMasonryGridState extends State<LibraryMasonryGrid> {
  OnlineGalleryMasonryLayoutSnapshot? _snapshot;
  List<double>? _ratios;
  (int, double, double)? _geometry;

  OnlineGalleryMasonryLayoutSnapshot _layout(
    List<double> ratios,
    int columns,
    double itemWidth,
  ) {
    final geometry = (columns, itemWidth, widget.spacing);
    final cached = _snapshot;
    if (cached != null &&
        _geometry == geometry &&
        listEquals(_ratios, ratios)) {
      return cached;
    }
    _ratios = ratios;
    _geometry = geometry;
    return _snapshot = OnlineGalleryMasonryLayoutSnapshot(
      aspectRatios: ratios,
      placeholderCount: 0,
      columnCount: columns,
      itemWidth: itemWidth,
      mainAxisSpacing: widget.spacing,
      crossAxisSpacing: widget.spacing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxWidth - widget.padding.horizontal)
            .clamp(0.0, double.infinity);
        final columns = libraryMasonryColumns(
          available,
          spacing: widget.spacing,
          textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
        );
        final itemWidth =
            (available - widget.spacing * (columns - 1)) / columns;
        final snapshot = _layout(
          [for (var i = 0; i < widget.itemCount; i++) widget.aspectRatioOf(i)],
          columns,
          itemWidth,
        );
        return GridView.builder(
          key: widget.gridKey,
          padding: widget.padding,
          gridDelegate: OnlineGalleryMasonryGridDelegate(snapshot: snapshot),
          itemCount: widget.itemCount,
          scrollCacheExtent: widget.scrollCacheExtent,
          addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
          itemBuilder: (context, index) => widget.itemBuilder(
            context,
            index,
            Size(itemWidth, snapshot.placementFor(index).mainAxisExtent),
          ),
        );
      },
    );
  }
}
