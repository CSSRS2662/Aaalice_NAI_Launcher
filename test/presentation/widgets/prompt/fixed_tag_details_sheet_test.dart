import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_link.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_provider.dart';
import 'package:nai_launcher/presentation/widgets/prompt/fixed_tag_details_sheet.dart';
import 'package:nai_launcher/presentation/widgets/prompt/fixed_tags_dialog_models.dart';

void main() {
  final positive = FixedTagEntry.create(
    name: '无袖水手服',
    content: 'serafuku, sleeveless',
    weight: 1.2,
  ).copyWith(id: 'positive');
  final negative = FixedTagEntry.create(
    name: '低画质',
    content: 'lowres',
    promptType: FixedTagPromptType.negative,
  ).copyWith(id: 'negative');

  Future<List<String>> openDetails(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    final notifier = _TestFixedTagsNotifier(
      FixedTagsState(
        entries: [positive, negative],
        links: const [
          FixedTagLink(
            id: 'link',
            positiveEntryId: 'positive',
            negativeEntryId: 'negative',
          ),
        ],
      ),
    );
    final commands = _commands(calls, notifier);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fixedTagsNotifierProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFixedTagDetails(
                  context: context,
                  entry: positive,
                  commands: commands,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('详情显示内容与联动，并可直接切换前后缀', (tester) async {
    await openDetails(tester, size: const Size(390, 800));

    expect(find.byKey(const ValueKey('adaptive-bottom-sheet')), findsOne);
    expect(find.text('无袖水手服'), findsOne);
    expect(find.textContaining('正向固定词 · 权重 1.20'), findsOne);
    expect(find.textContaining('serafuku'), findsWidgets);
    expect(find.text('已联动：低画质'), findsOne);

    await tester.tap(find.text('后缀'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('fixed-tag-details'))),
    );
    expect(
      container.read(fixedTagsNotifierProvider).entries.first.position,
      FixedTagPosition.suffix,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (key, call) in [
    ('fixed-tag-details-edit', 'edit'),
    ('fixed-tag-details-delete', 'delete'),
    ('fixed-tag-details-links', 'links'),
  ]) {
    testWidgets('$call 先关闭详情再打开对应流程', (tester) async {
      final calls = await openDetails(tester, size: const Size(390, 800));

      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('fixed-tag-details')), findsNothing);
      expect(calls, ['$call:positive']);
    });
  }

  testWidgets('320 宽 3x 字号下全部操作可达且不溢出', (tester) async {
    await openDetails(tester, size: const Size(320, 700), textScale: 3);

    // Lazily built rows need the vertical scroll; ensureVisible then also
    // scrolls the horizontal segment strip at 3x.
    for (final target in [
      find.text('后缀'),
      find.byKey(const ValueKey('fixed-tag-details-links')),
      find.byKey(const ValueKey('fixed-tag-details-copy')),
      find.byKey(const ValueKey('fixed-tag-details-delete')),
      find.byKey(const ValueKey('fixed-tag-details-edit')),
    ]) {
      await tester.scrollUntilVisible(
        target,
        80,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('fixed-tag-details')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOne);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏以居中表单呈现', (tester) async {
    await openDetails(tester, size: const Size(1180, 800));
    expect(find.byKey(const ValueKey('adaptive-centered-form')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

FixedTagsDialogCommands _commands(
  List<String> calls,
  _TestFixedTagsNotifier notifier,
) {
  void unused([Object? _, Object? _]) {}
  return FixedTagsDialogCommands(
    close: unused,
    openLibraryPage: unused,
    toggleNegativePanel: unused,
    undo: unused,
    redo: unused,
    setAllEnabled: unused,
    setPromptTypeEnabled: unused,
    toggleEntry: unused,
    showDetails: unused,
    togglePosition: (entry) => notifier.togglePosition(entry.id),
    reorder: (_, _, _) {},
    editEntry: (entry, _) => calls.add('edit:${entry?.id}'),
    deleteEntry: (entry) => calls.add('delete:${entry.id}'),
    clearAll: unused,
    pickFromLibrary: unused,
    showLinkManager: (entry) => calls.add('links:${entry.id}'),
  );
}

class _TestFixedTagsNotifier extends FixedTagsNotifier {
  _TestFixedTagsNotifier(this.initialState);

  final FixedTagsState initialState;

  @override
  FixedTagsState build() => initialState;

  @override
  Future<void> togglePosition(String entryId) async {
    state = state.copyWith(
      entries: [
        for (final entry in state.entries)
          entry.id == entryId ? entry.togglePosition() : entry,
      ],
    );
  }
}
