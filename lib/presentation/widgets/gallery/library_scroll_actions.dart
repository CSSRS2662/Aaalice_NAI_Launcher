import 'package:flutter/material.dart';

/// Touch affordances around a library list: pull down from the top to refresh,
/// and [onLoadMore] while [canLoadMore] once the end is near — including when
/// the loaded items do not fill the viewport yet.
class LibraryScrollActions extends StatelessWidget {
  const LibraryScrollActions({
    super.key,
    required this.child,
    this.onRefresh,
    this.onLoadMore,
    this.canLoadMore = false,
  });

  final Widget child;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final bool canLoadMore;

  /// Remaining scroll extent below which the next page loads.
  static const double loadMoreExtent = 800;

  bool _handle(Notification notification) {
    final loadMore = onLoadMore;
    if (loadMore == null || !canLoadMore) return false;
    final metrics = switch (notification) {
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      ScrollUpdateNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics != null &&
        metrics.axis == Axis.vertical &&
        metrics.extentAfter < loadMoreExtent) {
      loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    Widget result = NotificationListener<Notification>(
      onNotification: _handle,
      child: child,
    );
    final refresh = onRefresh;
    if (refresh != null) {
      final configuration = ScrollConfiguration.of(context);
      result = RefreshIndicator(
        onRefresh: refresh,
        // Short lists must still be pullable.
        child: ScrollConfiguration(
          behavior: configuration.copyWith(
            physics: AlwaysScrollableScrollPhysics(
              parent: configuration.getScrollPhysics(context),
            ),
          ),
          child: result,
        ),
      );
    }
    return result;
  }
}
