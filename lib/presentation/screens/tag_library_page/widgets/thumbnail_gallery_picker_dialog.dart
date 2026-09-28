import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/gallery/local_image_record.dart';
import '../../../../data/services/gallery/local_gallery_service.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../providers/local_gallery_provider.dart';
import '../../../widgets/common/image_viewport_surface.dart';
import '../../../widgets/gallery/gallery_scope_controls.dart';

typedef ThumbnailGalleryPageLoader =
    Future<LocalGalleryQueryPage> Function({
      required int page,
      required int pageSize,
      required bool favoritesOnly,
    });

/// 从应用内图库的历史记录或收藏中选择词库预览图。
class ThumbnailGalleryPickerDialog extends ConsumerStatefulWidget {
  const ThumbnailGalleryPickerDialog({super.key, this.pageLoader});

  final ThumbnailGalleryPageLoader? pageLoader;

  static Future<String?> show(
    BuildContext context, {
    ThumbnailGalleryPageLoader? pageLoader,
  }) {
    return AdaptivePresenter.showForm<String>(
      context: context,
      titleBuilder: (panelContext) => Row(
        children: [
          Icon(
            Icons.photo_library_outlined,
            color: Theme.of(panelContext).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              panelContext.l10n.tagLibrary_selectFromAppGallery,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(panelContext).textTheme.titleLarge,
            ),
          ),
        ],
      ),
      dialogWidth: 720,
      maxCenteredHeight: 680,
      builder: (_, __) => ThumbnailGalleryPickerDialog(pageLoader: pageLoader),
    );
  }

  @override
  ConsumerState<ThumbnailGalleryPickerDialog> createState() =>
      _ThumbnailGalleryPickerDialogState();
}

class _ThumbnailGalleryPickerDialogState
    extends ConsumerState<ThumbnailGalleryPickerDialog> {
  static const _pageSize = 50;

  final _scrollController = ScrollController();
  LocalGalleryService? _galleryService;
  List<LocalImageRecord> _records = const [];
  Object? _error;
  bool _favoritesOnly = false;
  bool _loading = false;
  bool _hasMore = true;
  int _page = -1;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadPage(reset: true));
    });
  }

  @override
  void dispose() {
    _requestSerial++;
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >= 240 ||
        _loading ||
        _error != null ||
        !_hasMore) {
      return;
    }
    unawaited(_loadPage());
  }

  Future<LocalGalleryQueryPage> _queryPage({
    required int page,
    required bool favoritesOnly,
  }) async {
    final injectedLoader = widget.pageLoader;
    if (injectedLoader != null) {
      return injectedLoader(
        page: page,
        pageSize: _pageSize,
        favoritesOnly: favoritesOnly,
      );
    }

    final notifier = ref.read(localGalleryNotifierProvider.notifier);
    await notifier.initialize();
    if (!mounted) throw StateError('Thumbnail gallery picker was closed');
    final galleryState = ref.read(localGalleryNotifierProvider);
    if (galleryState.error case final error?) {
      throw StateError(error.localized(context.l10n));
    }
    final service = _galleryService ??= await notifier.getService();
    return service.queryPage(
      page: page,
      pageSize: _pageSize,
      favoritesOnly: favoritesOnly,
    );
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading && !reset) return;
    final requestSerial = ++_requestSerial;
    final requestedFavoritesOnly = _favoritesOnly;
    final requestedPage = reset ? 0 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _records = const [];
        _page = -1;
        _hasMore = true;
      }
    });

    try {
      final result = await _queryPage(
        page: requestedPage,
        favoritesOnly: requestedFavoritesOnly,
      );
      if (!mounted ||
          requestSerial != _requestSerial ||
          requestedFavoritesOnly != _favoritesOnly) {
        return;
      }
      setState(() {
        _records = reset
            ? result.records
            : <LocalImageRecord>[
                ..._records,
                ...result.records.where(
                  (candidate) =>
                      !_records.any((record) => record.path == candidate.path),
                ),
              ];
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
      _loadAgainIfViewportIsNotFull();
    } on Object catch (error) {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _loadAgainIfViewportIsNotFull() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _loading ||
          _error != null ||
          !_hasMore) {
        return;
      }
      if (_scrollController.position.extentAfter < 240) {
        unawaited(_loadPage());
      }
    });
  }

  void _setFavoritesOnly(bool value) {
    if (_favoritesOnly == value) return;
    setState(() => _favoritesOnly = value);
    unawaited(_loadPage(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GalleryScopeRow(
            key: const ValueKey('thumbnail-gallery-source-tabs'),
            children: [
              GalleryScopeToggle(
                favorites: _favoritesOnly,
                onShowAll: () => _setFavoritesOnly(false),
                onShowFavorites: () => _setFavoritesOnly(true),
                allKey: const ValueKey('thumbnail-gallery-scope-all'),
                favoritesKey: const ValueKey(
                  'thumbnail-gallery-scope-favorites',
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading && _records.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          value: MediaQuery.disableAnimationsOf(context) ? 0.72 : null,
        ),
      );
    }
    if (_error != null && _records.isEmpty) {
      return _buildError();
    }
    if (_records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.localGallery_noImagesFound,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    }

    return MasonryGridView.extent(
      key: const ValueKey('thumbnail-gallery-grid'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      maxCrossAxisExtent: 220,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      itemCount: _records.length + (_loading || _error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _records.length) {
          return _error == null
              ? Center(
                  child: CircularProgressIndicator(
                    value: MediaQuery.disableAnimationsOf(context)
                        ? 0.72
                        : null,
                  ),
                )
              : Center(
                  child: IconButton(
                    tooltip: context.l10n.common_retry,
                    onPressed: () => unawaited(_loadPage()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                );
        }
        final record = _records[index];
        return _GalleryImageTile(
          key: ValueKey('thumbnail-gallery-image-${record.path}'),
          record: record,
          onTap: () => Navigator.of(context).pop(record.path),
        );
      },
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '${context.l10n.common_error}: $_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => unawaited(_loadPage(reset: true)),
              child: Text(context.l10n.common_retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryImageTile extends StatelessWidget {
  const _GalleryImageTile({
    super.key,
    required this.record,
    required this.onTap,
  });

  final LocalImageRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fileName = path.basename(record.path);
    return Semantics(
      button: true,
      label: fileName,
      child: Material(
        color: ImageViewportSurface.background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pixelRatio = MediaQuery.devicePixelRatioOf(context);
              final cacheWidth = constraints.maxWidth.isFinite
                  ? (constraints.maxWidth * pixelRatio).ceil()
                  : null;
              return Stack(
                fit: StackFit.loose,
                children: [
                  Image.file(
                    File(record.path),
                    cacheWidth: cacheWidth,
                    fit: BoxFit.contain,
                    frameBuilder: (context, child, frame, synchronous) {
                      if (frame != null || synchronous) return child;
                      final width = record.metadata?.width ?? 1;
                      final height = record.metadata?.height ?? 1;
                      return AspectRatio(
                        aspectRatio: width > 0 && height > 0
                            ? width / height
                            : 1,
                        child: const Center(child: Icon(Icons.image_outlined)),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xB3000000)],
                        ),
                      ),
                      child: SizedBox(width: double.infinity, height: 52),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: record.isFavorite ? 32 : 8,
                    bottom: 7,
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  if (record.isFavorite)
                    const Positioned(
                      right: 8,
                      bottom: 7,
                      child: Icon(
                        Icons.favorite_rounded,
                        color: Colors.redAccent,
                        size: 17,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
