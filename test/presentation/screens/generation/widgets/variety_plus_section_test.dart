import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/generation_param_sections.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/variety_plus_section.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final section = find.byKey(const ValueKey('generation-variety-plus'));

  testWidgets('Variety+ 单独成节，附说明，点整行切换；CFG 标题不再带它', (tester) async {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 3.0)]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      final container = ProviderContainer(
        overrides: [
          generationParamsNotifierProvider.overrideWith(
            () => _FakeGenerationParamsNotifier(
              ImageModels.animeDiffusionV45Full,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_subject(container, textScale: scale));
      await tester.pump();
      final l10n = AppLocalizations.of(tester.element(section))!;

      expect(
        find.descendant(
          of: section,
          matching: find.text(l10n.generation_varietyPlusDescription),
        ),
        findsOne,
      );
      expect(find.text('Variety+'), findsOne, reason: 'only in its section');

      await tester.tap(section);
      await tester.pump();
      expect(
        container.read(generationParamsNotifierProvider).varietyPlus,
        true,
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('generation-variety-plus-switch')),
            )
            .value,
        isTrue,
      );
      expect(tester.getSize(section).height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull, reason: '$width@$scale');
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('模型不支持 Variety+ 时不显示', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          () => _FakeGenerationParamsNotifier(ImageModels.animeDiffusionV3),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_subject(container));
    await tester.pump();
    final supported = container
        .read(generationParamsNotifierProvider)
        .capabilities
        .supportsVarietyPlus;
    expect(section, supported ? findsOne : findsNothing);
  });
}

Widget _subject(ProviderContainer container, {double textScale = 1}) =>
    UncontrolledProviderScope(
      container: container,
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
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [CfgScaleSection(), VarietyPlusSection()],
            ),
          ),
        ),
      ),
    );

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  _FakeGenerationParamsNotifier(this.model);

  final String model;

  @override
  ImageParams build() => ImageParams(model: model);

  @override
  void updateVarietyPlus(bool varietyPlus) {
    state = state.copyWith(varietyPlus: varietyPlus);
  }

  @override
  void updateScale(double scale) {
    state = state.copyWith(scale: scale);
  }
}
