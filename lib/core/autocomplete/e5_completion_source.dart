import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../services/android_asset_copy_service.dart';
import 'completion_models.dart';
import 'e5_search_worker.dart';

final e5CompletionSourceProvider = Provider<E5CompletionSource>((ref) {
  final source = E5CompletionSource();
  ref.onDispose(source.dispose);
  return source;
});

/// Local E5 retrieval pack; no user text or model state enters cloud backup.
class E5CompletionSource implements CompletionSource {
  Future<SendPort>? _opening;
  Isolate? _worker;
  SendPort? _port;
  bool _disposed = false;
  DateTime? _retryAfter;
  final _cache = <String, List<CompletionCandidate>>{};
  final _pending = <Completer<dynamic>, ReceivePort>{};

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    if (_disposed ||
        !query.isChinese ||
        query.token.trim().runes.length < 2 ||
        query.kind != CompletionQueryKind.tag ||
        query.relatedTag != null ||
        (query.categoryFilter != null &&
            query.categoryFilter != TagCategory.general)) {
      return const [];
    }
    final text = query.token.trim();
    final cached = _cache[text];
    if (cached != null) return cached.take(query.limit).toList();
    if (_retryAfter?.isAfter(DateTime.now()) == true) {
      throw StateError('E5 initialization failed; retry available shortly');
    }
    final opening = _opening ??= _open();
    final SendPort port;
    try {
      port = await opening;
    } catch (_) {
      if (identical(_opening, opening)) {
        _opening = null;
        _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      }
      rethrow;
    }
    if (_disposed) return const [];
    final response = ReceivePort();
    final completion = Completer<dynamic>();
    _pending[completion] = response;
    response.listen((message) {
      if (!completion.isCompleted) completion.complete(message);
    });
    try {
      port.send([response.sendPort, text, 50]);
      final raw = await completion.future.timeout(const Duration(seconds: 30));
      if (raw is String) throw StateError(raw);
      final results = (raw as List)
          .cast<List>()
          .map(
            (row) => CompletionCandidate(
              canonicalTag: row[0] as String,
              category: TagCategory.general,
              postCount: row[1] as int,
              translation: (row[2] as String).isEmpty ? null : row[2] as String,
              matchKind: CompletionMatchKind.fullText,
              sources: const {CompletionSourceKind.base},
              semanticScore: row[3] as double,
            ),
          )
          .toList(growable: false);
      if (!_disposed) {
        if (_cache.length >= 32) _cache.remove(_cache.keys.first);
        _cache[text] = results;
      }
      return results.take(query.limit).toList();
    } finally {
      _pending.remove(completion);
      response.close();
    }
  }

  Future<SendPort> _open() async {
    final rawManifest = await rootBundle.loadString(
      'assets/semantic_search/manifest.json',
    );
    final manifest = jsonDecode(rawManifest) as Map;
    final version = sha256.convert(utf8.encode(rawManifest)).toString();
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/semantic_search/$version');
    await directory.create(recursive: true);
    for (final entry in (manifest['files'] as Map).entries) {
      if (_disposed) throw StateError('E5 source disposed');
      final name = entry.key as String;
      final expected = entry.value as Map;
      final file = File('${directory.path}/$name');
      if (await file.exists() &&
          await file.length() == expected['bytes'] &&
          (await sha256.bind(file.openRead()).first).toString() ==
              expected['sha256']) {
        continue;
      }
      final partial = File('${file.path}.partial');
      if (Platform.isAndroid) {
        await AndroidAssetCopyService.copyAssetToFile(
          assetKey: 'assets/semantic_search/$name',
          target: partial,
        );
      } else {
        final bytes = await rootBundle.load('assets/semantic_search/$name');
        await partial.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
      }
      if (await partial.length() != expected['bytes'] ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              expected['sha256']) {
        throw FormatException('E5 asset verification failed: $name');
      }
      await partial.rename(file.path);
    }
    await File(
      '${directory.path}/manifest.json',
    ).writeAsString(rawManifest, flush: true);
    await removeStaleVersions(directory.parent, keep: version);
    if (_disposed) throw StateError('E5 source disposed');
    final ready = ReceivePort();
    try {
      _worker = await Isolate.spawn(e5SearchWorker, (
        ready.sendPort,
        directory.path,
      ));
      final result = await ready.first.timeout(const Duration(seconds: 90));
      if (result is! SendPort) throw StateError('E5 initialization: $result');
      if (_disposed) {
        result.send(null);
        throw StateError('E5 source disposed');
      }
      return _port = result;
    } catch (_) {
      _worker?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  /// Earlier verified packs are copies of bundled assets; keeping them would
  /// leave hundreds of megabytes behind after every pack update.
  @visibleForTesting
  static Future<void> removeStaleVersions(
    Directory root, {
    required String keep,
  }) async {
    final version = RegExp(r'^[0-9a-f]{64}$');
    await for (final entity in root.list(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      if (entity is! Directory || !version.hasMatch(name) || name == keep) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        // A locked leftover is retried on the next initialization.
      }
    }
  }

  void dispose() {
    _disposed = true;
    _cache.clear();
    _port?.send(null);
    for (final request in _pending.entries) {
      request.value.close();
      if (!request.key.isCompleted) {
        request.key.completeError(StateError('E5 source disposed'));
      }
    }
    _pending.clear();
  }
}
