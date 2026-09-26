import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_top_bar.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/image_detail_data.dart';

void main() {
  for (final panelWidth in [320.0, 600.0]) {
    testWidgets('actions adapt to an embedded ${panelWidth.toInt()}px panel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: panelWidth,
                  child: DetailTopBar(
                    currentImage: GeneratedImageDetailData(
                      imageBytes: Uint8List(0),
                    ),
                    currentIndex: 0,
                    totalImages: 1,
                    onClose: () {},
                    onSave: () {},
                    onReuseSeed: () {},
                    onFavoriteToggle: () {},
                    onShare: () {},
                    onShowMetadata: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      if (panelWidth >= 420) {
        expect(find.byIcon(Icons.save_alt), findsOneWidget);
        expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      }
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Save Image'), findsOneWidget);
      expect(find.text('Reuse Seed'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      final primaryPositions = [
        tester.getTopLeft(find.text('Save Image')).dy,
        tester.getTopLeft(find.text('Reuse Seed')).dy,
        tester.getTopLeft(find.text('Favorite')).dy,
      ];
      expect(
        primaryPositions,
        orderedEquals(primaryPositions.toList()..sort()),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
