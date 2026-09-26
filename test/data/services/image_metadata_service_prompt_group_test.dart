import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/data/services/image_metadata_service.dart';
import 'package:nai_launcher/data/services/metadata/hash_calculator.dart';
import 'package:nai_launcher/data/services/metadata/unified_metadata_parser.dart';
import 'package:nai_launcher/data/services/prompt_group/prompt_group_record_store.dart';

import '../../helpers/fixed_tag_usage_fixture.dart';

PromptGroupSnapshot _snapshotOf(String firstSection) => PromptGroupSnapshot(
  groupedMode: true,
  positiveSections: [
    PromptGroupSectionSnapshot(id: 'first', text: firstSection),
    const PromptGroupSectionSnapshot(id: 'second', text: 'night sky'),
  ],
  negativeSections: const [PromptGroupSectionSnapshot(id: 'n', text: '')],
);

/// Older custom builds embedded the sections in the PNG Comment.
Uint8List _embedPromptGroups(Uint8List bytes, PromptGroupSnapshot snapshot) {
  final comment =
      jsonDecode(UnifiedMetadataParser.extractPngTextData(bytes)['Comment']!)
          as Map<String, dynamic>;
  comment[PromptGroupSnapshot.metadataKey] = snapshot.toJson();
  return UnifiedMetadataParser.embedTextChunkOnly(
    bytes,
    'Comment',
    jsonEncode(comment),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('metadata-prompt-group-');
    Hive.init(directory.path);
    await ImageMetadataService().initialize();
  });

  tearDown(() async {
    await ImageMetadataService().clearCache();
    await Hive.close().timeout(const Duration(seconds: 10));
    await directory.delete(recursive: true);
  });

  test(
    'recorded sections are mounted onto metadata parsed from bytes',
    () async {
      final bytes = await novelAiPngBytes('1girl, night sky');
      await PromptGroupRecordStore().record(
        contentHash: FileHashCalculator().calculateFromBytes(bytes),
        snapshot: _snapshotOf('1girl'),
      );

      final metadata = await ImageMetadataService().getMetadataFromBytes(bytes);

      expect(
        metadata?.promptGroupSnapshot?.positiveSections.first.text,
        '1girl',
      );
      expect(
        UnifiedMetadataParser.parseFromPng(bytes).metadata!.promptGroupData,
        isNull,
        reason: 'the image bytes must stay exactly as NovelAI produced them',
      );
    },
  );

  test(
    'recorded sections are mounted onto metadata parsed from a file',
    () async {
      final bytes = await novelAiPngBytes('1girl, night sky');
      final file = File('${directory.path}/grouped.png');
      await file.writeAsBytes(bytes);
      await PromptGroupRecordStore().record(
        contentHash: FileHashCalculator().calculateFromBytes(bytes),
        snapshot: _snapshotOf('from-file'),
      );

      final metadata = await ImageMetadataService().getMetadata(file.path);

      expect(
        metadata?.promptGroupSnapshot?.positiveSections.first.text,
        'from-file',
      );
    },
  );

  test('sections embedded by older builds win over the record', () async {
    final bytes = _embedPromptGroups(
      await novelAiPngBytes('1girl, night sky'),
      _snapshotOf('from-png'),
    );
    await PromptGroupRecordStore().record(
      contentHash: FileHashCalculator().calculateFromBytes(bytes),
      snapshot: _snapshotOf('from-store'),
    );

    final metadata = await ImageMetadataService().getMetadataFromBytes(bytes);

    expect(
      metadata?.promptGroupSnapshot?.positiveSections.first.text,
      'from-png',
    );
  });

  test('images without a record keep their metadata unchanged', () async {
    final bytes = await novelAiPngBytes('plain prompt');

    final metadata = await ImageMetadataService().getMetadataFromBytes(bytes);

    expect(metadata, isNotNull);
    expect(metadata!.promptGroupData, isNull);
  });
}
