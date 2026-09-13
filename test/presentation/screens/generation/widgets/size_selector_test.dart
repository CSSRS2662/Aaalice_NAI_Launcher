import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/size_selector.dart';

void main() {
  testWidgets('shows a valid 64-grid suggestion for custom resolution', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizeSelector(width: 1080, height: 1920, onChanged: (_, _) {}),
        ),
      ),
    );

    expect(
      find.text(
        '1080×1920 无法用于生成。宽度和高度必须是 64 的倍数、单边不能超过 4096，且总像素'
        '不能超过 3,145,728。最接近的可用尺寸是 1088×1920。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not warn for a valid 64-grid resolution', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizeSelector(width: 1088, height: 1920, onChanged: (_, _) {}),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('invalid-resolution-hint')), findsNothing);
  });

  testWidgets('saves, lists, selects and deletes a custom resolution', (
    tester,
  ) async {
    final storage = _MemoryLocalStorageService();
    var selectedSize = (width: 0, height: 0);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SizeSelector(
              width: 704,
              height: 1472,
              onChanged: (width, height) {
                selectedSize = (width: width, height: height);
              },
              storage: storage,
            ),
          ),
        ),
      ),
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(tester.getSize(fields.first).width, lessThan(140));
    expect(
      find.byKey(const ValueKey('save-custom-resolution')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('save-custom-resolution')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('delete-custom-resolution')),
      findsOneWidget,
    );
    await _waitForButtonEnabled(
      tester,
      const ValueKey('delete-custom-resolution'),
    );
    expect(storage.values, ['704x1472']);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('704×1472'), findsOneWidget);
    await tester.tap(find.text('704×1472'));
    await tester.pumpAndSettle();
    expect(selectedSize, (width: 704, height: 1472));

    await tester.tap(find.byKey(const ValueKey('delete-custom-resolution')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('save-custom-resolution')),
      findsOneWidget,
    );
    await _waitForButtonEnabled(
      tester,
      const ValueKey('save-custom-resolution'),
    );
    expect(storage.values, isEmpty);
  });

  testWidgets('keeps the custom action reachable at 320 width and 3x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Scaffold(
            body: SizeSelector(
              width: 704,
              height: 1472,
              onChanged: (_, __) {},
              storage: _MemoryLocalStorageService(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('save-custom-resolution')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _waitForButtonEnabled(WidgetTester tester, Key key) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty &&
        tester.widget<TextButton>(finder).onPressed != null) {
      return;
    }
  }
  fail('Timed out waiting for $key to become enabled');
}

class _MemoryLocalStorageService extends LocalStorageService {
  List<String> values = [];

  @override
  List<String> getCustomResolutionPresets() => List.unmodifiable(values);

  @override
  Future<void> setCustomResolutionPresets(List<String> presets) {
    values = List.of(presets);
    return Future<void>.value();
  }
}
