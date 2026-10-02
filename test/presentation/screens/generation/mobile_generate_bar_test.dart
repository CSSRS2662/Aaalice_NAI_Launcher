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
import 'package:nai_launcher/presentation/screens/generation/mobile_generation_view_data.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_generate_bar.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final strip = find.byKey(const ValueKey('generation-mobile-status-strip'));
  final generate = find.byKey(const ValueKey('generation-mobile-generate'));

  testWidgets('额度条含体力百分比与余额；智能体、队列在生成按钮左侧', (tester) async {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 1.0), (320.0, 3.0)]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(_subject(textScale: scale));
      await tester.pump();
      final reason = '$width@$scale';

      expect(
        find.descendant(of: strip, matching: find.text('86%')),
        findsOne,
        reason: reason,
      );
      expect(
        find.descendant(of: strip, matching: find.text('9,993')),
        findsOne,
        reason: reason,
      );

      final generateRect = tester.getRect(generate);
      var previousRight = 0.0;
      for (final key in [
        'generation-add-current-to-queue',
        'generation-agent-drawer-action',
        'generation-mobile-queue-action',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(previousRight), reason: key);
        expect(rect.right, lessThanOrEqualTo(generateRect.left), reason: key);
        expect(rect.shortestSide, greaterThanOrEqualTo(44), reason: key);
        expect((rect.center.dy - generateRect.center.dy).abs(), lessThan(1));
        previousRight = rect.right;
      }
      expect(generateRect.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull, reason: reason);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('非 V5 时额度条只显示余额', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_subject(model: ImageModels.animeDiffusionV45Full));
    await tester.pump();
    expect(find.byKey(const ValueKey('opus-stamina-bar')), findsNothing);
    expect(find.descendant(of: strip, matching: find.text('9,993')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

Widget _subject({
  String model = ImageModels.animeDiffusionV5Full,
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    subscriptionNotifierProvider.overrideWith(_FakeSubscriptionNotifier.new),
    generationParamsNotifierProvider.overrideWith(
      () => _FakeGenerationParamsNotifier(model),
    ),
    estimatedCostProvider.overrideWith((ref) => 0),
  ],
  child: MaterialApp(
    theme: AppTheme.getTheme(Brightness.light),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: app!,
    ),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: MobileGenerateBar(
        data: const MobileGenerationViewData(
          batchStatus: (
            isGenerating: false,
            isPreparing: false,
            currentImage: 0,
            totalImages: 0,
          ),
          cooldownRemainingSeconds: 0,
          keyboardVisible: false,
          isGenerating: false,
          isLauncherGenerating: false,
          requiresLogin: false,
          showRandomTools: false,
          isUpscaleMode: false,
          randomModeEnabled: false,
        ),
        onGenerate: () {},
        onCancel: () {},
        onSkipCurrent: () {},
        onAddToQueue: () {},
        onOpenAgent: () {},
      ),
    ),
  ),
);

class _FakeSubscriptionNotifier extends SubscriptionNotifier {
  @override
  SubscriptionState build() => const SubscriptionState.loaded(
    UserSubscription(
      tier: 3,
      active: true,
      trainingStepsLeft: TrainingStepsInfo(fixedTrainingStepsLeft: 9993),
      usage: OpusUsageInfo(
        percent: 86,
        isNegative: false,
        timeUntilNextPercent: 6780,
      ),
    ),
  );
}

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  _FakeGenerationParamsNotifier(this.model);

  final String model;

  @override
  ImageParams build() => ImageParams(model: model);
}
