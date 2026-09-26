import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/user/user_subscription.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/cost_estimate_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/subscription_provider.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';
import 'package:nai_launcher/presentation/widgets/anlas/opus_stamina_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final bar = find.byKey(const ValueKey('opus-stamina-bar'));

  testWidgets('非 Opus、缺少额度数据或非 V5 模型时不显示体力条', (tester) async {
    for (final (subscription, model) in [
      (_subscription(tier: 2, percent: 86), ImageModels.animeDiffusionV5Full),
      (_subscription(tier: 3, percent: null), ImageModels.animeDiffusionV5Full),
      (_subscription(tier: 3, percent: 86), ImageModels.animeDiffusionV45Full),
    ]) {
      await tester.pumpWidget(_subject(subscription, model: model));
      await tester.pump();
      expect(bar, findsNothing, reason: '$model/${subscription.tier}');
    }
  });

  testWidgets('主界面只显示体力条本身，不显示文字', (tester) async {
    await tester.pumpWidget(_subject(_subscription(tier: 3, percent: 86)));
    await tester.pump();

    expect(bar, findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byType(Text)), findsNothing);
    final fill = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('opus-stamina-fill')),
    );
    expect(fill.widthFactor, closeTo(0.86, 1e-9));
    expect(
      tester.getSemantics(bar),
      isSemantics(
        label: 'V5 体力 86%，点按查看详情',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(tester.getSize(bar).height, greaterThanOrEqualTo(20));
  });

  testWidgets('超出上限时填满轨道并在 100% 处画分界线', (tester) async {
    await tester.pumpWidget(_subject(_subscription(tier: 3, percent: 130)));
    await tester.pump();

    final fill = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('opus-stamina-fill')),
    );
    expect(fill.widthFactor, 1);
    final capLine = find.descendant(
      of: bar,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 2,
      ),
    );
    expect(capLine, findsOneWidget);
  });

  testWidgets('点按体力条打开详情，展示估算张数、回充时间与本次消耗', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_subject(_subscription(tier: 3, percent: 86)));
    await tester.pump();

    await tester.tap(bar);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('opus-stamina-details')), findsOneWidget);
    expect(find.text('V5 体力'), findsOneWidget);
    expect(find.text('86%'), findsOneWidget);
    expect(find.text('约 1,488 张'), findsOneWidget);
    expect(find.text('1 小时 53 分'), findsOneWidget);
    expect(find.text('约 1 天 2 小时'), findsOneWidget);
    expect(find.text('体力'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('体力耗尽时轨道为空并说明改按 Anlas 计费', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _subject(_subscription(tier: 3, percent: 0, negative: true), cost: 30),
    );
    await tester.pump();

    final fill = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('opus-stamina-fill')),
    );
    expect(fill.widthFactor, 0);
    expect(
      tester.getSemantics(bar),
      isSemantics(
        label: 'V5 体力 已耗尽，点按查看详情',
        isButton: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('体力已耗尽，V5 生成改按 Anlas 计费；体力自动回充后恢复免费生成。'), findsOneWidget);
    expect(find.text('30 Anlas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

UserSubscription _subscription({
  required int tier,
  required double? percent,
  bool negative = false,
}) => UserSubscription(
  tier: tier,
  active: true,
  usage: percent == null
      ? null
      : OpusUsageInfo(
          percent: percent,
          isNegative: negative,
          timeUntilNextPercent: 6780,
        ),
);

Widget _subject(
  UserSubscription subscription, {
  String model = ImageModels.animeDiffusionV5Full,
  int cost = 0,
}) => ProviderScope(
  overrides: [
    subscriptionNotifierProvider.overrideWith(
      () => _FakeSubscriptionNotifier(subscription),
    ),
    generationParamsNotifierProvider.overrideWith(
      () => _FakeGenerationParamsNotifier(model),
    ),
    estimatedCostProvider.overrideWith((ref) => cost),
  ],
  child: MaterialApp(
    theme: AppTheme.getTheme(Brightness.light),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: app!,
    ),
    home: const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(padding: EdgeInsets.all(16), child: OpusStaminaBar()),
      ),
    ),
  ),
);

class _FakeSubscriptionNotifier extends SubscriptionNotifier {
  _FakeSubscriptionNotifier(this.subscription);

  final UserSubscription subscription;

  @override
  SubscriptionState build() => SubscriptionState.loaded(subscription);
}

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  _FakeGenerationParamsNotifier(this.model);

  final String model;

  @override
  ImageParams build() => ImageParams(model: model);
}
