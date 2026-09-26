import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/data/services/metadata/hash_calculator.dart';
import 'package:nai_launcher/data/services/prompt_group/prompt_group_record_store.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

const _snapshot = PromptGroupSnapshot(
  groupedMode: true,
  positiveSections: [
    PromptGroupSectionSnapshot(id: 'subject', text: '1girl, solo'),
    PromptGroupSectionSnapshot(id: 'scene', text: 'night sky', collapsed: true),
    PromptGroupSectionSnapshot(id: 'weather', text: 'rain', enabled: false),
  ],
  negativeSections: [PromptGroupSectionSnapshot(id: 'neg', text: 'lowres')],
);

void main() {
  late Directory directory;
  late PromptGroupRecordStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prompt-group-store-');
    Hive.init(directory.path);
    store = PromptGroupRecordStore();
    await store.initialize();
  });

  tearDown(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await directory.delete(recursive: true);
  });

  test('records and looks up sections by content hash', () async {
    await store.record(contentHash: _hashA, snapshot: _snapshot);

    final recorded = store.lookup(_hashA);
    expect(recorded, isNotNull);
    expect(recorded!.groupedMode, isTrue);
    expect(recorded.positiveSections.map((section) => section.id), [
      'subject',
      'scene',
      'weather',
    ]);
    expect(recorded.positiveSections[1].collapsed, isTrue);
    expect(recorded.positiveSections[2].enabled, isFalse);
    expect(recorded.negativeSections.single.text, 'lowres');
    expect(recorded.positivePrompt, _snapshot.positivePrompt);
    expect(store.lookup(_hashB), isNull);
  });

  test('identical snapshots are stored once and shared by hash', () async {
    await store.record(contentHash: _hashA, snapshot: _snapshot);
    await store.record(contentHash: _hashB, snapshot: _snapshot);

    expect(Hive.box<String>(StorageKeys.promptGroupSnapshotsBox).length, 1);
    expect(Hive.box<String>(StorageKeys.promptGroupRecordsBox).length, 2);
    expect(store.lookup(_hashB)?.positivePrompt, _snapshot.positivePrompt);
  });

  test('rejects identifiers that are not lowercase sha-256 digests', () async {
    await expectLater(
      store.record(contentHash: 'not-a-hash', snapshot: _snapshot),
      throwsArgumentError,
    );
    await expectLater(
      store.record(contentHash: _hashA.toUpperCase(), snapshot: _snapshot),
      throwsArgumentError,
    );
    expect(store.lookup('not-a-hash'), isNull);
  });

  test('generated images are keyed by the sha-256 of their bytes', () async {
    final first = Uint8List.fromList([1, 2, 3]);
    final second = Uint8List.fromList([4, 5, 6]);

    await store.recordGeneratedImages(
      images: [first, second],
      snapshot: _snapshot,
    );

    final hashes = FileHashCalculator();
    expect(
      store.lookup(hashes.calculateFromBytes(first))?.positiveSections.length,
      3,
    );
    expect(
      store.lookup(hashes.calculateFromBytes(second))?.negativePrompt,
      'lowres',
    );
  });

  test('lookup returns null once the boxes are closed', () async {
    await store.record(contentHash: _hashA, snapshot: _snapshot);
    await Hive.close().timeout(const Duration(seconds: 10));

    expect(store.isReady, isFalse);
    expect(store.lookup(_hashA), isNull);
  });
}
