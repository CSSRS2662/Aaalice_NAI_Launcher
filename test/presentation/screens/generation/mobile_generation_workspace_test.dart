import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_state.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_tab_bar.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_view.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Finder tabFinder(MobileWorkbenchTab tab) =>
      find.byKey(ValueKey('mobile-workbench-tab-${tab.name}'));
  final paneSlot = find.byKey(const ValueKey('mobile-workbench-pane-slot'));
  final thumb = find.byKey(const ValueKey('mobile-workbench-tab-thumb'));

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
    // Same height as the header pills; each tab is a full-height target.
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile-workbench-tab-bar')))
          .height,
      44,
    );
    for (final tab in MobileWorkbenchTab.values) {
      expect(tester.getSize(tabFinder(tab)).height, 44);
    }
    for (final tab in MobileWorkbenchTab.values) {
      await tester.tap(tabFinder(tab));
    }
    expect(selections, MobileWorkbenchTab.values);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 3.0]) {
      testWidgets(
        '页签栏在 ${width.toInt()} 宽与 ${scale.toInt()} 倍文字下等分整行、不横向滚动',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 240));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final selections = <MobileWorkbenchTab>[];

          await tester.pumpWidget(
            _subject(
              textScaler: TextScaler.linear(scale),
              child: MobileWorkbenchTabBar(
                selected: MobileWorkbenchTab.prompt,
                referenceCount: 12,
                hasUnseenResult: true,
                onSelected: selections.add,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollable), findsNothing);

          final bar = tester.getRect(
            find.byKey(const ValueKey('mobile-workbench-tab-bar')),
          );
          // _subject 两侧各留 12 的外边距，页签栏占满其余宽度。
          expect(bar.width, closeTo(width - 24, 0.5));
          final segments = [
            for (final tab in MobileWorkbenchTab.values)
              tester.getRect(tabFinder(tab)),
          ];
          // Tabs span the whole track; only the thumb is inset.
          expect(segments.first.left, closeTo(bar.left, 0.5));
          expect(segments.last.right, closeTo(bar.right, 0.5));
          expect(bar.height, 44);
          for (final segment in segments) {
            expect(segment.width, closeTo(segments.first.width, 0.01));
          }

          for (final tab in MobileWorkbenchTab.values) {
            expect(tabFinder(tab).hitTestable(), findsOneWidget);
            await tester.tap(tabFinder(tab));
          }
          expect(selections, MobileWorkbenchTab.values);
          expect(tester.takeException(), isNull);
        },
      );
    }
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
    final paramsRect = tester.getRect(tabFinder(MobileWorkbenchTab.params));
    expect(tester.getRect(thumb).left, closeTo(paramsRect.left, 0.5));
  });

  testWidgets('面板首次进入才构建，切换后保留各自状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_subject(child: const _ViewHarness()));
    await tester.pumpAndSettle();

    expect(find.text('pane-image 0'), findsOneWidget);
    // 提示词面板始终构建但不可见；历史面板从未进入，不应构建。
    expect(find.text('pane-prompt 0', skipOffstage: false), findsOneWidget);
    expect(find.text('pane-prompt 0'), findsNothing);
    expect(find.text('pane-history 0', skipOffstage: false), findsNothing);

    await tester.tap(tabFinder(MobileWorkbenchTab.params));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pane-params 0'));
    await tester.pump();
    await tester.tap(find.text('pane-params 1'));
    await tester.pumpAndSettle();
    expect(find.text('pane-params 2'), findsOneWidget);

    await tester.tap(tabFinder(MobileWorkbenchTab.history));
    await tester.pumpAndSettle();
    expect(find.text('pane-history 0'), findsOneWidget);
    expect(find.text('pane-params 2'), findsNothing);
    // 跳过的中间页签（参考）不会因为点按跳转而被构建。
    expect(
      find.text('pane-references 0', skipOffstage: false),
      findsNothing,
    );

    await tester.tap(tabFinder(MobileWorkbenchTab.params));
    await tester.pumpAndSettle();
    expect(find.text('pane-params 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('左右滑动切换相邻页签，选中底跟随手指并在首尾页回弹', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = GlobalKey<_ViewHarnessState>();

    await tester.pumpWidget(_subject(child: _ViewHarness(key: harness)));
    await tester.pumpAndSettle();
    final startThumb = tester.getRect(thumb).left;

    // 跟手：拖到一半时选中底位于两个页签之间，两侧面板同时可见。
    final gesture = await tester.startGesture(tester.getCenter(paneSlot));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump();
    final midThumb = tester.getRect(thumb).left;
    final segment = tester.getSize(tabFinder(MobileWorkbenchTab.image)).width;
    expect(midThumb, greaterThan(startThumb + 4));
    expect(midThumb, lessThan(startThumb + segment));
    expect(find.text('pane-image 0'), findsOneWidget);
    expect(find.text('pane-prompt 0'), findsOneWidget);
    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.prompt);
    expect(find.text('pane-prompt 0').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(thumb).left,
      closeTo(tester.getRect(tabFinder(MobileWorkbenchTab.prompt)).left, 0.5),
    );

    // 快速轻扫即使距离不足一半也切换。
    await tester.fling(paneSlot, const Offset(-90, 0), 1500);
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.params);

    // 慢速短距离拖动回到原页。
    await tester.timedDrag(
      paneSlot,
      const Offset(-100, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.params);
    expect(find.text('pane-params 0').hitTestable(), findsOneWidget);

    // 向右滑回到上一页；首页继续右滑只回弹。
    await tester.fling(paneSlot, const Offset(250, 0), 1500);
    await tester.pumpAndSettle();
    await tester.fling(paneSlot, const Offset(250, 0), 1500);
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.image);
    await tester.fling(paneSlot, const Offset(250, 0), 1500);
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.image);
    expect(find.text('pane-image 0').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手指落在未聚焦的文本框上也能横滑，滑块仍优先拖动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = GlobalKey<_ViewHarnessState>();
    var sliderValue = 0.2;

    await tester.pumpWidget(
      _subject(
        child: _ViewHarness(
          key: harness,
          initial: MobileWorkbenchTab.prompt,
          paneBuilder: (tab) => switch (tab) {
            MobileWorkbenchTab.prompt => const TextField(
              key: ValueKey('prompt-text'),
              maxLines: null,
              expands: true,
            ),
            MobileWorkbenchTab.params => StatefulBuilder(
              builder: (context, setState) => Center(
                child: Slider(
                  key: const ValueKey('params-slider'),
                  value: sliderValue,
                  onChanged: (value) => setState(() => sliderValue = value),
                ),
              ),
            ),
            _ => null,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 真机的触摸事件以几像素为步长连续上报，这里用小步长模拟：
    // 页签横滑在文本上的阈值更小，会先于文本拖动选择胜出。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('prompt-text'))),
    );
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(-8, 0));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.params);

    await tester.drag(
      find.byKey(const ValueKey('params-slider')),
      const Offset(-150, 0),
    );
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.params);
    expect(sliderValue, lessThan(0.2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('开关横滑（软键盘弹出收起）不重建面板，输入状态保留', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pump({required bool swipe}) => tester.pumpWidget(
      _subject(
        child: _ViewHarness(
          key: const ValueKey('harness'),
          initial: MobileWorkbenchTab.params,
          swipeEnabled: swipe,
        ),
      ),
    );

    await pump(swipe: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('pane-params 0'));
    await tester.pump();
    expect(find.text('pane-params 1'), findsOneWidget);

    await pump(swipe: false);
    await tester.pump();
    expect(find.text('pane-params 1'), findsOneWidget);
    await pump(swipe: true);
    await tester.pump();
    expect(find.text('pane-params 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('停用横滑时拖动不切换页签，点按页签仍可切换', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = GlobalKey<_ViewHarnessState>();

    await tester.pumpWidget(
      _subject(child: _ViewHarness(key: harness, swipeEnabled: false)),
    );
    await tester.pumpAndSettle();

    await tester.fling(paneSlot, const Offset(-250, 0), 1500);
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.image);

    await tester.tap(tabFinder(MobileWorkbenchTab.references));
    await tester.pumpAndSettle();
    expect(harness.currentState!.selected, MobileWorkbenchTab.references);
    expect(find.text('pane-references 0').hitTestable(), findsOneWidget);
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

class _ViewHarness extends StatefulWidget {
  const _ViewHarness({
    super.key,
    this.initial = MobileWorkbenchTab.image,
    this.swipeEnabled = true,
    this.paneBuilder,
  });

  final MobileWorkbenchTab initial;
  final bool swipeEnabled;
  final Widget? Function(MobileWorkbenchTab tab)? paneBuilder;

  @override
  State<_ViewHarness> createState() => _ViewHarnessState();
}

class _ViewHarnessState extends State<_ViewHarness> {
  late MobileWorkbenchTab selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 460,
      child: MobileWorkbenchView(
        tabs: MobileWorkbenchTab.values,
        selected: selected,
        onSelected: (tab) => setState(() => selected = tab),
        swipeEnabled: widget.swipeEnabled,
        eager: const {MobileWorkbenchTab.prompt},
        builders: {
          for (final tab in MobileWorkbenchTab.values)
            tab: (_) =>
                widget.paneBuilder?.call(tab) ?? _CounterPane(name: tab.name),
        },
      ),
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
