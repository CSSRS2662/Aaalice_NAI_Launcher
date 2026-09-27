import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_generation_header.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final pill = find.byKey(const ValueKey('generation-mobile-model-action'));

  testWidgets('点按模型直接展开菜单切换，当前模型带勾选', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const MobileModelMenu()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.descendant(of: pill, matching: find.text('V5 Full')), findsOne);
    expect(
      tester.getSemantics(pill),
      isSemantics(label: '模型 V5 Full，点按切换', isButton: true),
    );

    await tester.tap(pill);
    await tester.pumpAndSettle();
    for (final id in ImageModels.allModels) {
      final item = find.byKey(ValueKey('generation-mobile-model-$id'));
      expect(item, findsOneWidget);
      expect(tester.getSize(item).height, greaterThanOrEqualTo(44));
    }
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'generation-mobile-model-${ImageModels.animeDiffusionV5Full}',
          ),
        ),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey(
          'generation-mobile-model-${ImageModels.animeDiffusionV45Full}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(generationParamsNotifierProvider).model,
      ImageModels.animeDiffusionV45Full,
    );
    expect(
      find.descendant(of: pill, matching: find.text('V4.5 Full')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.getTheme(Brightness.light),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: app!,
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  @override
  ImageParams build() =>
      const ImageParams(model: ImageModels.animeDiffusionV5Full);

  @override
  void updateModel(
    String model, {
    bool persist = true,
    bool followDefaults = true,
  }) {
    state = state.copyWith(model: model);
  }
}
