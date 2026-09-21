import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_controller.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_input_controller.dart';

import '../../../../helpers/memory_local_storage.dart';

void main() {
  group('joinPromptSections', () {
    test('joins non-empty sections with one separator', () {
      expect(
        joinPromptSections([
          ' 1girl, ',
          ', blue eyes，',
          '   ',
          '{{detailed background}}',
        ]),
        '1girl, blue eyes, {{detailed background}}',
      );
    });

    test('does not alter punctuation inside a section', () {
      expect(
        joinPromptSections(['0.85::artist:kantoor::, 2d', 'looking_at_viewer']),
        '0.85::artist:kantoor::, 2d, looking_at_viewer',
      );
    });
  });

  test('collection excludes disabled sections and follows reordered order', () {
    final groups = PromptGroupCollection.single('character');
    addTearDown(groups.dispose);
    final second = groups.add()..controller.text = 'clothes';
    final third = groups.add()..controller.text = 'pose';

    groups.setEnabled(second.id, false);
    expect(groups.effectiveText, 'character, pose');

    groups.setEnabled(second.id, true);
    groups.reorder(2, 0);
    expect(groups.effectiveText, 'pose, character, clothes');
    expect(groups.sections.first.id, third.id);
  });

  test(
    'prompt controller keeps group state while exposing one final prompt',
    () {
      final storage = MemoryLocalStorage();
      final controller = PromptInputController(
        prompt: 'character',
        negativePrompt: 'lowres',
        storage: storage,
      );

      controller.setEditorMode(PromptEditorMode.grouped);
      final clothes = controller.positiveGroups.add()
        ..controller.text = ', school_uniform, ';
      expect(
        controller.commitGroupedPrompt(negative: false),
        'character, school_uniform',
      );
      expect(controller.promptController.text, 'character, school_uniform');

      controller.positiveGroups.setEnabled(clothes.id, false);
      expect(controller.commitGroupedPrompt(negative: false), 'character');

      final negativeExtra = controller.negativeGroups.add()
        ..controller.text = 'bad hands';
      controller.negativeGroups.toggleCollapsed(negativeExtra.id);
      expect(
        controller.commitGroupedPrompt(negative: true),
        'lowres, bad hands',
      );

      controller.dispose();

      final restored = PromptInputController(
        prompt: 'character',
        negativePrompt: 'lowres, bad hands',
        storage: storage,
      );
      addTearDown(restored.dispose);

      expect(restored.editorMode, PromptEditorMode.grouped);
      expect(restored.positiveGroups.sections, hasLength(2));
      expect(restored.positiveGroups.sections.last.enabled, isFalse);
      expect(restored.negativeGroups.sections, hasLength(2));
      expect(restored.negativeGroups.sections.last.collapsed, isTrue);
    },
  );

  test('external replacement resets only the matching prompt side', () {
    final controller = PromptInputController(
      prompt: 'old positive',
      negativePrompt: 'old negative',
    );
    addTearDown(controller.dispose);
    controller.positiveGroups.add().controller.text = 'second positive';
    controller.negativeGroups.add().controller.text = 'second negative';

    controller.replacePrompt('imported prompt', negative: false);

    expect(controller.positiveGroups.sections, hasLength(1));
    expect(
      controller.positiveGroups.sections.single.controller.text,
      'imported prompt',
    );
    expect(controller.negativeGroups.sections, hasLength(2));
  });

  test('restores imported partitions without flattening their state', () {
    final controller = PromptInputController(
      prompt: 'old positive',
      negativePrompt: 'old negative',
    );
    addTearDown(controller.dispose);
    const snapshot = PromptGroupSnapshot(
      groupedMode: true,
      positiveSections: [
        PromptGroupSectionSnapshot(id: 'character', text: '1girl'),
        PromptGroupSectionSnapshot(
          id: 'clothes',
          text: 'school uniform',
          collapsed: true,
        ),
        PromptGroupSectionSnapshot(
          id: 'disabled',
          text: 'indoors',
          enabled: false,
        ),
      ],
      negativeSections: [
        PromptGroupSectionSnapshot(id: 'negative', text: 'lowres'),
      ],
    );

    controller.restoreGroupSnapshot(
      snapshot,
      restorePositive: true,
      restoreNegative: false,
    );

    expect(controller.editorMode, PromptEditorMode.grouped);
    expect(controller.positiveGroups.sections, hasLength(3));
    expect(controller.positiveGroups.sections[1].collapsed, isTrue);
    expect(controller.positiveGroups.sections[2].enabled, isFalse);
    expect(controller.promptController.text, '1girl, school uniform');
    expect(controller.negativeController.text, 'old negative');
  });
}
