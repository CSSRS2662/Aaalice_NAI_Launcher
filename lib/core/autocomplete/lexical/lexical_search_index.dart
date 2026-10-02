import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/app_logger.dart';
import 'english_words.dart';
import 'lexical_index_builder.dart';
import 'search_lexicon.dart';

/// Where the index inputs live right now. The fingerprint changes when any of
/// them does (bundled data, catalog version, installed ffdkj dictionary).
class LexicalIndexSources {
  const LexicalIndexSources({
    required this.indexPath,
    required this.catalogPath,
    required this.catalogVersion,
    required this.ameLexiconGz,
    required this.pinyinGz,
    required this.crossLingualGz,
    this.zhDictionaryPath,
    this.zhDictionaryVersion,
  });

  final String indexPath;
  final String catalogPath;
  final String catalogVersion;
  final Uint8List ameLexiconGz;
  final Uint8List pinyinGz;
  final Uint8List crossLingualGz;
  final String? zhDictionaryPath;
  final String? zhDictionaryVersion;

  String get fingerprint => [
    'v${LexicalIndexSchema.version}',
    catalogVersion,
    shortDigest(ameLexiconGz),
    shortDigest(pinyinGz),
    shortDigest(crossLingualGz),
    zhDictionaryPath == null ? 'nozh' : 'zh:${zhDictionaryVersion ?? '?'}',
  ].join('|');
}

/// A Chinese label row matched through pinyin or characters.
class LexicalLabelMatch {
  const LexicalLabelMatch({
    required this.tag,
    required this.label,
    required this.postCount,
    required this.category,
    required this.pinyin,
  });

  final String tag;
  final String label;
  final int postCount;
  final int category;

  /// Space-separated syllables of the matched reading (empty for character
  /// matches).
  final String pinyin;
}

class SpellSuggestion {
  const SpellSuggestion(this.word, this.distance, this.weight);

  final String word;
  final int distance;
  final int weight;
}

/// The device-local index for pinyin, character and spelling lookups. It is a
/// cache: built in the background from bundled and installed data, rebuilt
/// when its inputs change, never synced.
class LexicalSearchIndex {
  LexicalSearchIndex({
    required Future<LexicalIndexSources?> Function() resolveSources,
    DatabaseFactory? databaseFactory,
    Future<Map<String, int>> Function(LexicalIndexBuildInput input)? build,
  }) : _resolveSources = resolveSources,
       _factory = databaseFactory ?? databaseFactoryFfi,
       _build = build ?? _buildInIsolate;

  final Future<LexicalIndexSources?> Function() _resolveSources;
  final DatabaseFactory _factory;
  final Future<Map<String, int>> Function(LexicalIndexBuildInput input) _build;

  Database? _database;
  String? _openFingerprint;
  Future<void>? _building;
  DateTime? _lastCheck;
  String? _failedFingerprint;
  DateTime? _retryAfter;

  /// A failed build is not retried for the same inputs before this; a build
  /// reads the whole catalog, so retrying on every keystroke would drain a
  /// phone.
  static const Duration retryDelay = Duration(minutes: 10);

  static Future<Map<String, int>> _buildInIsolate(
    LexicalIndexBuildInput input,
  ) => Isolate.run(() => buildLexicalIndex(input));

  /// The open index, or null while it is missing or being (re)built; a build
  /// starts in the background and later calls get the result.
  Future<Database?> database() async {
    final current = _database;
    final now = DateTime.now();
    // Inputs rarely change; re-check them at most every few seconds.
    if (current != null &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < const Duration(seconds: 5)) {
      return current;
    }
    _lastCheck = now;
    final sources = await _resolveSources();
    if (sources == null) return null;
    final fingerprint = sources.fingerprint;
    if (current != null && _openFingerprint == fingerprint) return current;
    if (_building != null) return current;
    if (fingerprint == _failedFingerprint && now.isBefore(_retryAfter!)) {
      return current;
    }

    final existing = await _openIfCurrent(sources.indexPath, fingerprint);
    if (existing != null) return existing;
    _building = _rebuild(sources, fingerprint).whenComplete(() {
      _building = null;
      _lastCheck = null;
    });
    return current;
  }

  /// Waits for any running build; for tests and the evaluation tool.
  Future<Database?> ready() async {
    await database();
    await _building;
    return database();
  }

  Future<Database?> _openIfCurrent(String path, String fingerprint) async {
    try {
      if (!await _factory.databaseExists(path)) return null;
      final db = await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final rows = await db.rawQuery(
        "SELECT value FROM metadata WHERE key = 'fingerprint'",
      );
      if (rows.isEmpty || rows.first['value'] != fingerprint) {
        await db.close();
        return null;
      }
      await _database?.close();
      _database = db;
      _openFingerprint = fingerprint;
      return db;
    } catch (error) {
      AppLogger.w('Lexical index unreadable: $error', 'LexicalSearchIndex');
      return null;
    }
  }

