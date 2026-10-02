import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_state.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_workbench_tab_bar.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness app bars keep their surface under scrolled content',
      (tester) async {
        final theme = AppTheme.getTheme(brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('bar')),
              body: ListView(
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 60, child: Text('row $i')),
                ],
              ),
            ),
          ),
        );
        Material bar() => tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(Material),
              )
              .first,
        );
        final resting = bar().color;

        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();

        expect(bar().color, resting);
        expect(bar().color, theme.colorScheme.surface);
        expect(bar().elevation, 0);
        expect(bar().surfaceTintColor, Colors.transparent);
      },
    );
  }

  testWidgets('workbench tabs answer a tap with the thumb, not a ripple', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MobileWorkbenchTabBar(
            selected: MobileWorkbenchTab.image,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    for (final tab in MobileWorkbenchTab.values) {
      final ink = tester.widget<InkWell>(
        find.byKey(ValueKey('mobile-workbench-tab-${tab.name}')),
      );
      expect(ink.splashFactory, NoSplash.splashFactory, reason: tab.name);
      expect(ink.highlightColor, Colors.transparent, reason: tab.name);
    }
  });
}
