import 'dart:math' as math;

import '../autocomplete_settings.dart';
import '../completion_models.dart';
import '../tag_catalog_repository.dart';
import 'english_words.dart';
import 'lexical_search_index.dart';
import 'pinyin_syllables.dart';
import 'search_lexicon.dart';

/// Non-AI fallbacks that run after the literal sources answered:
///
/// * Chinese queries: homophones (陈山 → 衬衫), fuzzy sounds, labels sharing
///   most characters in order (拨起头发 → 拨头发), and the query split into
///   words searched as English tag tokens (坐在椅子上 → sitting_on_chair).
/// * Letter queries: corrected typos and other word forms when nothing
///   matched literally, then the letters read as full pinyin, Ziranma double
///   pinyin or syllable initials.
///
/// Each row carries a match kind below the literal kinds, so literal matches
/// always come first.
class LexicalEnhancementSource implements SupplementalCompletionSource {
  LexicalEnhancementSource({
    required LexicalSearchIndex index,
    required Future<SearchLexicon> Function() lexicon,
    required TagCatalogRepository catalog,
    required AutocompleteSettings Function() settings,
  }) : _index = index,
       _lexicon = lexicon,
       _catalog = catalog,
       _settings = settings;

  final LexicalSearchIndex _index;
  final Future<SearchLexicon> Function() _lexicon;
  final TagCatalogRepository _catalog;
  final AutocompleteSettings Function() _settings;

  static final RegExp _hanzi = RegExp(r'[㐀-鿿]');
  static final RegExp _letterQuery = RegExp(r"^[a-zA-Z][a-zA-Z\s_']*$");
  static final RegExp _separators = RegExp(r"[\s_']+");
  static const int _perStage = 24;

  static const Set<CompletionMatchKind> _literalChinese = {
    CompletionMatchKind.chineseExact,
    CompletionMatchKind.chinesePrefix,
  };
  static const Set<CompletionMatchKind> _literalEnglish = {
    CompletionMatchKind.englishExact,
    CompletionMatchKind.englishPrefix,
    CompletionMatchKind.aliasExact,
    CompletionMatchKind.aliasPrefix,
  };

  @override
  Future<List<CompletionCandidate>> supplement(
    CompletionQuery query,
    List<CompletionCandidate> primary,
  ) async {
    if (query.kind != CompletionQueryKind.tag || query.relatedTag != null) {
      return const [];
    }
    final token = query.token.trim();
    if (token.isEmpty) return const [];
    final settings = _settings();
    final List<CompletionCandidate> rows;
    if (_hanzi.hasMatch(token)) {
      rows = await _chinese(query, token, primary, settings);
    } else if (_letterQuery.hasMatch(token)) {
      rows = await _letters(query, token, primary, settings);
    } else {
      return const [];
    }
    final filter = query.categoryFilter;
    return filter == null
        ? rows
        : rows.where((row) => row.category == filter).toList(growable: false);
  }

  // ------------------------------------------------------------ Chinese

  Future<List<CompletionCandidate>> _chinese(
    CompletionQuery query,
    String token,
    List<CompletionCandidate> primary,
    AutocompleteSettings settings,
  ) async {
    final text = token.replaceAll(_separators, '');
    final lexicon = await _lexicon();
    final results = <CompletionCandidate>[];
    var strong = primary
        .where((row) => _literalChinese.contains(row.matchKind))
        .length;

    if (settings.pinyinSearchEnabled) {
      final variants = lexicon.pinyin.readingVariants(text, maxVariants: 6);
      if (variants.isNotEmpty) {
        final homophones = await _homophones(variants);
        strong += homophones.where((row) => row.matchQuality >= 0.6).length;
        results.addAll(homophones);
        if (settings.fuzzyPinyinRules.isNotEmpty) {
          results.addAll(
            await _fuzzy(variants, settings.fuzzyPinyinRules, results),
          );
        }
      }
    }
    if (settings.approximateMatchEnabled &&
        text.runes.length >= 2 &&
        strong < 8) {
      results.addAll(await _approximate(text));
    }
    if (settings.crossLingualEnabled) {
      results.addAll(await _crossLingual(text, lexicon, strong));
    }
    return results;
  }

