import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_generation_header.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

import '../../../helpers/memory_local_storage.dart';

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

  testWidgets('尺寸菜单只能选择：分组预设与已保存尺寸，选中后写回参数', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryLocalStorage()
      ..values[StorageKeys.customResolutionPresets] = ['896x1152'];
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final sizePill = find.byKey(
      const ValueKey('generation-mobile-size-action'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const MobileSizeMenu()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sizePill, matching: find.text('832×1216')),
      findsOne,
    );
    expect(
      tester.getSemantics(sizePill),
      isSemantics(label: '尺寸 832×1216，点按切换', isButton: true),
    );

    await tester.tap(sizePill);
    await tester.pumpAndSettle();
    final portrait = find.byKey(
      const ValueKey('generation-mobile-size-normal_portrait'),
    );
    expect(
      find.descendant(of: portrait, matching: find.byIcon(Icons.check_rounded)),
      findsOne,
    );
    expect(
      find.byKey(
        const ValueKey('generation-mobile-size-saved_custom_896_1152'),
      ),
      findsOne,
    );
    expect(find.text('常规'), findsOne);
    // Only choices: typing, saving and deleting sizes stay on the param page.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('save-custom-resolution')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('generation-mobile-size-normal_landscape')),
    );
    await tester.pumpAndSettle();
    final params = container.read(generationParamsNotifierProvider);
    expect((params.width, params.height), (1216, 832));
    expect(
      find.descendant(of: sizePill, matching: find.text('1216×832')),
      findsOne,
    );

    await tester.tap(sizePill);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('generation-mobile-size-saved_custom_896_1152'),
      ),
    );
    await tester.pumpAndSettle();
    final saved = container.read(generationParamsNotifierProvider);
    expect((saved.width, saved.height), (896, 1152));
    expect(tester.takeException(), isNull);
  });

  testWidgets('模型与尺寸并排：空间够时完整显示，窄屏与 3 倍字号下一起收缩不溢出', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
        localStorageServiceProvider.overrideWithValue(MemoryLocalStorage()),
      ],
    );
    addTearDown(container.dispose);

    for (final (width, scale) in [
      (360.0, 1.0),
      (200.0, 1.0),
      (140.0, 1.0),
      (360.0, 3.0),
      (200.0, 3.0),
    ]) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(
            SizedBox(width: width, child: const MobileGenerationHeaderMenus()),
            textScale: scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final model = find.byKey(
        const ValueKey('generation-mobile-model-action'),
      );
      final size = find.byKey(const ValueKey('generation-mobile-size-action'));
      expect(model, findsOne, reason: '$width@$scale');
      expect(size, findsOne, reason: '$width@$scale');
      expect(
        tester.getRect(size).right,
        lessThanOrEqualTo(width + 0.01),
        reason: '$width@$scale',
      );
      expect(
        tester.getRect(model).right,
        lessThanOrEqualTo(tester.getRect(size).left),
        reason: '$width@$scale',
      );
      expect(tester.takeException(), isNull, reason: '$width@$scale');
    }

    // With room for both, neither label is cut.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const SizedBox(width: 360, child: MobileGenerationHeaderMenus()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['V5 Full', '832×1216']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
    }
  });
}

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
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
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  @override
  ImageParams build() => const ImageParams(
    model: ImageModels.animeDiffusionV5Full,
    width: 832,
    height: 1216,
  );

  @override
  void updateSize(int width, int height, {bool persist = true}) {
    state = state.copyWith(width: width, height: height);
  }

  @override
  void updateModel(
    String model, {
    bool persist = true,
    bool followDefaults = true,
  }) {
    state = state.copyWith(model: model);
  }
}
