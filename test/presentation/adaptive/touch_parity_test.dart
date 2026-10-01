import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/screens/generation/generation_layout_policy.dart';
import 'package:nai_launcher/presentation/widgets/common/draggable_number_input.dart';
import 'package:nai_launcher/presentation/widgets/common/image_comparison_toolbar.dart';
import 'package:nai_launcher/presentation/widgets/shortcuts/shortcut_tooltip.dart';
import 'package:nai_launcher/presentation/widgets/tag_chip.dart';

const _touch = InteractionPolicy(
  modality: InteractionModality.touch,
  touchAvailable: true,
  precisePointerAvailable: false,
);
const _mouse = InteractionPolicy(
  modality: InteractionModality.pointer,
  touchAvailable: false,
  precisePointerAvailable: true,
);

// Keyed by policy so switching policies remounts the scope.
Widget _app(Widget child, {InteractionPolicy policy = _touch}) => ProviderScope(
  key: ValueKey(policy),
  child: InteractionPolicyScope(
    initialPolicy: policy,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  tearDown(() => PlatformCapabilities.debugOverride = null);

  group('生成页布局', () {
    bool desktop(Size size, {required bool touch}) =>
        usesDesktopGenerationLayout(size, touchDevice: touch);

    test('手机横屏等触屏矮屏保留移动工作台', () {
      expect(desktop(const Size(900, 380), touch: true), false);
      expect(desktop(const Size(411, 860), touch: true), false);
    });

    test('平板与桌面宽屏使用桌面工作区，桌面矮窗口不受影响', () {
      expect(desktop(const Size(1180, 800), touch: true), true);
      expect(desktop(const Size(1000, 500), touch: false), true);
      expect(desktop(const Size(700, 900), touch: false), false);
    });

    test('默认按平台判断是否触屏设备', () {
      PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
        TargetPlatform.android,
      );
      expect(usesDesktopGenerationLayout(const Size(900, 380)), false);
      PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
        TargetPlatform.windows,
      );
      expect(usesDesktopGenerationLayout(const Size(900, 380)), true);
    });
  });

  group('标签菜单', () {
    testWidgets('长按与右键都打开同一菜单，长按不再弹出提示', (tester) async {
      final positions = <Offset>[];
      await tester.pumpWidget(
        _app(
          SimpleTagChip(
            tag: 'long_hair',
            autoTranslate: false,
            tooltip: '长按可复制、加入黑名单或输出过滤',
            onMenu: positions.add,
          ),
        ),
      );

      await tester.longPress(find.text('long hair'));
      await tester.pumpAndSettle();
      expect(positions, hasLength(1));
      expect(find.text('长按可复制、加入黑名单或输出过滤'), findsNothing);

      await tester.tap(find.text('long hair'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(positions, hasLength(2));
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).triggerMode,
        TooltipTriggerMode.manual,
      );
    });
  });

  testWidgets('触屏隐藏“跟随鼠标”，鼠标下保留', (tester) async {
    Widget toolbar() => ImageComparisonToolbar(
      followMouse: false,
      onFollowMouseChanged: (_) {},
      showZoom: true,
      scale: 1,
      actualPixelScale: 2,
      onScaleChanged: (_) {},
      canUseActualPixels: true,
    );
    await tester.pumpWidget(_app(SizedBox(width: 600, child: toolbar())));
    expect(find.byKey(const ValueKey('comparison-follow-mouse')), findsNothing);
    expect(find.byKey(const ValueKey('comparison-fit-window')), findsOne);

    await tester.pumpWidget(
      _app(SizedBox(width: 600, child: toolbar()), policy: _mouse),
    );
    expect(find.byKey(const ValueKey('comparison-follow-mouse')), findsOne);
  });

  testWidgets('触屏横滑不会改动数量，鼠标拖动仍可调整', (tester) async {
    final values = <int>[];
    Widget input() =>
        DraggableNumberInput(value: 4, onChanged: values.add, max: 8);

    await tester.pumpWidget(_app(input()));
    await tester.drag(find.text('4'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(values, isEmpty);

    await tester.pumpWidget(_app(input(), policy: _mouse));
    await tester.drag(
      find.text('4'),
      const Offset(120, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(values, isNotEmpty);
  });

  testWidgets('手机上的按钮提示不显示快捷键', (tester) async {
    PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
      TargetPlatform.android,
    );
    await tester.pumpWidget(
      _app(
        const ShortcutTooltip(
          message: '刷新',
          shortcutId: 'refresh',
          child: SizedBox.square(dimension: 48),
        ),
      ),
    );
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, '刷新');
    expect(find.byType(ShortcutLabel), findsNothing);
  });
}
