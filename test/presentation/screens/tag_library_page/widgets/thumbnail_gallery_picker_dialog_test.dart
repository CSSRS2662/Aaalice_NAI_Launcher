import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/services/gallery/local_gallery_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/thumbnail_gallery_picker_dialog.dart';

void main() {
  testWidgets('可在历史记录与收藏之间切换并返回所选图片', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory.systemTemp.createTempSync(
      'thumbnail_gallery_picker_test_',
    );
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final historyFile = File('${directory.path}/history.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 32, height: 48)));
    final favoriteFile = File('${directory.path}/favorite.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 48, height: 32)));
    final history = LocalImageRecord(
      path: historyFile.path,
      size: historyFile.lengthSync(),
      modifiedAt: DateTime(2026, 9, 2),
    );
    final favorite = LocalImageRecord(
      path: favoriteFile.path,
      size: favoriteFile.lengthSync(),
      modifiedAt: DateTime(2026, 9, 1),
      isFavorite: true,
    );
    final requestedSources = <bool>[];
    String? selectedPath;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  selectedPath = await ThumbnailGalleryPickerDialog.show(
                    context,
                    pageLoader:
                        ({
                          required page,
                          required pageSize,
                          required favoritesOnly,
                        }) async {
                          requestedSources.add(favoritesOnly);
                          final records = favoritesOnly
                              ? [favorite]
                              : [history, favorite];
                          return LocalGalleryQueryPage(
                            records: records,
                            page: page,
                            pageSize: pageSize,
                            totalCount: records.length,
                          );
                        },
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(requestedSources, [false]);
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect(image.fit, BoxFit.contain);
      final provider = image.image as ResizeImage;
      expect(provider.width, isNotNull);
      expect(provider.height, isNull, reason: '解码只限宽度，避免把长图压成方形');
    }
    expect(
      find.byKey(ValueKey('thumbnail-gallery-image-${history.path}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('thumbnail-gallery-image-${favorite.path}')),
      findsOneWidget,
    );

    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(requestedSources, [false, true]);
    expect(
      find.byKey(ValueKey('thumbnail-gallery-image-${history.path}')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(ValueKey('thumbnail-gallery-image-${favorite.path}')),
    );
    await tester.pumpAndSettle();
    expect(selectedPath, favorite.path);
    expect(tester.takeException(), isNull);
  });
}
