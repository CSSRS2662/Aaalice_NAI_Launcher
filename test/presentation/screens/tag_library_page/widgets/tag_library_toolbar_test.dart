import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/tag_library_toolbar.dart';
import 'package:nai_launcher/presentation/widgets/common/icon_dropdown_selector.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_library_toolbar.dart';

import '../../../../helpers/light_theme_contrast.dart';

class _FakeTagLibraryPageNotifier extends TagLibraryPageNotifier {
  @override
  TagLibraryPageState build() => const TagLibraryPageState();

  @override
  void setSortBy(TagLibrarySortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  @override
  void setViewMode(TagLibraryViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }
}

void main() {
  tearDown(() => PlatformCapabilities.debugOverride = null);

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets('词库使用公共顶栏并保留全部能力 ${width.toInt()}px', (tester) async {
      PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
        TargetPlatform.windows,
      );
      await _pumpToolbar(tester, width: width);

      expect(find.byType(GalleryLibraryToolbar), findsOneWidget);
      expect(find.byType(GalleryLibrarySearchField), findsOneWidget);
      expect(
        find.byType(GalleryLibrarySortMenu<TagLibrarySortBy>),
        findsOneWidget,
      );
      expect(
        find.byType(IconDropdownSelector<TagLibraryViewMode>),
        findsOneWidget,
      );
      expect(find.text('分组'), findsOneWidget);
      expect(find.text('网格'), findsNothing);
      expect(find.text('2 列'), findsOneWidget);
      for (final label in ['分类', '多选', '导入', '导出', '文件夹', '添加条目']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('排序菜单切换 provider 状态', (tester) async {
    await _pumpToolbar(tester, width: 1180);

    await tester.tap(find.text('自定义排序'));
    await tester.pumpAndSettle();
    expect(find.text('更新时间'), findsOneWidget);
    await tester.tap(find.text('名称').last);
    await tester.pumpAndSettle();
    expect(find.text('名称'), findsOneWidget);
  });

  for (final width in [320.0, 1180.0]) {
    testWidgets('视图下拉选单在 ${width.toInt()}px 保留图标并切换状态', (tester) async {
      await _pumpToolbar(
        tester,
        width: width,
        interactionPolicy: width == 320
            ? InteractionPolicy.touchFirst
            : InteractionPolicy.neutral,
      );

      final selector = find.byKey(const Key('tag-library-view-mode-selector'));
      expect(
        tester.getSize(selector).height,
        greaterThanOrEqualTo(width == 320 ? 48 : 40),
      );

      await tester.tap(selector);
      await tester.pumpAndSettle();

      for (final icon in [
        Icons.grid_view_rounded,
        Icons.folder_copy_outlined,
      ]) {
        expect(find.byIcon(icon), findsWidgets);
      }
      expect(find.byIcon(Icons.view_list_rounded), findsNothing);
      expect(find.text('网格'), findsOneWidget);
      expect(find.text('分组'), findsNWidgets(2));

      await tester.tap(find.text('网格'));
      await tester.pumpAndSettle();

      expect(find.text('网格'), findsOneWidget);
      expect(find.text('分组'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('列数按钮在 1 到 3 列之间循环并记住选择', (tester) async {
    final storage = InMemoryLocalStorageService();
    await _pumpToolbar(tester, width: 1180, storage: storage);

    final button = find.byKey(const Key('tag-library-columns-button'));
    expect(find.text('2 列'), findsOneWidget);
    for (final expected in ['3 列', '1 列', '2 列', '3 列']) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
    expect(storage.getSetting<int>('tag_library_grid_columns'), 3);
  });

  testWidgets('分类与文件夹按钮转发顶栏操作', (tester) async {
    var categoryToggleCount = 0;
    var openFolderCount = 0;
    await _pumpToolbar(
      tester,
      width: 1180,
      onShowCategories: () => categoryToggleCount++,
      onOpenFolder: () => openFolderCount++,
    );

    await tester.tap(find.byKey(const Key('tag-library-categories-button')));
    await tester.tap(find.byKey(const Key('tag-library-folder-button')));

    expect(categoryToggleCount, 1);
    expect(openFolderCount, 1);
  });

  testWidgets('3x 文本保留完整可横向滚动操作区', (tester) async {
    PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
      TargetPlatform.windows,
    );
    await _pumpToolbar(tester, width: 320, textScale: 3);

    expect(
      find.byKey(const ValueKey('gallery-library-toolbar-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gallery-library-toolbar-actions')),
      findsOneWidget,
    );
    for (final label in ['分类', '多选', '导入', '导出', '文件夹', '添加条目']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  VoidCallback? onShowCategories,
  VoidCallback? onOpenFolder,
  InteractionPolicy? interactionPolicy,
  LocalStorageService? storage,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith(
          (ref) => storage ?? InMemoryLocalStorageService(),
        ),
        tagLibraryPageNotifierProvider.overrideWith(
          _FakeTagLibraryPageNotifier.new,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: InteractionPolicyScope(
              initialPolicy: interactionPolicy,
              child: Scaffold(
                body: TagLibraryToolbar(
                  onShowCategories: onShowCategories ?? () {},
                  onOpenFolder: onOpenFolder ?? () {},
                  onEnterSelectionMode: () {},
                  onImport: () {},
                  onExport: () {},
                  onAddEntry: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
