enum TagCategory {
  general(0),
  artist(1),
  copyright(3),
  character(4),
  meta(5),
  contributor(9),
  species(12),
  lore(15),
  library(99);

  const TagCategory(this.value);

  final int value;

  static TagCategory? fromDanbooru(int value) => switch (value) {
    0 => TagCategory.general,
    1 => TagCategory.artist,
    3 => TagCategory.copyright,
    4 => TagCategory.character,
    5 => TagCategory.meta,
    _ => null,
  };

  /// The bundled LoRA Manager catalog preserves both Danbooru and e621's
  /// source category IDs. Equivalent categories share the same presentation;
  /// e621-only concepts retain their own identities.
  static TagCategory? fromCatalog(int value) => switch (value) {
    0 || 7 => TagCategory.general,
    1 || 8 => TagCategory.artist,
    3 || 10 => TagCategory.copyright,
    4 || 11 => TagCategory.character,
    5 || 14 => TagCategory.meta,
    9 => TagCategory.contributor,
    12 => TagCategory.species,
    15 => TagCategory.lore,
    _ => null,
  };
}

abstract final class CompletionResultLimits {
  /// A practical exhaustive target for the complete 221k-tag merged catalog.
  ///
  /// One-character queries remain separately bounded because they can match a
  /// large fraction of the catalog before the user has finished typing.
  static const int all = 300000;
  static const int _legacyAll = 200000;
  static const int oneCharacter = 100;
  static const int danbooruPageSize = 1000;
  static const int initialRelatedTags = 100;
  static const int maxRelatedTags = 25000;

  static bool isAll(int value) => value >= _legacyAll;
}

enum CompletionSourceKind {
  base,
  zhDictionary,
  danbooruApi,
  cooccurrence,
  ai,
  library,
}

enum CompletionQueryKind { tag, libraryAlias }

enum CompletionMatchKind {
  englishExact,
  englishPrefix,
  aliasExact,
  aliasPrefix,
  chineseExact,
  chinesePrefix,
  chineseContains,
  related,
  fullText,

  /// A Chinese label that reads the same as the Chinese query (陈山 → 衬衫).
  homophone,

  /// An English query with a typo, matched after correcting it.
  spellCorrected,

  /// An English query matched through another form of its word (socks/sock).
  englishVariant,

  /// Letters read as full pinyin (chenshan → 衬衫).
  pinyin,

  /// Letters read as Ziranma double pinyin (ifuj → 衬衫).
  shuangpin,

  /// A Chinese query split into words and searched as English tag tokens.
  crossLingual,

  /// A Chinese label sharing most characters, in order, with the query.
  approximate,

  /// A label that sounds alike under the enabled fuzzy-sound pairs.
  fuzzyPinyin,

  /// Letters read as syllable initials (cs → 衬衫).
  pinyinInitials,
}

class TextReplacementRange {
  const TextReplacementRange({required this.start, required this.end});

  final int start;
  final int end;
}

class CompletionQuery {
  const CompletionQuery({
    required this.fullText,
    required this.cursorPosition,
    required this.token,
    required this.replacementRange,
    required this.existingTags,
    required this.limit,
    required this.locale,
    this.relatedTag,
    this.categoryFilter,
    this.kind = CompletionQueryKind.tag,
  });

  final String fullText;
  final int cursorPosition;
  final String token;
  final TextReplacementRange replacementRange;
  final Set<String> existingTags;
  final int limit;
  final String locale;
  final String? relatedTag;
  final TagCategory? categoryFilter;
  final CompletionQueryKind kind;

  static final RegExp _chineseCharacter = RegExp(r'[\u3400-\u9fff]');

  bool get isChinese => _chineseCharacter.hasMatch(token);
  bool get isEnglish => !isChinese;

  CompletionQuery copyWith({
    String? fullText,
    int? cursorPosition,
    String? token,
    TextReplacementRange? replacementRange,
    Set<String>? existingTags,
    int? limit,
    String? locale,
    String? relatedTag,
    bool clearRelatedTag = false,
    TagCategory? categoryFilter,
    bool clearCategoryFilter = false,
    CompletionQueryKind? kind,
  }) {
    return CompletionQuery(
      fullText: fullText ?? this.fullText,
      cursorPosition: cursorPosition ?? this.cursorPosition,
      token: token ?? this.token,
      replacementRange: replacementRange ?? this.replacementRange,
      existingTags: existingTags ?? this.existingTags,
      limit: limit ?? this.limit,
      locale: locale ?? this.locale,
      relatedTag: clearRelatedTag ? null : relatedTag ?? this.relatedTag,
      categoryFilter: clearCategoryFilter
          ? null
          : categoryFilter ?? this.categoryFilter,
      kind: kind ?? this.kind,
    );
  }
}

