import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/enums/precise_ref_type.dart';
import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/data/models/precise_ref/precise_ref_library_entry.dart';
import 'package:nai_launcher/data/services/precise_ref_library_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/precise_ref_library_provider.dart';
import 'package:nai_launcher/presentation/screens/precise_ref_library/precise_ref_library_screen.dart';
import 'package:nai_launcher/presentation/screens/precise_ref_library/widgets/precise_ref_entry_edit_dialog.dart';
import 'package:nai_launcher/presentation/screens/precise_ref_library/widgets/precise_ref_selector_dialog.dart';
import 'package:nai_launcher/presentation/widgets/common/input_surface_container.dart';
import 'package:nai_launcher/presentation/widgets/common/pagination_bar.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_library_toolbar.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_sidebar.dart';
import 'package:nai_launcher/presentation/widgets/gallery/library_masonry_grid.dart';

void main() {
  setUp(() {
    PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
      TargetPlatform.android,
    );
  });
  tearDown(() => PlatformCapabilities.debugOverride = null);

  test('library masonry keeps two phone columns and one at narrow 3x text', () {
    expect(libraryMasonryColumns(320 - 24), 2);
    expect(libraryMasonryColumns(390 - 24), 2);
    expect(libraryMasonryColumns(320 - 24, textScale: 3), 1);
    expect(
      libraryMasonryColumns(1180 - 24),
      greaterThan(libraryMasonryColumns(600 - 24)),
    );
  });

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets(
      'non-empty precise reference library keeps search, filters and edit reachable at ${width.toInt()}px',
      (tester) async {
        await _setViewport(tester, Size(width, 800));
        await _pumpLibrary(tester);

        expect(find.text('目标参考'), findsOneWidget);
        expect(_preciseRefSearchField(), findsOneWidget);
        for (final key in [
          'precise-ref-scope-all',
          'precise-ref-scope-favorites',
          'precise-ref-type-chip',
          'precise-ref-library-sort-chip',
        ]) {
          final finder = find.byKey(Key(key));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder.hitTestable(), findsOneWidget, reason: key);
          expect(
            tester.getSize(finder).height,
            greaterThanOrEqualTo(44),
            reason: key,
          );
        }
        if (width < 840) {
          expect(
            find.byKey(const Key('precise-ref-library-category-sidebar')),
            findsNothing,
          );
          // 窄屏由类型条件替代分类侧栏：选中后只剩同类型条目，可一键清除。
          await tester.tap(find.byKey(const Key('precise-ref-type-chip')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('precise-ref-type-option-characterAndStyle')),
          );
          await tester.pumpAndSettle();
          expect(find.text('目标参考'), findsOneWidget);
          expect(find.text('其他参考'), findsNothing);
          final clear = find.byKey(const Key('precise-ref-type-clear'));
          await tester.ensureVisible(clear);
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(find.text('其他参考'), findsOneWidget);
        } else {
          expect(
            find.byKey(const Key('precise-ref-library-category-sidebar')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('precise-ref-sidebar-type-characterAndStyle')),
            findsOneWidget,
          );
        }
        expect(
          find.byKey(const Key('precise-ref-library-unified-toolbar')),
          findsOneWidget,
        );
        for (final key in [
          'precise-ref-library-select-action',
          'precise-ref-library-import-button',
          'precise-ref-library-more-action',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget);
        }
        // 导出、刷新等低频操作收进“更多”菜单。
        expect(find.text('刷新'), findsNothing);
        await tester.tap(
          find.byKey(const Key('precise-ref-library-more-action')),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'precise-ref-library-more-export',
          'precise-ref-library-more-refresh',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        if (width >= 1050) {
          final titleRect = tester.getRect(
            find.byKey(const Key('precise-ref-library-page-title')),
          );
          final countRect = tester.getRect(
            find.byType(GalleryLibraryCountBadge),
          );
          final searchRect = tester.getRect(
            find.byKey(const Key('precise-ref-library-search-surface')),
          );
          expect(countRect.left - titleRect.right, 8);
          expect(
            searchRect.left - countRect.right,
            GalleryCollectionChrome.toolbarGroupGap,
          );
        }
        if (width == 1600) {
          const toolbarKey = Key('precise-ref-library-unified-toolbar');
          expect(
            tester.getSize(find.byKey(toolbarKey)).height,
            GalleryCollectionChrome.toolbarHeight,
          );
          expect(
            find.descendant(
              of: find.byKey(toolbarKey),
              matching: find.text('精准参考库'),
            ),
            findsOneWidget,
          );
          expect(tester.getTopLeft(find.byKey(toolbarKey)).dx, 0);
          expect(tester.getSize(find.byKey(toolbarKey)).width, 1600);
        }
        // 手机上连续滚动，不显示分页条。
        expect(find.byType(PaginationBar), findsNothing);

        await tester.enterText(_preciseRefSearchField(), '目标');
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('目标参考'), findsOneWidget);
        expect(find.text('其他参考'), findsNothing);

        await tester.tap(
          find.byKey(const Key('precise-ref-card-more-target-ref')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithIcon(ListTile, Icons.edit_outlined));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('precise-ref-edit-dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('precise-ref-edit-confirm')),
          findsOneWidget,
        );
        final surfaceKey = switch (width) {
          < 600 => 'adaptive-bottom-sheet',
          _ => 'adaptive-centered-form',
        };
        final surface = find.byKey(ValueKey(surfaceKey));
        expect(surface, findsOneWidget);
        if (width >= 840) {
          expect(tester.getSize(surface).width, lessThanOrEqualTo(440));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'shared pagination slices the precise reference grid and changes pages',
    (tester) async {
      PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
        TargetPlatform.windows,
      );
      await _setViewport(tester, const Size(1180, 800));
      await _pumpLibrary(tester, notifier: _ManyPreciseRefNotifier.new);

      expect(find.byKey(const Key('precise-ref-card-entry-0')), findsOneWidget);
      expect(find.byKey(const Key('precise-ref-card-entry-50')), findsNothing);
      final pagination = tester.widget<PaginationBar>(
        find.byKey(const Key('precise-ref-library-pagination')),
      );
      expect(pagination.totalPages, 2);
      pagination.onPageChanged(1);
      await tester.pump();
      expect(find.byKey(const Key('precise-ref-card-entry-0')), findsNothing);
      expect(
        find.byKey(const Key('precise-ref-card-entry-50')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phones scroll the whole library without a page bar', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 800));
    await _pumpLibrary(tester, notifier: _ManyPreciseRefNotifier.new);

    expect(find.byType(PaginationBar), findsNothing);
    expect(find.byKey(const Key('precise-ref-card-entry-0')), findsOneWidget);
    final last = find.byKey(const Key('precise-ref-card-entry-50'));
    await tester.scrollUntilVisible(
      last,
      400,
      scrollable: find
          .descendant(
            of: find.byType(LibraryMasonryGrid),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(last, findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px 3x text selector remains searchable and confirms a local selection above IME',
    (tester) async {
      await _setViewport(
        tester,
        const Size(320, 720),
        padding: const FakeViewPadding(top: 24, bottom: 24),
        viewInsets: const FakeViewPadding(bottom: 180),
      );
      List<PreciseRefLibraryEntry>? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preciseRefLibraryNotifierProvider.overrideWith(
              _PopulatedPreciseRefNotifier.new,
            ),
            preciseRefLibraryStorageServiceProvider.overrideWithValue(
              _ThumbnailFreeStorage(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await PreciseRefSelectorDialog.show(context);
                  },
                  child: const Text('打开选择器'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开选择器'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adaptive-bottom-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('precise-ref-selector-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('precise-ref-selector-type-scroll')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('adaptive-bottom-sheet')))
            .dy,
        greaterThanOrEqualTo(24),
      );
      expect(
        tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );

      final search = find.byKey(const Key('precise-ref-selector-search'));
      await tester.enterText(search, '参考');
      await tester.pump(const Duration(milliseconds: 250));
      final typeChip = find.byKey(const Key('precise-ref-selector-type-chip'));
      await tester.ensureVisible(typeChip);
      await tester.tap(typeChip);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key('precise-ref-selector-type-option-characterAndStyle'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('precise-ref-selector-item-other-ref')),
        findsNothing,
      );

      final item = find.byKey(
        const Key('precise-ref-selector-item-target-ref'),
      );
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pump();
      final confirm = find.byKey(const Key('precise-ref-selector-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result?.map((entry) => entry.id), ['target-ref']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, surfaceKey) in [
    (700.0, 'adaptive-centered-form'),
    (1200.0, 'adaptive-centered-form'),
  ]) {
    testWidgets('${width.toInt()}px selector uses a bounded adaptive surface', (
      tester,
    ) async {
      await _setViewport(tester, Size(width, 900));
      await _pumpSelectorHost(tester);

      await tester.tap(find.text('打开选择器'));
      await tester.pumpAndSettle();

      final surface = find.byKey(ValueKey(surfaceKey));
      expect(surface, findsOneWidget);
      expect(tester.getSize(surface).width, lessThan(width));
      expect(tester.getSize(surface).height, lessThan(760));
      expect(
        find.byKey(const Key('precise-ref-selector-search')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('precise-ref-selector-type-scroll')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320px 3x text keeps export selection controls reachable', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 720));
    await _pumpSelectorHost(
      tester,
      purpose: PreciseRefSelectorPurpose.export,
      textScale: 3,
    );

    await tester.tap(find.text('打开选择器'));
    await tester.pumpAndSettle();

    expect(find.textContaining('一个 .naipreciseref 文件'), findsOneWidget);
    final deselectAll = find.byKey(
      const Key('precise-ref-export-deselect-all'),
    );
    await tester.ensureVisible(deselectAll);
    await tester.tap(deselectAll);
    await tester.pump();

    final selectAll = find.byKey(const Key('precise-ref-export-select-all'));
    await tester.ensureVisible(selectAll);
    await tester.tap(selectAll);
    await tester.pump();
    final confirm = find.byKey(const Key('precise-ref-selector-confirm'));
    await tester.ensureVisible(confirm);
    expect(find.text('导出所选 (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('precise reference toolbar uses the outward export icon', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1180, 800));
    await _pumpLibrary(tester);

    await tester.tap(find.byKey(const Key('precise-ref-library-more-action')));
    await tester.pumpAndSettle();
    final exportButton = find.byKey(
      const Key('precise-ref-library-more-export'),
    );
    expect(
      find.descendant(
        of: exportButton,
        matching: find.byIcon(Icons.file_upload_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: exportButton,
        matching: find.byIcon(Icons.file_download_outlined),
      ),
      findsNothing,
    );
  });

  testWidgets(
    '320px 3x text with SafeArea and IME keeps the edit form scrollable and submittable',
    (tester) async {
      await _setViewport(
        tester,
        const Size(320, 720),
        padding: const FakeViewPadding(top: 24, bottom: 24),
        viewInsets: const FakeViewPadding(bottom: 220),
      );
      PreciseRefEntryEditResult? result;
      final entry = _PopulatedPreciseRefNotifier.entries.first;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await PreciseRefEntryEditDialog.show(context, entry);
                },
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开编辑'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('adaptive-bottom-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('precise-ref-edit-type-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('precise-ref-edit-strength-field')),
        findsOneWidget,
      );
      expect(find.text('取消'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      final confirm = find.byKey(const Key('precise-ref-edit-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(result?.name, entry.name);
      expect(result?.type, entry.type);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop search focus keeps the pill radius and geometry stable',
    (tester) async {
      await _setViewport(tester, const Size(1180, 800));
      await _pumpLibrary(
        tester,
        interactionPolicy: const InteractionPolicy(
          modality: InteractionModality.pointer,
          touchAvailable: false,
          precisePointerAvailable: true,
        ),
      );

      const surfaceKey = Key('precise-ref-library-search-surface');
      final field = _preciseRefSearchField();
      final surface = tester.widget<InputSurfaceContainer>(
        find.descendant(
          of: find.byKey(surfaceKey),
          matching: find.byType(InputSurfaceContainer),
        ),
      );
      final restingRect = tester.getRect(find.byKey(surfaceKey));

      expect(surface.height, 36);
      expect(surface.borderRadius, 18);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(1100, 700));
      await mouse.moveTo(tester.getCenter(field));
      await mouse.down(tester.getCenter(field));
      await mouse.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byKey(surfaceKey)), restingRect);
      final focusedDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(surfaceKey),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(focusedDecoration.borderRadius, BorderRadius.circular(18));
      expect(
        (focusedDecoration.border! as Border).top.color.a,
        closeTo(0.38, 0.01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop toolbar keeps scope, type and sort filters inline', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1180, 800));
    await _pumpLibrary(
      tester,
      interactionPolicy: const InteractionPolicy(
        modality: InteractionModality.pointer,
        touchAvailable: false,
        precisePointerAvailable: true,
      ),
    );

    expect(find.byType(GalleryLibraryToolbar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-library-toolbar-desktop')),
      findsOneWidget,
    );
    final searchCenter = tester
        .getCenter(find.byKey(const Key('precise-ref-library-search-surface')))
        .dy;
    for (final key in [
      'precise-ref-scope-favorites',
      'precise-ref-type-chip',
      'precise-ref-library-sort-chip',
      'precise-ref-library-import-button',
    ]) {
      expect(
        tester.getCenter(find.byKey(Key(key))).dy,
        closeTo(searchCenter, 0.5),
        reason: key,
      );
    }
    expect(
      tester
          .getSize(find.byKey(const Key('precise-ref-library-unified-toolbar')))
          .height,
      GalleryCollectionChrome.toolbarHeight,
    );
    await tester.tap(find.byKey(const Key('precise-ref-scope-favorites')));
    await tester.pumpAndSettle();
    expect(find.text('目标参考'), findsOneWidget);
    expect(find.text('其他参考'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px 3x text with SafeArea and IME keeps filtering and edit fields reachable',
    (tester) async {
      await _setViewport(
        tester,
        const Size(320, 720),
        padding: const FakeViewPadding(top: 24, bottom: 24),
        viewInsets: const FakeViewPadding(bottom: 220),
      );
      await _pumpLibrary(tester, textScale: 3);

      final search = _preciseRefSearchField();
      await tester.tap(search);
      await tester.enterText(search, '目标');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('目标参考'), findsOneWidget);
      expect(
        find.byKey(const Key('precise-ref-library-import-button')),
        findsOneWidget,
      );
      final typeChip = find.byKey(const Key('precise-ref-type-chip'));
      await tester.ensureVisible(typeChip);
      await tester.pumpAndSettle();
      expect(typeChip.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  FakeViewPadding? padding,
  FakeViewPadding? viewInsets,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding ?? const FakeViewPadding();
  tester.view.viewInsets = viewInsets ?? const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewInsets();
  });
}

Future<void> _pumpSelectorHost(
  WidgetTester tester, {
  PreciseRefSelectorPurpose purpose = PreciseRefSelectorPurpose.add,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preciseRefLibraryNotifierProvider.overrideWith(
          _PopulatedPreciseRefNotifier.new,
        ),
        preciseRefLibraryStorageServiceProvider.overrideWithValue(
          _ThumbnailFreeStorage(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  PreciseRefSelectorDialog.show(context, purpose: purpose),
              child: const Text('打开选择器'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  double textScale = 1,
  PreciseRefLibraryNotifier Function()? notifier,
  InteractionPolicy interactionPolicy = InteractionPolicy.touchFirst,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preciseRefLibraryNotifierProvider.overrideWith(
          notifier ?? _PopulatedPreciseRefNotifier.new,
        ),
        preciseRefLibraryStorageServiceProvider.overrideWithValue(
          _ThumbnailFreeStorage(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: InteractionPolicyScope(
          initialPolicy: interactionPolicy,
          child: const PreciseRefLibraryScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _preciseRefSearchField() => find.descendant(
  of: find.byKey(const Key('precise-ref-library-search-surface')),
  matching: find.byType(TextField),
);

class _PopulatedPreciseRefNotifier extends PreciseRefLibraryNotifier {
  static final entries = [
    PreciseRefLibraryEntry(
      id: 'target-ref',
      name: '目标参考',
      imagePath: 'target.png',
      typeIndex: PreciseRefType.characterAndStyle.index,
      isFavorite: true,
      createdAt: DateTime(2026),
    ),
    PreciseRefLibraryEntry(
      id: 'other-ref',
      name: '其他参考',
      imagePath: 'other.png',
      typeIndex: PreciseRefType.style.index,
      createdAt: DateTime(2026),
    ),
  ];

  @override
  PreciseRefLibraryState build() =>
      PreciseRefLibraryState(entries: entries, filteredEntries: entries);

  @override
  Future<void> initialize() async {}
}

class _ManyPreciseRefNotifier extends PreciseRefLibraryNotifier {
  static final entries = List.generate(
    51,
    (index) => PreciseRefLibraryEntry(
      id: 'entry-$index',
      name: '参考 $index',
      imagePath: '$index.png',
      typeIndex: PreciseRefType.character.index,
      createdAt: DateTime(2026, 1, 1).add(Duration(minutes: index)),
    ),
  );

  @override
  PreciseRefLibraryState build() =>
      PreciseRefLibraryState(entries: entries, filteredEntries: entries);

  @override
  Future<void> initialize() async {}
}

class _ThumbnailFreeStorage extends PreciseRefLibraryStorageService {
  @override
  Uint8List? peekDisplayThumbnail(String id) => null;

  @override
  Future<Uint8List?> getDisplayThumbnail(
    String id, {
    bool Function()? isCancelled,
  }) async => null;
}
