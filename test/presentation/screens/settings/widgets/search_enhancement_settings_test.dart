import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/lexical/pinyin_syllables.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/settings/widgets/search_enhancement_settings.dart';

import '../../../../helpers/memory_local_storage.dart';

Future<void> _pump(
  WidgetTester tester,
  MemoryLocalStorage storage, {
  double width = 400,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localStorageServiceProvider.overrideWith((ref) => storage)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: SearchEnhancementSettings()),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('320 宽 3 倍字体下全部开关可达且无溢出', (tester) async {
    final storage = MemoryLocalStorage();
    await _pump(tester, storage, width: 320, textScale: 3);
    expect(tester.takeException(), isNull);
    for (final rule in FuzzyPinyinRule.values) {
      final chip = find.byKey(ValueKey('fuzzy-pinyin-${rule.id}'));
      await tester.ensureVisible(chip);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    }
    expect(find.byType(Switch, skipOffstage: false), findsNWidgets(9));
  });

  testWidgets('关闭拼音后子项禁用，模糊音选择会保存', (tester) async {
    final storage = MemoryLocalStorage();
    await _pump(tester, storage);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SearchEnhancementSettings)),
    )!;

    final zToZh = find.byKey(const ValueKey('fuzzy-pinyin-z-zh'));
    await tester.ensureVisible(zToZh);
    await tester.tap(zToZh);
    await tester.pump();
    expect(storage.values[StorageKeys.autocompleteFuzzyPinyin], [
      'z-zh',
      'an-ang',
      'en-eng',
      'in-ing',
    ]);

    final pinyin = find.text(l10n.autocomplete_pinyinSearch);
    await tester.ensureVisible(pinyin);
    await tester.tap(pinyin);
    await tester.pump();
    expect(storage.values[StorageKeys.autocompletePinyinSearch], false);
    final ziranma = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text(l10n.autocomplete_pinyinZiranma),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(ziranma.onChanged, isNull);
    expect(tester.widget<FilterChip>(zToZh).onSelected, isNull);
  });

  testWidgets('确认后清除本机使用记录', (tester) async {
    final storage = MemoryLocalStorage()
      ..values[StorageKeys.autocompleteTagUsageHistory] = {
        'shirt': [3, 20000],
      };
    await _pump(tester, storage);
    final clear = find.byKey(const ValueKey('search-enhancement-clear-usage'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(clear))!;
    await tester.tap(find.text(l10n.common_confirm).last);
    await tester.pumpAndSettle();
    expect(
      storage.values.containsKey(StorageKeys.autocompleteTagUsageHistory),
      isFalse,
    );
  });
}