  Future<List<CompletionCandidate>> _homophones(
    List<List<String>> variants,
  ) async {
    // Labels that start with the reading only: mid-label homophones
    // (葛城（闪乱… for 城山) are noise more often than what was meant.
    final rows = await _index.pinyinMatches(
      _expression('py', [for (final variant in variants) _phrase(variant)]),
      limit: 160,
    );
    final best = <String, CompletionCandidate>{};
    for (final row in rows) {
      final syllables = row.pinyin.split(' ');
      final quality = variants
          .map((variant) => _sequenceQuality(syllables, variant))
          .reduce(math.max);
      if (quality <= 0) continue;
      _keepBest(
        best,
        _labelCandidate(row, CompletionMatchKind.homophone, quality),
      );
    }
    return _top(best.values);
  }

  Future<List<CompletionCandidate>> _fuzzy(
    List<List<String>> variants,
    Set<FuzzyPinyinRule> rules,
    List<CompletionCandidate> found,
  ) async {
    final expression = _expression('pyf', [
      for (final variant in variants)
        _phrase(variant.map(foldPinyinFully).toList()),
    ]);
    final known = found.map((row) => row.stableId).toSet();
    final best = <String, CompletionCandidate>{};
    for (final row in await _index.pinyinMatches(expression, limit: 200)) {
      final syllables = row.pinyin.split(' ');
      var quality = 0.0;
      for (final variant in variants) {
        if (syllables.length < variant.length) continue;
        var same = true;
        var exact = true;
        for (var i = 0; i < variant.length && same; i++) {
          if (syllables[i] != variant[i]) exact = false;
          same =
              foldPinyin(syllables[i], rules) == foldPinyin(variant[i], rules);
        }
        // Exact readings were homophones already.
        if (!same || exact) continue;
        quality = math.max(
          quality,
          syllables.length == variant.length ? 1 : 0.6,
        );
      }
      if (quality <= 0) continue;
      final candidate = _labelCandidate(
        row,
        CompletionMatchKind.fuzzyPinyin,
        quality,
      );
      if (!known.contains(candidate.stableId)) _keepBest(best, candidate);
    }
    return _top(best.values);
  }

  Future<List<CompletionCandidate>> _approximate(String text) async {
    final chars = text.runes.map(String.fromCharCode).toList(growable: false);
    final best = <String, CompletionCandidate>{};
    for (final row in await _index.characterMatches(chars, limit: 240)) {
      if (row.label == text) continue;
      final label = row.label.runes.map(String.fromCharCode).toList();
      final common = _lcs(chars, label);
      final similarity = common / math.max(chars.length, label.length);
      if (common < 2 || similarity < 0.5) continue;
      _keepBest(
        best,
        _labelCandidate(row, CompletionMatchKind.approximate, similarity),
      );
    }
    return _top(best.values);
  }

  Future<List<CompletionCandidate>> _crossLingual(
    String text,
    SearchLexicon lexicon,
    int strong,
  ) async {
    final groups = <List<String>>[];
    final words = <String>[];
    for (final segment in lexicon.crossLingual.segment(text)) {
      if (lexicon.crossLingual.isDropped(segment)) continue;
      final candidates = lexicon.crossLingual.candidatesOf(segment);
      if (candidates == null || candidates.isEmpty) continue;
      groups.add(candidates);
      words.add(segment);
    }
    // One known word only helps when nothing matched literally.
    if (groups.isEmpty || (groups.length == 1 && strong > 0)) return const [];
    final records = await _catalog.searchTokenGroups(groups);
    final scored = <(double, TagCatalogRecord)>[];
    for (final record in records) {
      final extra = _unmatchedWords(record.canonicalTag, groups);
      scored.add((1 / (1 + extra), record));
    }
    scored.sort((a, b) {
      final quality = b.$1.compareTo(a.$1);
      if (quality != 0) return quality;
      return b.$2.postCount.compareTo(a.$2.postCount);
    });
    final hint = words.join('·');
    return [
      for (final (quality, record) in scored.take(_perStage))
        CompletionCandidate(
          canonicalTag: record.canonicalTag,
          category: record.category,
          postCount: record.postCount,
          matchKind: CompletionMatchKind.crossLingual,
          sources: const {CompletionSourceKind.base},
          matchHint: hint,
          matchQuality: quality,
        ),
    ];
  }

  // ------------------------------------------------------------ letters