  Future<void> _rebuild(LexicalIndexSources sources, String fingerprint) async {
    final stopwatch = Stopwatch()..start();
    try {
      final previous = _database;
      _database = null;
      _openFingerprint = null;
      await previous?.close();
      final stats = await _build(
        LexicalIndexBuildInput(
          outputPath: sources.indexPath,
          fingerprint: fingerprint,
          catalogPath: sources.catalogPath,
          zhDictionaryPath: sources.zhDictionaryPath,
          ameLexiconGz: sources.ameLexiconGz,
          pinyinGz: sources.pinyinGz,
          crossLingualGz: sources.crossLingualGz,
        ),
      );
      AppLogger.i(
        'Lexical index built in ${stopwatch.elapsedMilliseconds} ms: $stats',
        'LexicalSearchIndex',
      );
      _failedFingerprint = null;
      await _openIfCurrent(sources.indexPath, fingerprint);
    } catch (error, stack) {
      _failedFingerprint = fingerprint;
      _retryAfter = DateTime.now().add(retryDelay);
      AppLogger.e(
        'Lexical index build failed',
        error,
        stack,
        'LexicalSearchIndex',
      );
    }
  }

  /// Labels whose pinyin matches an FTS5 expression over `py` or `pyf`.
  Future<List<LexicalLabelMatch>> pinyinMatches(
    String expression, {
    int limit = 200,
  }) async {
    final db = await database();
    if (db == null || expression.isEmpty) return const [];
    final rows = await db.rawQuery(
      '''
      SELECT e.tag, e.label, e.post_count, e.category, f.py
      FROM label_py f JOIN entries e ON e.id = f.entry
      WHERE label_py MATCH ?
      ORDER BY e.post_count DESC
      LIMIT ?
      ''',
      [expression, limit],
    );
    return rows.map(_labelMatch).toList(growable: false);
  }

  /// Labels sharing characters with the query, best BM25 first.
  Future<List<LexicalLabelMatch>> characterMatches(
    Iterable<String> characters, {
    int limit = 300,
  }) async {
    final db = await database();
    final terms = characters
        .where((c) => c.trim().isNotEmpty)
        .map((c) => '"${c.replaceAll('"', '""')}"')
        .toSet();
    if (db == null || terms.isEmpty) return const [];
    final rows = await db.rawQuery(
      '''
      SELECT e.tag, e.label, e.post_count, e.category, '' AS py
      FROM label_chars f JOIN entries e ON e.id = f.entry
      WHERE label_chars MATCH ?
      ORDER BY bm25(label_chars)
      LIMIT ?
      ''',
      [terms.join(' OR '), limit],
    );
    return rows.map(_labelMatch).toList(growable: false);
  }

  /// Post-count weight of English tag tokens (4+ letters); missing tokens are
  /// not in any tag name.
  Future<Map<String, int>> vocabularyWeights(Iterable<String> tokens) async {
    final db = await database();
    final unique = tokens.toSet().toList(growable: false);
    if (db == null || unique.isEmpty) return const {};
    final rows = await db.rawQuery(
      'SELECT token, weight FROM en_vocab '
      'WHERE token IN (${List.filled(unique.length, '?').join(',')})',
      unique,
    );
    return {
      for (final row in rows) row['token'] as String: row['weight'] as int,
    };
  }

  /// Tag-name words close to [token], nearest and most used first.
  Future<List<SpellSuggestion>> spellingSuggestions(
    String token, {
    int limit = 3,
  }) async {
    final word = token.toLowerCase();
    if (word.length < 4) return const [];
    final db = await database();
    if (db == null) return const [];
    final maxDistance = EnglishWords.allowedDistance(word.length);
    final probes = EnglishWords.deleteNeighbourhood(
      word,
      depth: maxDistance,
    ).toList(growable: false);
    final rows = <Map<String, Object?>>[];
    for (var offset = 0; offset < probes.length; offset += 400) {
      final chunk = probes.skip(offset).take(400).toList(growable: false);
      rows.addAll(
        await db.rawQuery(
          'SELECT DISTINCT d.token, v.weight FROM en_deletes d '
          'JOIN en_vocab v ON v.token = d.token '
          'WHERE d.del IN (${List.filled(chunk.length, '?').join(',')})',
          chunk,
        ),
      );
    }
    final suggestions = <String, SpellSuggestion>{};
    for (final row in rows) {
      final candidate = row['token'] as String;
      if (candidate == word) continue;
      final distance = EnglishWords.distance(word, candidate);
      if (distance > maxDistance) continue;
      suggestions[candidate] = SpellSuggestion(
        candidate,
        distance,
        row['weight'] as int,
      );
    }
    final ordered = suggestions.values.toList()
      ..sort((a, b) {
        final byDistance = a.distance.compareTo(b.distance);
        if (byDistance != 0) return byDistance;
        return b.weight.compareTo(a.weight);
      });
    return ordered.take(limit).toList(growable: false);
  }

  Future<void> dispose() async {
    await _building;
    await _database?.close();
    _database = null;
  }

  static LexicalLabelMatch _labelMatch(Map<String, Object?> row) =>
      LexicalLabelMatch(
        tag: row['tag'] as String,
        label: row['label'] as String,
        postCount: (row['post_count'] as int?) ?? 0,
        category: (row['category'] as int?) ?? 0,
        pinyin: (row['py'] as String?) ?? '',
      );
}
