import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chinese_query_variants.dart';
import 'completion_models.dart';

/// Bundled Chinese names and aliases from amenorira/danbooru-tags-data-zh
/// (MIT), mapped onto the bundled catalog by `tool/zh_lexicon`.
///
/// It adds Chinese reverse-lookup keys (for example community nicknames) and
/// only fills translations after reviewed corrections, the installed ffdkj
/// dictionary and the E5 labels. Search rows leave `translation` empty so the
/// shared resolver precedence decides what is displayed.
class AmeZhLexicon implements CompletionSource, TranslationResolver {
  AmeZhLexicon({
    Future<Uint8List> Function()? loadBytes,
    Future<AmeZhLexiconIndex> Function(Uint8List bytes)? decode,
  }) : _loadBytes = loadBytes ?? _loadAsset,
       _decode = decode ?? _decodeInBackground;

  static const assetKey = 'assets/zh_lexicon/ame_lexicon.json.gz';

  final Future<Uint8List> Function() _loadBytes;
  final Future<AmeZhLexiconIndex> Function(Uint8List bytes) _decode;
  Future<AmeZhLexiconIndex>? _index;
  DateTime? _retryAfter;

  static Future<Uint8List> _loadAsset() async {
    final data = await rootBundle.load(assetKey);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static Future<AmeZhLexiconIndex> _decodeInBackground(Uint8List bytes) =>
      compute(AmeZhLexiconIndex.decode, bytes);

  Future<AmeZhLexiconIndex> _load() async => _decode(await _loadBytes());

  Future<AmeZhLexiconIndex> _ensure() async {
    final retryAfter = _retryAfter;
    if (retryAfter != null && retryAfter.isAfter(DateTime.now())) {
      throw StateError('Bundled Chinese lexicon unavailable');
    }
    final loading = _index ??= _load();
    try {
      return await loading;
    } catch (_) {
      if (identical(_index, loading)) {
        _index = null;
        _retryAfter = DateTime.now().add(const Duration(minutes: 1));
      }
      rethrow;
    }
  }

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    if (!query.isChinese ||
        query.kind != CompletionQueryKind.tag ||
        query.relatedTag != null ||
        query.token.trim().isEmpty) {
      return const [];
    }
    return (await _ensure()).search(query);
  }

  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async {
    if (!locale.toLowerCase().startsWith('zh') || canonicalTags.isEmpty) {
      return const {};
    }
    return (await _ensure()).resolve(canonicalTags);
  }
}

/// In-memory lexicon with a per-character posting list, so a query only scans
/// entries containing its rarest character.
class AmeZhLexiconIndex {
  AmeZhLexiconIndex._(
    this._tags,
    this._categories,
    this._counts,
    this._labels,
    this._aliases,
    this._byTag,
    this._postings,
  );

