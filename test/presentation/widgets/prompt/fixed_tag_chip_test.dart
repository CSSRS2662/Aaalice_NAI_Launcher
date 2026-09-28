import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/presentation/themes/prompt_semantic_colors.dart';
import 'package:nai_launcher/presentation/widgets/prompt/fixed_tag_chip.dart';

void main() {
  Future<({List<String> calls})> pumpChip(
    WidgetTester tester,
    FixedTagEntry entry, {
    int linkCount = 0,
  }) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              height: 52,
              child: FixedTagChip(
                entry: entry,
                linkCount: linkCount,
                onToggle: () => calls.add('toggle'),
                onShowDetails: () => calls.add('details'),
              ),
            ),
          ),
        ),
      ),
    );
    return (calls: calls);
  }

  BoxDecoration decorationOf(WidgetTester tester) =>
      tester.widget<Ink>(find.byType(Ink)).decoration! as BoxDecoration;

  testWidgets('点按切换，长按与右键打开详情', (tester) async {
    final entry = FixedTagEntry.create(name: '水手服', content: 'serafuku');
    final (:calls) = await pumpChip(tester, entry);

    await tester.tap(find.text('水手服'));
    await tester.longPress(find.text('水手服'));
    await tester.tap(find.text('水手服'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(calls, ['toggle', 'details', 'details']);
  });

  testWidgets('只显示名称；启用时带勾选标记和语义色面，未启用为中性色面', (tester) async {
    final enabled = FixedTagEntry.create(name: '启用', content: 'a, b');
    await pumpChip(tester, enabled);
    final theme = Theme.of(tester.element(find.byType(FixedTagChip)));
    final resting = controlSurfaceColor(theme.colorScheme);

    expect(find.text('a, b'), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(
      decorationOf(tester).color,
      Color.alphaBlend(
        theme.promptSemanticColors.positiveFixedTag.withValues(alpha: 0.22),
        resting,
      ),
    );
    expect(
      tester.getSemantics(find.text('启用')),
      isSemantics(
        label: '启用',
        isSelected: true,
        hasTapAction: true,
        hasLongPressAction: true,
      ),
    );

    await pumpChip(
      tester,
      FixedTagEntry.create(
        name: '未启用',
        content: 'c',
        enabled: false,
        promptType: FixedTagPromptType.negative,
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(decorationOf(tester).color, resting);
    expect(
      (decorationOf(tester).border! as Border).top.color,
      Colors.transparent,
    );
  });

  testWidgets('有联动时显示联动标记', (tester) async {
    final entry = FixedTagEntry.create(name: '联动', content: 'x');
    await pumpChip(tester, entry, linkCount: 2);
    expect(find.byKey(ValueKey('fixed-tag-link-mark-${entry.id}')), findsOne);
  });
}
