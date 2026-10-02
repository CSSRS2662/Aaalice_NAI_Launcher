import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/services/gallery/gallery_filter_service.dart';
import 'package:nai_launcher/data/services/gallery/unified_gallery_service.dart';
import 'package:nai_launcher/presentation/providers/image_favorite_status_provider.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';

void main() {
  late _PagedGalleryService service;

  setUp(() => service = _PagedGalleryService(total: 120));

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        galleryServiceProvider.overrideWith(() => _StubGalleryService(service)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  List<String> paths(ProviderContainer container) => container
      .read(localGalleryNotifierProvider)
      .currentImages
      .map((record) => record.path)
      .toList();

  group('continuous paging', () {
    test('loadMore 追加下一页，到最后一页后不再请求', () async {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);
      await notifier.initialize();
      expect(paths(container), hasLength(50));

      await notifier.loadMore();
      expect(paths(container), hasLength(100));
      expect(paths(container).last, 'img_99');
      expect(container.read(localGalleryNotifierProvider).currentPage, 1);

      await notifier.loadMore();
      expect(paths(container), hasLength(120));
      service.loadedPages.clear();
      await notifier.loadMore();
      expect(service.loadedPages, isEmpty);
    });

    test('删除、刷新等重取当前页时保留已追加的全部页', () async {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);
      await notifier.initialize();
      await notifier.loadMore();
      service.loadedPages.clear();

      await notifier.loadPage(1, showLoading: false);

      expect(service.loadedPages, [0, 1]);
      expect(paths(container), hasLength(100));
      expect(paths(container).first, 'img_0');
    });

    test('跳到其他页时回到单页', () async {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);
      await notifier.initialize();
      await notifier.loadMore();

      await notifier.loadPage(0);
      expect(paths(container), hasLength(50));

      // The window is gone: reloading page 0 fetches page 0 alone.
      service.loadedPages.clear();
      await notifier.loadPage(0, showLoading: false);
      expect(service.loadedPages, [0]);
    });
  });

  group('shared favorite status', () {
    test('切换收藏写入共享状态，任何地方都能读到', () async {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);
      await notifier.initialize();

      await notifier.toggleFavorite(r'G:\gallery\fresh.png');

      expect(
        container.read(imageFavoriteStatusProvider).values.single,
        isTrue,
        reason: 'recorded even though the image is not on the loaded page',
      );
    });

    test('按需读取一次；读取失败不记录，下次再试', () async {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);
      service.favoriteError = StateError('index busy');

      await notifier.loadFavoriteStatus(r'G:\gallery\a.png');
      expect(container.read(imageFavoriteStatusProvider), isEmpty);

      service.favoriteError = null;
      service.favorites.add(r'G:\gallery\a.png');
      await notifier.loadFavoriteStatus(r'G:\gallery\a.png');
      expect(container.read(imageFavoriteStatusProvider).values.single, isTrue);
    });

    testWidgets('别处收藏后，显示同一张图的心形随之填充', (tester) async {
      final container = createContainer();
      const path = r'G:\gallery\fresh.png';
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) =>
                  Text(watchImageFavorite(ref, path) ? 'filled' : 'empty'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('empty'), findsOneWidget);

      unawaited(
        container
            .read(localGalleryNotifierProvider.notifier)
            .toggleFavorite(path),
      );
      await tester.pumpAndSettle();
      expect(find.text('filled'), findsOneWidget);
    });
  });
}

class _PagedGalleryService extends Mock implements LocalGalleryService {
  _PagedGalleryService({required this.total});

  final int total;
  final loadedPages = <int>[];
  final favorites = <String>{};
  Object? favoriteError;

  @override
  bool get isInitialized => true;

  @override
  int get totalCount => total;

  @override
  int get filteredCount => total;

  @override
  FilterCriteria get currentFilter => const FilterCriteria();

  @override
  Future<void> applyFilter(FilterCriteria criteria) async {}

  @override
  Future<List<LocalImageRecord>> getPage(int page, {int? pageSize}) async {
    loadedPages.add(page);
    final size = pageSize ?? 50;
    final start = page * size;
    if (start >= total) return const [];
    final end = start + size > total ? total : start + size;
    return [
      for (var i = start; i < end; i++)
        LocalImageRecord(path: 'img_$i', size: 0, modifiedAt: DateTime(2026)),
    ];
  }

  @override
  Future<bool> toggleFavorite(String filePath) async =>
      favorites.add(filePath) || !favorites.remove(filePath);

  @override
  Future<bool> isFavorite(String filePath) async {
    final error = favoriteError;
    if (error != null) throw error;
    return favorites.contains(filePath);
  }

  @override
  Future<void> dispose() async {}
}

class _PendingGalleryService extends Mock implements LocalGalleryService {
  @override
  bool get isInitialized => false;
}

class _StubGalleryService extends GalleryService {
  _StubGalleryService(this.service);

  final LocalGalleryService service;
  Future<void>? _initialization;

  @override
  LocalGalleryService build() => _PendingGalleryService();

  @override
  Future<void> ensureInitialized() =>
      _initialization ??= Future(() => state = service);
}
