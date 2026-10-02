import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/stepped_slider.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

Widget _slider({
  required double Function() value,
  required ValueChanged<double> onChanged,
  double min = 1,
  double max = 30,
  double step = 1,
  int decimals = 0,
}) => StatefulBuilder(
  builder: (context, setState) => SteppedSlider(
    idPrefix: 'param',
    value: value(),
    min: min,
    max: max,
    step: step,
    decimals: decimals,
    onChanged: (next) => setState(() => onChanged(next)),
  ),
);

void main() {
  final increase = find.byKey(const ValueKey('param-increase'));
  final decrease = find.byKey(const ValueKey('param-decrease'));

  testWidgets('点按 −/+ 精确走一步，到边界后按钮失效', (tester) async {
    var value = 29.0;
    await tester.pumpWidget(
      _app(_slider(value: () => value, onChanged: (next) => value = next)),
    );

    await tester.tap(increase);
    await tester.pump();
    expect(value, 30);
    await tester.tap(increase);
    await tester.pump();
    expect(value, 30, reason: 'max reached, + is disabled');
    await tester.tap(decrease);
    await tester.pump();
    expect(value, 29);
    expect(tester.getSize(increase).height, greaterThanOrEqualTo(40));
    expect(
      tester.getSemantics(decrease),
      isSemantics(label: '减小', isButton: true, isEnabled: true),
    );
  });

  testWidgets('按住连续调整，越久越快，到边界或松手即停', (tester) async {
    var value = 20.0;
    await tester.pumpWidget(
      _app(_slider(value: () => value, onChanged: (next) => value = next)),
    );

    final hold = await tester.startGesture(tester.getCenter(increase));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    expect(value, 21, reason: 'the hold steps once right away');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 140));
    }
    expect(value, 27);
    await tester.pump(const Duration(milliseconds: 60));
    expect(value, 28, reason: 'repeats speed up');
    await hold.up();
    await tester.pump(const Duration(seconds: 1));
    expect(value, 28, reason: 'release stops');

    final again = await tester.startGesture(tester.getCenter(increase));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(seconds: 2));
    expect(value, 30, reason: 'stops at the bound');
    await again.up();
    await tester.pump();
  });

  testWidgets('小数步长不累积误差，输入的值按步长对齐并限制在范围内', (tester) async {
    var value = 5.0;
    await tester.pumpWidget(
      _app(
        _slider(
          value: () => value,
          onChanged: (next) => value = next,
          max: 20,
          step: 0.1,
          decimals: 1,
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(increase);
      await tester.pump();
    }
    expect(value, 5.3);

    final field = find.byKey(const ValueKey('param-value'));
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      '7.24',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(value, 7.2);

    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      '99',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(value, 20);
  });

  testWidgets('鼠标与触屏都能点按步进', (tester) async {
    var value = 10.0;
    await tester.pumpWidget(
      _app(_slider(value: () => value, onChanged: (next) => value = next)),
    );
    await tester.tap(decrease, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(value, 9);
    expect(tester.takeException(), isNull);
  });
}
