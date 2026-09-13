import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/app_version.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/warmup_provider.dart';
import 'package:nai_launcher/presentation/screens/splash/splash_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../helpers/flutter_error_collector.dart';

class _IdleWarmupNotifier extends WarmupNotifier {
  @override
  WarmupState build() => WarmupState.initial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Aaalice Pocket',
      packageName: 'nai_launcher',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppVersion.initialize();
  });

  testWidgets(
    'Splash keeps critical content reachable at 320 width with 3x text, IME, and SafeArea',
    (tester) async {
      final flutterErrors = FlutterErrorCollector.install(tester);
      addTearDown(flutterErrors.restoreAndAssertNoErrors);
      const size = Size(320, 760);
      const safePadding = EdgeInsets.only(top: 24, bottom: 16);
      const keyboardInset = 300.0;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            warmupNotifierProvider.overrideWith(_IdleWarmupNotifier.new),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(3),
                padding: safePadding,
                viewPadding: safePadding,
                viewInsets: const EdgeInsets.only(bottom: keyboardInset),
              ),
              child: child!,
            ),
            home: const SplashScreen(),
          ),
        ),
      );
      await tester.pump();

      flutterErrors.expectNoErrors(reason: 'initial splash layout');
      final scrollView = find.byKey(const ValueKey('splash_scroll_view'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: scrollView, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      final usableRect = Rect.fromLTRB(
        0,
        safePadding.top,
        size.width,
        size.height - keyboardInset,
      );
      expect(find.byKey(const ValueKey('splash-brand-art')), findsOneWidget);
      expect(find.text('NAI Launcher'), findsNothing);
      for (final content in [find.text('Aaalice Pocket'), find.text('0%')]) {
        await tester.ensureVisible(content);
        await tester.pump();
        expect(
          tester.getRect(content).intersect(usableRect).height,
          greaterThan(0),
          reason: '$content should be reachable above the IME',
        );
        flutterErrors.expectNoErrors(
          reason: '$content should remain reachable above the IME',
        );
      }
    },
  );

  testWidgets('Splash plays the pixel artist intro once and settles', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          warmupNotifierProvider.overrideWith(_IdleWarmupNotifier.new),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: SplashScreen(),
        ),
      ),
    );

    final artFade = find.byKey(const ValueKey('splash-brand-art-transition'));
    expect(artFade, findsOneWidget);
    expect(tester.widget<FadeTransition>(artFade).opacity.value, 0);

    await tester.pump(const Duration(milliseconds: 200));
    final enteringOpacity = tester
        .widget<FadeTransition>(artFade)
        .opacity
        .value;
    expect(enteringOpacity, greaterThan(0));
    expect(enteringOpacity, lessThan(1));

    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.widget<FadeTransition>(artFade).opacity.value, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<FadeTransition>(artFade).opacity.value, 1);
  });
}