  /// Rows: `[tag, catalog category, post count, zh label, [aliases]]`.
  factory AmeZhLexiconIndex.fromRows(List<List<Object?>> rows) {
    final tags = <String>[];
    final categories = Int32List(rows.length);
    final counts = Int32List(rows.length);
    final labels = <String>[];
    final aliases = <List<String>>[];
    final byTag = <String, int>{};
    final postings = <int, List<int>>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final tag = row[0] as String;
      tags.add(tag);
      categories[i] = row[1] as int;
      counts[i] = row[2] as int;
      labels.add(row[3] as String);
      aliases.add(List.unmodifiable((row[4] as List).cast<String>()));
      byTag[tag] = i;
      final runes = <int>{
        ...labels[i].runes,
        for (final a in aliases[i]) ...a.runes,
      };
      for (final rune in runes) {
        (postings[rune] ??= <int>[]).add(i);
      }
    }
    return AmeZhLexiconIndex._(
      List.unmodifiable(tags),
      categories,
      counts,
      List.unmodifiable(labels),
      List.unmodifiable(aliases),
      byTag,
      {for (final e in postings.entries) e.key: Int32List.fromList(e.value)},
    );
  }

  static AmeZhLexiconIndex decode(Uint8List gzipped) {
    final data = jsonDecode(utf8.decode(gzip.decode(gzipped))) as Map;
    return AmeZhLexiconIndex.fromRows(
      (data['entries'] as List).cast<List<Object?>>(),
    );
  }

  final List<String> _tags;
  final Int32List _categories;
  final Int32List _counts;
  final List<String> _labels;
  final List<List<String>> _aliases;
  final Map<String, int> _byTag;
  final Map<int, Int32List> _postings;

  int get length => _tags.length;

  List<CompletionCandidate> search(CompletionQuery query) {
    final token = query.token.trim();
    if (token.isEmpty) return const [];
    final limit =
        token.runes.length == 1 && CompletionResultLimits.isAll(query.limit)
        ? CompletionResultLimits.oneCharacter
        : query.limit;
    final hits = <int, (CompletionMatchKind, String?)>{};
    void keep(int id, CompletionMatchKind kind, String? alias) {
      final existing = hits[id];
      if (existing == null || kind.index < existing.$1.index) {
        hits[id] = (kind, alias);
      }
    }

    for (final term in {token, ...chineseQueryVariants(token)}) {
      for (final id in _candidates(term.runes)) {
        final match = _match(id, term);
        if (match != null) keep(id, match.$1, match.$2);
      }
    }
    final keywords = chineseQueryKeywords(token);
    if (keywords.isNotEmpty) {
      for (final id in _candidates(keywords.expand((k) => k.runes))) {
        final text = [
          _labels[id],
          ..._aliases[id],
        ].where((value) => keywords.every(value.contains)).firstOrNull;
        if (text != null) {
          keep(
            id,
            CompletionMatchKind.fullText,
            text == _labels[id] ? null : text,
          );
        }
      }
    }

    final filter = query.categoryFilter;
    final ids =
        hits.keys
            .where(
              (id) =>
                  filter == null ||
                  (TagCategory.fromCatalog(_categories[id]) ??
                          TagCategory.general) ==
                      filter,
            )
            .toList()
          ..sort((a, b) {
            final kind = hits[a]!.$1.index.compareTo(hits[b]!.$1.index);
            if (kind != 0) return kind;
            final count = _counts[b].compareTo(_counts[a]);
            return count != 0 ? count : _tags[a].compareTo(_tags[b]);
          });
    return [
      for (final id in ids.take(limit))
        CompletionCandidate(
          canonicalTag: _tags[id],
          category:
              TagCategory.fromCatalog(_categories[id]) ?? TagCategory.general,
          postCount: _counts[id],
          matchKind: hits[id]!.$1,
          matchedAlias: hits[id]!.$2,
          sources: const {CompletionSourceKind.zhDictionary},
        ),
    ];
  }

  Map<String, String> resolve(Iterable<String> canonicalTags) {
    final result = <String, String>{};
    for (final raw in canonicalTags) {
      final id = _byTag[raw.trim().toLowerCase().replaceAll(' ', '_')];
      if (id != null && _labels[id].isNotEmpty) result[raw] = _labels[id];
    }
    return result;
  }

  Iterable<int> _candidates(Iterable<int> runes) {
    Int32List? rarest;
    for (final rune in runes.toSet()) {
      final postings = _postings[rune];
      if (postings == null) return const [];
      if (rarest == null || postings.length < rarest.length) rarest = postings;
    }
    return rarest ?? const <int>[];
  }

  (CompletionMatchKind, String?)? _match(int id, String term) {
    (CompletionMatchKind, String?)? best;
    void consider(String text, String? alias) {
      final kind = text == term
          ? CompletionMatchKind.chineseExact
          : text.startsWith(term)
          ? CompletionMatchKind.chinesePrefix
          : text.contains(term)
          ? CompletionMatchKind.chineseContains
          : null;
      if (kind != null && (best == null || kind.index < best!.$1.index)) {
        best = (kind, alias);
      }
    }

    if (_labels[id].isNotEmpty) consider(_labels[id], null);
    for (final alias in _aliases[id]) {
      consider(alias, alias);
    }
    return best;
  }
}
