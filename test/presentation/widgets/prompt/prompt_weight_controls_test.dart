import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/grunge_palette.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/presentation/widgets/prompt/prompt_action_overlay.dart';
import 'package:nai_launcher/presentation/widgets/prompt/prompt_weight_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('weight slider fills the surface and keeps actions aligned', (
    tester,
  ) async {
    final weights = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: resolveLayeredSurfaceColors(
            const GrungePalette().darkScheme,
          ),
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('toolbar-preview'),
              child: ColoredBox(
                color: const Color(0xff292929),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: PromptActionSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: PromptWeightControls(
                          weight: 1,
                          onWeight: weights.add,
                          onStep: (_) {},
                          caption: const Text(
                            '黑衬衫',
                            style: TextStyle(fontSize: 13),
                          ),
                          trailing: [
                            IconButton(
                              tooltip: '停用',
                              onPressed: () {},
                              icon: const Icon(
                                Icons.visibility_off_outlined,
                                size: 18,
                              ),
                            ),
                          ],
                          onClose: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = tester.getSize(find.byType(PromptActionSurface));
    expect(surface.width, 420);
    expect(surface.height, lessThan(180));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('1.00'), findsOneWidget);

    final sliderFinder = find.byKey(const ValueKey('prompt-weight-slider'));
    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.min, -3);
    expect(slider.max, 3);
    expect(slider.divisions, 120);
    expect(tester.getSize(sliderFinder).width, greaterThan(220));
    final sliderTheme = tester.widget<SliderTheme>(
      find.ancestor(of: sliderFinder, matching: find.byType(SliderTheme)).first,
    );
    expect(sliderTheme.data.thumbShape, isA<RoundSliderThumbShape>());

    slider.onChanged!(-1.27);
    expect(weights.single, -1.25);

    final y = tester.getCenter(find.byIcon(Icons.refresh)).dy;
    for (final icon in [Icons.visibility_off_outlined, Icons.close]) {
      expect(tester.getCenter(find.byIcon(icon)).dy, closeTo(y, 1));
    }
    expect(
      tester.getBottomLeft(find.text('黑衬衫')).dy,
      closeTo(
        tester
            .getBottomLeft(find.byKey(const ValueKey('prompt-weight-value')))
            .dy,
        4,
      ),
    );
    final closeRect = tester.getRect(find.byIcon(Icons.close));
    final surfaceRect = tester.getRect(find.byType(PromptActionSurface));
    expect(surfaceRect.right - closeRect.right, lessThan(24));
    expect(tester.takeException(), isNull);
  });
}