class CompletionCandidate {
  const CompletionCandidate({
    required this.canonicalTag,
    required this.category,
    required this.postCount,
    required this.matchKind,
    required this.sources,
    this.aliases = const [],
    this.translation,
    this.matchedAlias,
    this.isExisting = false,
    this.isTranslating = false,
    this.relatedScore,
    this.cooccurrenceCount,
    this.score = 0,
    this.semanticScore,
    this.matchHint,
    this.matchQuality = 0,
  });

  final String canonicalTag;
  final TagCategory category;
  final int postCount;
  final List<String> aliases;
  final String? translation;
  final String? matchedAlias;
  final CompletionMatchKind matchKind;
  final Set<CompletionSourceKind> sources;
  final bool isExisting;
  final bool isTranslating;

  /// Jaccard similarity in the inclusive range 0..1 for related-tag rows.
  final double? relatedScore;

  /// Number of posts in which the source and candidate tags co-occur.
  final int? cooccurrenceCount;
  final double score;

  /// Cosine similarity from the optional local E5 source, preserved on merge.
  final double? semanticScore;

  /// What a non-literal match went through: the corrected word, or the
  /// Chinese words a cross-lingual query was split into.
  final String? matchHint;

  /// 0..1 closeness within the match kind (exact over prefix over contains);
  /// orders rows of the same kind before popularity.
  final double matchQuality;

  String get stableId => canonicalTag.toLowerCase();

  CompletionCandidate copyWith({
    TagCategory? category,
    int? postCount,
    List<String>? aliases,
    String? translation,
    bool clearTranslation = false,
    String? matchedAlias,
    CompletionMatchKind? matchKind,
    Set<CompletionSourceKind>? sources,
    bool? isExisting,
    bool? isTranslating,
    double? relatedScore,
    int? cooccurrenceCount,
    double? score,
    double? semanticScore,
    String? matchHint,
    double? matchQuality,
  }) {
    return CompletionCandidate(
      canonicalTag: canonicalTag,
      category: category ?? this.category,
      postCount: postCount ?? this.postCount,
      aliases: aliases ?? this.aliases,
      translation: clearTranslation ? null : translation ?? this.translation,
      matchedAlias: matchedAlias ?? this.matchedAlias,
      matchKind: matchKind ?? this.matchKind,
      sources: sources ?? this.sources,
      isExisting: isExisting ?? this.isExisting,
      isTranslating: isTranslating ?? this.isTranslating,
      relatedScore: relatedScore ?? this.relatedScore,
      cooccurrenceCount: cooccurrenceCount ?? this.cooccurrenceCount,
      score: score ?? this.score,
      semanticScore: semanticScore ?? this.semanticScore,
      matchHint: matchHint ?? this.matchHint,
      matchQuality: matchQuality ?? this.matchQuality,
    );
  }
}

abstract interface class CompletionSource {
  Future<List<CompletionCandidate>> search(CompletionQuery query);
}

/// Adds rows after the primary sources answered, knowing what they found;
/// used for fallbacks that only make sense when literal matches are scarce.
abstract interface class SupplementalCompletionSource {
  Future<List<CompletionCandidate>> supplement(
    CompletionQuery query,
    List<CompletionCandidate> primary,
  );
}

/// Score boosts per candidate stable id from context and habits.
abstract interface class CompletionRankingSignals {
  Future<Map<String, double>> boosts(CompletionQuery query);
}

abstract interface class TranslationResolver {
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  });
}

abstract interface class CachedTranslationResolver
    implements TranslationResolver {
  Future<Map<String, String>> resolveCached(
    List<String> canonicalTags, {
    required String locale,
  });
}

abstract interface class CancellableTranslationResolver
    implements TranslationResolver {
  void cancelPending();
}

abstract interface class ScopedTranslationResolver
    implements TranslationResolver {
  TranslationResolver createScope();
}

class CompletionState {
  const CompletionState({
    this.query,
    this.candidates = const [],
    this.isLocalLoading = false,
    this.isRemoteLoading = false,
    this.localError,
    this.remoteError,
    this.translationError,
  });

  final CompletionQuery? query;
  final List<CompletionCandidate> candidates;
  final bool isLocalLoading;
  final bool isRemoteLoading;
  final String? localError;
  final String? remoteError;
  final String? translationError;

  CompletionState copyWith({
    CompletionQuery? query,
    List<CompletionCandidate>? candidates,
    bool? isLocalLoading,
    bool? isRemoteLoading,
    String? localError,
    bool clearLocalError = false,
    String? remoteError,
    bool clearRemoteError = false,
    String? translationError,
    bool clearTranslationError = false,
  }) {
    return CompletionState(
      query: query ?? this.query,
      candidates: candidates ?? this.candidates,
      isLocalLoading: isLocalLoading ?? this.isLocalLoading,
      isRemoteLoading: isRemoteLoading ?? this.isRemoteLoading,
      localError: clearLocalError ? null : localError ?? this.localError,
      remoteError: clearRemoteError ? null : remoteError ?? this.remoteError,
      translationError: clearTranslationError
          ? null
          : translationError ?? this.translationError,
    );
  }
}