  Future<List<CompletionCandidate>> _letters(
    CompletionQuery query,
    String token,
    List<CompletionCandidate> primary,
    AutocompleteSettings settings,
  ) async {
    final results = <CompletionCandidate>[];
    if (settings.pinyinSearchEnabled) {
      final letters = token.toLowerCase().replaceAll(_separators, '');
      if (letters.length >= 2) {
        results.addAll(await _pinyinLetters(letters, settings));
      }
    }
    // Letters that read as whole syllables with matches are pinyin, not an
    // English typo (chenshan is not a misspelt henshin).
    final readsAsPinyin = results.any(
      (row) =>
          row.matchQuality >= 1 &&
          (row.matchKind == CompletionMatchKind.pinyin ||
              row.matchKind == CompletionMatchKind.shuangpin),
    );
    final literal = primary.any(
      (row) => _literalEnglish.contains(row.matchKind),
    );
    if (settings.spellCorrectionEnabled && !literal && !readsAsPinyin) {
      results.addAll(await _englishFallbacks(query, token));
    }
    return results;
  }

  Future<List<CompletionCandidate>> _englishFallbacks(
    CompletionQuery query,
    String token,
  ) async {
    final words = token
        .toLowerCase()
        .split(_separators)
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return const [];
    final results = <CompletionCandidate>[];

    final stems = words.map(EnglishWords.stem).toList(growable: false);
    if (stems.join('_') != words.join('_')) {
      results.addAll(
        await _searchRewritten(
          query,
          stems,
          CompletionMatchKind.englishVariant,
          1,
        ),
      );
    }

    final weights = await _index.vocabularyWeights(
      words.where((word) => word.length >= 4),
    );
    final corrected = [...words];
    var changed = false;
    var distance = 0;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.length < 4 || weights.containsKey(word)) continue;
      final suggestions = await _index.spellingSuggestions(word, limit: 1);
      if (suggestions.isEmpty) continue;
      corrected[i] = suggestions.first.word;
      distance += suggestions.first.distance;
      changed = true;
    }
    if (changed) {
      results.addAll(
        await _searchRewritten(
          query,
          corrected,
          CompletionMatchKind.spellCorrected,
          1 / (1 + distance),
        ),
      );
    }
    return results;
  }

  Future<List<CompletionCandidate>> _searchRewritten(
    CompletionQuery query,
    List<String> words,
    CompletionMatchKind kind,
    double quality,
  ) async {
    final rewritten = words.join('_');
    final rows = await _catalog.search(
      query.copyWith(token: rewritten, limit: _perStage),
    );
    return [
      for (final row in rows)
        if (_literalEnglish.contains(row.matchKind))
          row.copyWith(
            matchKind: kind,
            matchHint: words.join(' '),
            // Exact rewrites ahead of prefix rewrites.
            matchQuality:
                quality *
                (row.matchKind == CompletionMatchKind.englishExact ||
                        row.matchKind == CompletionMatchKind.aliasExact
                    ? 1
                    : 0.7),
          ),
    ];
  }

  Future<List<CompletionCandidate>> _pinyinLetters(
    String letters,
    AutocompleteSettings settings,
  ) async {
    final lexicon = await _lexicon();
    final syllables = lexicon.pinyin.syllables;
    final best = <String, CompletionCandidate>{};

    Future<void> run(
      List<String> pieces, {
      required bool partialLast,
      required CompletionMatchKind kind,
      bool prefixesOnly = false,
    }) async {
      final terms = [
        for (var i = 0; i < pieces.length; i++)
          prefixesOnly || (partialLast && i == pieces.length - 1)
              ? '${pieces[i]}*'
              : pieces[i],
      ];
      final rows = await _index.pinyinMatches(
        'py : (^${terms.join(' + ')})',
        limit: 120,
      );
      for (final row in rows) {
        final sameLength = row.pinyin.split(' ').length == pieces.length;
        // Initials are loose enough already: only labels of that length.
        if (prefixesOnly && !sameLength) continue;
        final quality = !sameLength
            ? 0.6
            : partialLast
            ? 0.8
            : 1.0;
        _keepBest(best, _labelCandidate(row, kind, quality));
      }
    }

    if (settings.pinyinFullEnabled) {
      for (final split in syllables.splitFullPinyin(letters)) {
        await run(
          split.pieces,
          partialLast: split.partialLast,
          kind: CompletionMatchKind.pinyin,
        );
      }
    }
    if (settings.pinyinZiranmaEnabled) {
      final split = syllables.splitZiranma(letters);
      if (split != null) {
        await run(
          split.pieces,
          partialLast: split.partialLast,
          kind: CompletionMatchKind.shuangpin,
        );
      }
    }
    if (letters.length <= 8) {
      final letterList = letters.split('');
      if (settings.pinyinFullEnabled &&
          letterList.every(PinyinSyllables.isFullInitialLetter)) {
        await run(
          letterList,
          partialLast: false,
          kind: CompletionMatchKind.pinyinInitials,
          prefixesOnly: true,
        );
      }
      if (settings.pinyinZiranmaEnabled &&
          letterList.any(
            (letter) => !PinyinSyllables.isFullInitialLetter(letter),
          )) {
        await run(
          letterList.map(PinyinSyllables.ziranmaInitialOf).toList(),
          partialLast: false,
          kind: CompletionMatchKind.pinyinInitials,
          prefixesOnly: true,
        );
      }
    }
    return _top(best.values);
  }

  // ------------------------------------------------------------ helpers

  /// Syllables in order at the start of a reading.
  static String _phrase(List<String> syllables) =>
      '(^${syllables.join(' + ')})';

  static String _expression(String column, List<String> phrases) =>
      '$column : (${phrases.toSet().join(' OR ')})';

  /// 1 for the same syllables, 0.6 when the label starts with them, 0
  /// otherwise.
  static double _sequenceQuality(List<String> label, List<String> query) {
    if (label.length < query.length) return 0;
    for (var i = 0; i < query.length; i++) {
      if (label[i] != query[i]) return 0;
    }
    return label.length == query.length ? 1 : 0.6;
  }

  static int _lcs(List<String> a, List<String> b) {
    var previous = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      for (var j = 1; j <= b.length; j++) {
        current[j] = a[i - 1] == b[j - 1]
            ? previous[j - 1] + 1
            : math.max(previous[j], current[j - 1]);
      }
      previous = current;
    }
    return previous[b.length];
  }

  static const Set<String> _stopWords = {
    'on',
    'in',
    'with',
    'of',
    'the',
    'a',
    'an',
    'at',
    'to',
    'from',
    'by',
    'and',
    'own',
    'up',
  };

  /// Content words of [tag] that no query word accounts for.
  static int _unmatchedWords(String tag, List<List<String>> groups) {
    final stems = {
      for (final group in groups)
        for (final candidate in group)
          for (final word in candidate.split('_'))
            if (word.isNotEmpty) EnglishWords.stem(word),
    };
    var extra = 0;
    for (final word in tag.toLowerCase().split(RegExp('[^a-z0-9]+'))) {
      if (word.isEmpty || _stopWords.contains(word)) continue;
      if (!stems.any(word.startsWith)) extra++;
    }
    return extra;
  }

  static CompletionCandidate _labelCandidate(
    LexicalLabelMatch row,
    CompletionMatchKind kind,
    double quality,
  ) => CompletionCandidate(
    canonicalTag: row.tag,
    category: _category(row.category),
    postCount: row.postCount,
    translation: row.label,
    matchKind: kind,
    sources: const {CompletionSourceKind.base},
    matchQuality: quality,
  );

  static TagCategory _category(int value) => TagCategory.values.firstWhere(
    (category) => category.value == value,
    orElse: () => TagCategory.general,
  );

  static void _keepBest(
    Map<String, CompletionCandidate> best,
    CompletionCandidate candidate,
  ) {
    final current = best[candidate.stableId];
    if (current == null ||
        candidate.matchQuality > current.matchQuality ||
        (candidate.matchQuality == current.matchQuality &&
            candidate.matchKind.index < current.matchKind.index)) {
      best[candidate.stableId] = candidate;
    }
  }

  static List<CompletionCandidate> _top(Iterable<CompletionCandidate> rows) {
    final ordered = rows.toList()
      ..sort((a, b) {
        final quality = b.matchQuality.compareTo(a.matchQuality);
        if (quality != 0) return quality;
        return b.postCount.compareTo(a.postCount);
      });
    return ordered.take(_perStage).toList(growable: false);
  }
}
