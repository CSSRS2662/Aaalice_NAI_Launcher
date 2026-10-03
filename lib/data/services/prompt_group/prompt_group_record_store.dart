import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/utils/app_logger.dart';
import '../../models/gallery/prompt_group_snapshot.dart';
import '../metadata/hash_calculator.dart';

/// 图片内容哈希到提示词分区快照的旁路记录库。
///
/// 与固定词使用记录一致：结果图字节保持 NovelAI 原样，分区结构只存在本机。
/// 相同快照按指纹去重，每张图只保存一条“内容哈希 → 指纹”的引用。
class PromptGroupRecordStore {
  PromptGroupRecordStore._internal();

  static final PromptGroupRecordStore _instance =
      PromptGroupRecordStore._internal();

  factory PromptGroupRecordStore() => _instance;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  Box<String>? _usageBox;
  Box<String>? _snapshotBox;

  bool get isReady =>
      (_usageBox?.isOpen ?? false) && (_snapshotBox?.isOpen ?? false);

  Future<void> initialize() async {
    if (isReady) return;
    _usageBox = await _openBox(StorageKeys.promptGroupRecordsBox);
    _snapshotBox = await _openBox(StorageKeys.promptGroupSnapshotsBox);
  }

  /// 记录一张图片生成时使用的分区结构。
  Future<void> record({
    required String contentHash,
    required PromptGroupSnapshot snapshot,
    DateTime? recordedAt,
  }) async {
    if (!_hex64.hasMatch(contentHash)) {
      throw ArgumentError.value(
        contentHash,
        'contentHash',
        'Expected a lowercase 64-character SHA-256 hex digest',
      );
    }
    await initialize();
    final encoded = jsonEncode(snapshot.toJson());
    final fingerprint = sha256.convert(utf8.encode(encoded)).toString();
    if (!_snapshotBox!.containsKey(fingerprint)) {
      await _snapshotBox!.put(fingerprint, encoded);
    }
    await _usageBox!.put(
      contentHash,
      jsonEncode({
        'fingerprint': fingerprint,
        'recordedAt': (recordedAt ?? DateTime.now())
            .toUtc()
            .millisecondsSinceEpoch,
      }),
    );
  }

  /// 为本轮生成的结果图逐张记录分区；记录失败不影响生成结果。
  ///
  /// 结果图原字节落盘，按同一内容哈希即可在任意保存入口之后找回分区。
  Future<void> recordGeneratedImages({
    required Iterable<Uint8List> images,
    required PromptGroupSnapshot snapshot,
  }) async {
    final hashes = FileHashCalculator();
    for (final bytes in images) {
      try {
        await record(
          contentHash: await hashes.calculateFromBytesAsync(bytes),
          snapshot: snapshot,
        );
      } catch (error, stack) {
        AppLogger.e(
          'Failed to record prompt groups for a generated image',
          error,
          stack,
          'PromptGroupRecordStore',
        );
      }
    }
  }

  PromptGroupSnapshot? lookup(String contentHash) {
    if (!isReady || !_hex64.hasMatch(contentHash)) return null;
    final fingerprint = _decodeFingerprint(_usageBox!.get(contentHash));
    if (fingerprint == null) return null;
    final raw = _snapshotBox!.get(fingerprint);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PromptGroupSnapshot.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  String? _decodeFingerprint(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final fingerprint = decoded['fingerprint'];
      return fingerprint is String && _hex64.hasMatch(fingerprint)
          ? fingerprint
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<Box<String>> _openBox(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
    return Hive.openBox<String>(name);
  }
}
