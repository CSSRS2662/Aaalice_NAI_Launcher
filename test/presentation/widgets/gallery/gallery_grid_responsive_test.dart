import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/online_gallery/online_gallery_masonry_layout.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_grid.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_image_card_3d.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  late Duration previousVisibilityInterval;

  setUp(() {
    previousVisibilityInterval =
        VisibilityDetectorController.instance.updateInterval;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() {
    VisibilityDetectorController.instance.updateInterval =
        previousVisibilityInterval;
  });

  const cases = <(double, int)>[
    (320, 2),
    (360, 2),
    (600, 3),
    (840, 4),
    (1180, 6),
    (1600, 8),
  ];

  for (final (width, columns) in cases) {
    testWidgets(
      'grid fills ${width.toInt()}px with $columns responsive columns',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await _pumpGrid(tester, columns: columns, selectedIndices: const {0});

        final delegate =
            tester.widget<GridView>(find.byType(GridView)).gridDelegate
                as OnlineGalleryMasonryGridDelegate;
        expect(delegate.snapshot.columnCount, columns);

        final firstCard = tester.widget<LocalImageCard3D>(
          find.byType(LocalImageCard3D).first,
        );
        final expectedWidth = (width - 24 - 12 * (columns - 1)) / columns;
        expect(firstCard.width, closeTo(expectedWidth, 0.001));
        expect(firstCard.isSelected, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('瀑布流按元数据宽高比完整显示每张图，放进更短的一列', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    LocalImageRecord record(String name, int width, int height) =>
        LocalImageRecord(
          path: 'G:/gallery/$name.png',
          size: width * height,
          modifiedAt: DateTime(2026, 8, 1),
          metadata: NaiImageMetadata(width: width, height: height),
        );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GalleryGrid(
              images: [
                record('portrait', 832, 1216),
                record('landscape', 1216, 832),
                record('square', 1024, 1024),
              ],
              columns: 2,
              spacing: 12,
              padding: const EdgeInsets.all(12),
              enableDrag: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final cards = {
      for (final card in tester.widgetList<LocalImageCard3D>(
        find.byType(LocalImageCard3D),
      ))
        card.record.path.split('/').last: card,
    };
    Rect rectOf(String name) =>
        tester.getRect(find.byWidget(cards['$name.png']!));

    for (final (name, ratio) in [
      ('portrait', 832 / 1216),
      ('landscape', 1216 / 832),
      ('square', 1.0),
    ]) {
      final card = cards['$name.png']!;
      expect(card.width, closeTo((390 - 24 - 12) / 2, 0.001));
      expect(card.width / card.height!, closeTo(ratio, 0.001), reason: name);
    }
    expect(
      rectOf('portrait').left,
      isNot(closeTo(rectOf('landscape').left, 1)),
    );
    expect(rectOf('square').left, closeTo(rectOf('landscape').left, 0.5));
    expect(rectOf('square').top, greaterThan(rectOf('landscape').bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection and scroll offset survive a responsive resize', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpGrid(tester, columns: 3, selectedIndices: const {0, 20});
    await tester.drag(find.byType(GridView), const Offset(0, -900));
    await tester.pump();

    final beforeResize = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .pixels;
    expect(beforeResize, greaterThan(0));

    await tester.binding.setSurfaceSize(const Size(840, 500));
    await tester.pump();

    final afterResize = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .pixels;
    expect(afterResize, closeTo(beforeResize, 0.001));

    tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
    await tester.pump();
    final firstCard = tester.widget<LocalImageCard3D>(
      find.byType(LocalImageCard3D).first,
    );
    expect(firstCard.record.path, 'G:/gallery/image-0.png');
    expect(firstCard.isSelected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid scroll state survives switching to grouped-list mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _GridToggleHarness(),
        ),
      ),
    );
    await tester.drag(find.byType(GridView), const Offset(0, -900));
    await tester.pump();
    final beforeSwitch = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .pixels;
    expect(beforeSwitch, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('toggle-grid-mode')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('grouped-list-placeholder')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('toggle-grid-mode')));
    await tester.pump();
    final afterSwitch = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .pixels;
    expect(afterSwitch, closeTo(beforeSwitch, 0.001));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpGrid(
  WidgetTester tester, {
  required int columns,
  Set<int>? selectedIndices,
}) async {
  final images = List.generate(
    60,
    (index) => LocalImageRecord(
      path: 'G:/gallery/image-$index.png',
      size: index + 1,
      modifiedAt: DateTime(2026, 8, 1),
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GalleryGrid(
            images: images,
            columns: columns,
            spacing: 12,
            padding: const EdgeInsets.all(12),
            selectedIndices: selectedIndices,
            enableDrag: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _GridToggleHarness extends StatefulWidget {
  const _GridToggleHarness();

  @override
  State<_GridToggleHarness> createState() => _GridToggleHarnessState();
}

class _GridToggleHarnessState extends State<_GridToggleHarness> {
  bool grouped = false;

  @override
  Widget build(BuildContext context) {
    final images = List.generate(
      60,
      (index) => LocalImageRecord(
        path: 'G:/gallery/toggle-$index.png',
        size: index + 1,
        modifiedAt: DateTime(2026, 8, 1),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const ValueKey('toggle-grid-mode'),
            onPressed: () => setState(() => grouped = !grouped),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
      body: grouped
          ? const Center(
              key: ValueKey('grouped-list-placeholder'),
              child: Text('Grouped list'),
            )
          : GalleryGrid(
              key: const PageStorageKey<String>('gallery-grid'),
              images: images,
              columns: 3,
              spacing: 12,
              padding: const EdgeInsets.all(12),
              enableDrag: false,
            ),
    );
  }
}
