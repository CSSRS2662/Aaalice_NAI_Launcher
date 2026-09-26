import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/presentation/widgets/common/thumbnail_display.dart';

void main() {
  testWidgets('adds decode size hints while image dimensions are loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2.5),
          child: ThumbnailDisplay(
            imagePath: 'missing-thumbnail.png',
            width: 120,
            height: 48,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;

    expect(resized.width, 300);
    expect(resized.height, 120);
  });

  testWidgets('fits the complete square focus into a wide thumbnail', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'thumbnail_display_test_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    final imageFile = File('${directory.path}/square.png');
    imageFile.writeAsBytesSync(
      img.encodePng(img.Image(width: 100, height: 100)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: ThumbnailDisplay(
            imagePath: imageFile.path,
            width: 100,
            height: 40,
            scale: 2,
          ),
        ),
      ),
    );

    final resized = await _pumpUntilResizeWidth(tester, 160);
    final image = tester.widget<Image>(find.byType(Image));

    expect(resized.width, 160);
    expect(resized.height, 160);
    expect(image.width, 80);
    expect(image.height, 80);
  });

  testWidgets('preserves source ratio while fitting the square focus', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'thumbnail_display_ratio_test_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    final imageFile = File('${directory.path}/landscape.png');
    imageFile.writeAsBytesSync(
      img.encodePng(img.Image(width: 200, height: 100)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: ThumbnailDisplay(
            imagePath: imageFile.path,
            width: 64,
            height: 64,
          ),
        ),
      ),
    );

    final resized = await _pumpUntilResizeWidth(tester, 256);
    final image = tester.widget<Image>(find.byType(Image));

    expect(resized.width, 256);
    expect(resized.height, 128);
    expect(image.width, 128);
    expect(image.height, 64);
  });

  testWidgets(
    'keeps an offset square focus complete and centered at any ratio',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'thumbnail_display_focus_test_',
      );
      addTearDown(() {
        if (directory.existsSync()) {
          directory.deleteSync(recursive: true);
        }
      });

      final imageFile = File('${directory.path}/landscape.png');
      const sourceSize = Size(300, 200);
      const offsetX = 0.6;
      const offsetY = -0.5;
      const scale = 2.0;
      imageFile.writeAsBytesSync(
        img.encodePng(
          img.Image(
            width: sourceSize.width.toInt(),
            height: sourceSize.height.toInt(),
          ),
        ),
      );

      for (final viewportSize in const [Size(200, 80), Size(80, 200)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: ThumbnailDisplay(
                imagePath: imageFile.path,
                width: viewportSize.width,
                height: viewportSize.height,
                offsetX: offsetX,
                offsetY: offsetY,
                scale: scale,
              ),
            ),
          ),
        );
        await _pumpUntilResizeWidth(tester, 240);

        final viewport = tester.getRect(find.byType(ThumbnailDisplay));
        final renderedImage = tester.getRect(find.byType(Image));
        final cropSide = sourceSize.shortestSide / scale;
        final cropCenter = Offset(
          sourceSize.width / 2 + offsetX * (sourceSize.width - cropSide) / 2,
          sourceSize.height / 2 + offsetY * (sourceSize.height - cropSide) / 2,
        );
        final sourceToDisplay = renderedImage.width / sourceSize.width;
        final displayedFocus = Rect.fromCenter(
          center: Offset(
            renderedImage.left + cropCenter.dx * sourceToDisplay,
            renderedImage.top + cropCenter.dy * sourceToDisplay,
          ),
          width: cropSide * sourceToDisplay,
          height: cropSide * sourceToDisplay,
        );

        expect(displayedFocus.center.dx, closeTo(viewport.center.dx, 0.01));
        expect(displayedFocus.center.dy, closeTo(viewport.center.dy, 0.01));
        expect(displayedFocus.size, Size.square(viewport.size.shortestSide));
        expect(displayedFocus.left, greaterThanOrEqualTo(viewport.left - 0.01));
        expect(displayedFocus.top, greaterThanOrEqualTo(viewport.top - 0.01));
        expect(displayedFocus.right, lessThanOrEqualTo(viewport.right + 0.01));
        expect(
          displayedFocus.bottom,
          lessThanOrEqualTo(viewport.bottom + 0.01),
        );
      }
    },
  );
}

Future<ResizeImage> _pumpUntilResizeWidth(
  WidgetTester tester,
  int expectedWidth,
) async {
  ResizeImage? latest;

  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(milliseconds: 20));
    final image = tester.widget<Image>(find.byType(Image));
    latest = image.image as ResizeImage;
    if (latest.width == expectedWidth) {
      return latest;
    }
  }

  return latest!;
}
