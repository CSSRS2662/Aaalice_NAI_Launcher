import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_panes.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_state.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_tab_bar.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Finder tabFinder(MobileWorkbenchTab tab) =>
      find.byKey(ValueKey('mobile-workbench-tab-${tab.name}'));

  testWidgets('页签栏在 390 宽度下五个页签等宽且全部可点', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selections = <MobileWorkbenchTab>[];

    await tester.pumpWidget(
      _subject(
        child: MobileWorkbenchTabBar(
          selected: MobileWorkbenchTab.image,
          onSelected: selections.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final widths = {
      for (final tab in MobileWorkbenchTab.values)
        tester.getSize(tabFinder(tab)).width,
    };
    expect(widths, hasLength(1));
    for (final label in ['图像', '提示词', '参数', '参考', '历史']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-workbench-tab-bar'))),
      isA<Size>().having((size) => size.height, 'height', greaterThan(44)),
    );
    for (final tab in MobileWorkbenchTab.values) {
      await tester.tap(tabFinder(tab));
    }
    expect(selections, MobileWorkbenchTab.values);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('页签栏在 ${width.toInt()} 宽与 3 倍文字下不溢出且每个页签可达', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 240));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final selections = <MobileWorkbenchTab>[];

      await tester.pumpWidget(
        _subject(
          textScaler: const TextScaler.linear(3),
          child: MobileWorkbenchTabBar(
            selected: MobileWorkbenchTab.prompt,
            referenceCount: 2,
            hasUnseenResult: true,
            onSelected: selections.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final tab in MobileWorkbenchTab.values) {
        await tester.ensureVisible(tabFinder(tab));
        await tester.pumpAndSettle();
        expect(tabFinder(tab).hitTestable(), findsOneWidget);
        await tester.tap(tabFinder(tab));
      }
      expect(selections, MobileWorkbenchTab.values);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('参考页签显示生效数量，图像页签在未查看时显示新结果标记', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pump(MobileWorkbenchTab selected) => tester.pumpWidget(
      _subject(
        child: MobileWorkbenchTabBar(
          selected: selected,
          referenceCount: 3,
          hasUnseenResult: true,
          onSelected: (_) {},
        ),
      ),
    );

    await pump(MobileWorkbenchTab.prompt);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: tabFinder(MobileWorkbenchTab.references),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-workbench-unseen-dot')),
      findsOneWidget,
    );

    await pump(MobileWorkbenchTab.image);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-workbench-unseen-dot')),
      findsNothing,
    );
  });

  testWidgets('宽横屏只显示编辑类页签，选中底对齐当前页签', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _subject(
        child: MobileWorkbenchTabBar(
          selected: MobileWorkbenchTab.params,
          tabs: MobileWorkbenchTabBar.editingTabs,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tabFinder(MobileWorkbenchTab.image), findsNothing);
    final thumb = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    final paramsRect = tester.getRect(tabFinder(MobileWorkbenchTab.params));
    final barRect = tester.getRect(
      find.byKey(const ValueKey('mobile-workbench-tab-bar')),
    );
    expect(thumb.left, closeTo(paramsRect.left - barRect.left - 4, 0.5));
  });

  testWidgets('面板首次进入才构建，切换后保留各自状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_subject(child: const _PanesHarness()));
    await tester.pumpAndSettle();

    expect(find.text('pane-image 0'), findsOneWidget);
    // 提示词面板始终构建但不可见；历史面板从未进入，不应构建。
    expect(find.text('pane-prompt 0', skipOffstage: false), findsOneWidget);
    expect(find.text('pane-history 0', skipOffstage: false), findsNothing);

    await tester.tap(find.text('go-params'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pane-params 0'));
    await tester.pump();
    await tester.tap(find.text('pane-params 1'));
    await tester.pumpAndSettle();
    expect(find.text('pane-params 2'), findsOneWidget);

    await tester.tap(find.text('go-history'));
    await tester.pumpAndSettle();
    expect(find.text('pane-history 0'), findsOneWidget);
    expect(find.text('pane-params 2'), findsNothing);

    await tester.tap(find.text('go-params'));
    await tester.pumpAndSettle();
    expect(find.text('pane-params 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _subject({required Widget child, TextScaler? textScaler}) => MaterialApp(
  theme: AppTheme.getTheme(Brightness.light),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: textScaler, disableAnimations: true),
    child: app!,
  ),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  ),
);

class _PanesHarness extends StatefulWidget {
  const _PanesHarness();

  @override
  State<_PanesHarness> createState() => _PanesHarnessState();
}

class _PanesHarnessState extends State<_PanesHarness> {
  MobileWorkbenchTab _selected = MobileWorkbenchTab.image;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _selected = MobileWorkbenchTab.params),
              child: const Text('go-params'),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _selected = MobileWorkbenchTab.history),
              child: const Text('go-history'),
            ),
          ],
        ),
        SizedBox(
          height: 300,
          child: MobileWorkbenchPanes(
            selected: _selected,
            eager: const {MobileWorkbenchTab.prompt},
            builders: {
              for (final tab in MobileWorkbenchTab.values)
                tab: (_) => _CounterPane(name: tab.name),
            },
          ),
        ),
      ],
    );
  }
}

class _CounterPane extends StatefulWidget {
  const _CounterPane({required this.name});

  final String name;

  @override
  State<_CounterPane> createState() => _CounterPaneState();
}

class _CounterPaneState extends State<_CounterPane> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => _count++),
      child: Text('pane-${widget.name} $_count'),
    ),
  );
}
