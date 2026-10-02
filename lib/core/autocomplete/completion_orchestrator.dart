import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'autocomplete_settings.dart';
import 'completion_models.dart';
import 'completion_ranker.dart';
import 'danbooru_completion_source.dart';

class CompletionOrchestrator extends ChangeNotifier {
  CompletionOrchestrator({
    required List<CompletionSource> localSources,
    required TranslationResolver dictionaryTranslations,
    required TranslationResolver llmTranslations,
    required DanbooruCompletionSource danbooru,
    List<CompletionSource> tagLookupSources = const [],
    CompletionSource? libraryAliases,
    CompletionSource? semanticSource,
    List<SupplementalCompletionSource> supplementalSources = const [],
    CompletionRankingSignals? rankingSignals,
    Duration llmDebounceDuration = const Duration(milliseconds: 400),
  }) : _localSources = localSources,
       _tagLookupSources = tagLookupSources,
       _dictionaryTranslations = dictionaryTranslations,
       _llmTranslations = llmTranslations is ScopedTranslationResolver
           ? llmTranslations.createScope()
           : llmTranslations,
       _danbooru = danbooru,
       _libraryAliases = libraryAliases,
       _semanticSource = semanticSource,
       _supplementalSources = supplementalSources,
       _rankingSignals = rankingSignals,
       _llmDebounceDuration = llmDebounceDuration;

  final List<CompletionSource> _localSources;
  final List<CompletionSource> _tagLookupSources;
  final TranslationResolver _dictionaryTranslations;
  final TranslationResolver _llmTranslations;
  final DanbooruCompletionSource _danbooru;
  final CompletionSource? _libraryAliases;
  final CompletionSource? _semanticSource;
  final List<SupplementalCompletionSource> _supplementalSources;
  final CompletionRankingSignals? _rankingSignals;
  Timer? _semanticDebounce;

  /// Context and habit boosts of the current query, used by every merge.
  Map<String, double> _boosts = const {};
  bool _semanticPending = false;
  bool _supplementPending = false;
  final Duration _llmDebounceDuration;

  CompletionState _state = const CompletionState();
  CompletionState get state => _state;

  Timer? _remoteDebounce;
  Timer? _llmDebounce;
  int _sequence = 0;
  final Set<String> _llmRequested = {};
  List<String> _pendingLlmTags = const [];
  bool _llmInFlight = false;
  bool _disposed = false;

  /// Stops every in-flight completion branch and clears the visible snapshot.
  ///
  /// Closing a popup is an interaction decision, not merely a presentation
  /// change. Invalidating the sequence prevents a delayed local or remote result
  /// from reopening a popup that the user already dismissed.
  void cancel() {
    _semanticDebounce?.cancel();
    _sequence++;
    _cancelPendingLlmTranslation();
    _remoteDebounce?.cancel();
    _danbooru.cancelPending();
    _emit(const CompletionState());
  }

  Future<void> query(
    CompletionQuery query,
    AutocompleteSettings settings, {
    CompletionQuery? relatedFallbackQuery,
  }) async {
    final sequence = ++_sequence;
    _semanticDebounce?.cancel();
    _cancelPendingLlmTranslation();
    _remoteDebounce?.cancel();
    _danbooru.cancelPending();
    _boosts = const {};
    _semanticPending = false;
    _supplementPending = false;
    final requestedRelatedQuery =
        query.relatedTag != null && query.token.isEmpty;
    if (!settings.enabled ||
        (query.token.isEmpty &&
            query.relatedTag == null &&
            query.categoryFilter == null &&
            query.kind != CompletionQueryKind.libraryAlias) ||
        (requestedRelatedQuery && !settings.relatedTagsEnabled)) {
      _emit(CompletionState(query: query));
      return;
    }

    var effectiveQuery = query;
    if (requestedRelatedQuery &&
        relatedFallbackQuery != null &&
        _tagLookupSources.isNotEmpty) {
      final resolution = await _resolveRelatedTag(relatedFallbackQuery);
      if (!_isCurrent(sequence)) return;
      if (resolution != null) {
        effectiveQuery = resolution.isExact
            ? query.copyWith(relatedTag: resolution.canonicalTag)
            : relatedFallbackQuery;
      }
    }

    final isRelatedQuery =
        effectiveQuery.relatedTag != null && effectiveQuery.token.isEmpty;
    final isLibraryAlias =
        effectiveQuery.kind == CompletionQueryKind.libraryAlias;

    final canLoadRemote =
        !isLibraryAlias &&
        settings.danbooruEnabled &&
        (effectiveQuery.token.length >= 2 || isRelatedQuery);
    _emit(
      CompletionState(
        query: effectiveQuery,
        candidates: const [],
        isLocalLoading: true,
        isRemoteLoading: canLoadRemote,
      ),
    );
    final activeLocalSources = isLibraryAlias
        ? [_libraryAliases].whereType<CompletionSource>()
        : _localSources;
    final expandsRelatedResults =
        isRelatedQuery &&
        effectiveQuery.limit > CompletionResultLimits.initialRelatedTags;
    final initialQuery = expandsRelatedResults
        ? effectiveQuery.copyWith(
            limit: CompletionResultLimits.initialRelatedTags,
          )
        : effectiveQuery;
    final boosts = isLibraryAlias || isRelatedQuery
        ? Future.value(const <String, double>{})
        : _rankingBoosts(effectiveQuery);
    final localResults = await Future.wait(
      activeLocalSources.map((source) async {
        try {
          return _LocalSourceResult(await source.search(initialQuery));
        } catch (error) {
          return _LocalSourceResult(
            const <CompletionCandidate>[],
            error: '${source.runtimeType}: $error',
          );
        }
      }),
    );
    final localBatches = localResults.map(
      (result) => _filterCategory(result.candidates, effectiveQuery),
    );
    final localErrors = localResults
        .map((result) => result.error)
        .whereType<String>()
        .toList(growable: false);
    final resolvedBoosts = await boosts;
    if (!_isCurrent(sequence)) return;
    _boosts = resolvedBoosts;
    var candidates = isLibraryAlias
        ? localBatches
              .expand((batch) => batch)
              .take(effectiveQuery.limit)
              .toList(growable: false)
        : CompletionRanker.mergeAndSort(
            localBatches.expand((batch) => batch),
            query: initialQuery,
            boosts: _boosts,
          );
    if (isRelatedQuery) {
      candidates = candidates
          .where((candidate) => !candidate.isExisting)
          .toList(growable: false);
    }
    candidates = await _applyDictionaryTranslations(
      candidates,
      initialQuery,
      sequence,
      settings,
    );
    candidates = await _applyCachedLlmTranslations(
      candidates,
      initialQuery,
      sequence,
      settings,
    );
    if (!_isCurrent(sequence)) return;
    final canLoadSemantic =
        !isLibraryAlias &&
        !isRelatedQuery &&
        effectiveQuery.isChinese &&
        effectiveQuery.token.trim().runes.length >= 2 &&
        (effectiveQuery.categoryFilter == null ||
            effectiveQuery.categoryFilter == TagCategory.general) &&
        _semanticSource != null;
    final canSupplement =
        !isLibraryAlias &&
        !isRelatedQuery &&
        effectiveQuery.token.trim().isNotEmpty &&
        _supplementalSources.isNotEmpty;
    _semanticPending = canLoadSemantic;
    _supplementPending = canSupplement;
    _emit(
      _state.copyWith(
        candidates: candidates,
        isLocalLoading:
            expandsRelatedResults || canLoadSemantic || canSupplement,
        localError: localErrors.isEmpty ? null : localErrors.join('\n'),
        clearLocalError: localErrors.isEmpty,
        isRemoteLoading: canLoadRemote,
      ),
    );
    _scheduleLlmTranslations(initialQuery, sequence, settings);
    if (canSupplement) {
      unawaited(
        _loadSupplements(effectiveQuery, sequence, settings, candidates),
      );
    }
    if (canLoadSemantic) {
      _semanticDebounce = Timer(const Duration(milliseconds: 250), () {
        unawaited(_loadSemantic(effectiveQuery, sequence, settings));
      });
    }
    if (expandsRelatedResults) {
      unawaited(_expandRelatedLocalResults(effectiveQuery, settings, sequence));
    }

    if (!canLoadRemote) {
      _emit(_state.copyWith(isRemoteLoading: false));
      return;
    }
    _remoteDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_loadRemote(effectiveQuery, sequence, settings));
    });
  }

  Future<void> _loadSemantic(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    try {
      var rows = await _semanticSource!.search(query);
      if (!_isCurrent(sequence)) return;
      // Use the same current dictionary/locale policy as lexical completion.
      // The frozen index labels describe its corpus, not user translation state.
      rows = rows.map((row) => row.copyWith(clearTranslation: true)).toList();
      rows = await _applyDictionaryTranslations(
        rows,
        query,
        sequence,
        settings,
      );
      if (!_isCurrent(sequence)) return;
      _semanticPending = false;
      _emit(
        _state.copyWith(
          isLocalLoading: _supplementPending,
          candidates: CompletionRanker.mergeAndSort(
            [..._state.candidates, ...rows],
            query: query,
            boosts: _boosts,
          ),
        ),
      );
    } catch (error) {
      if (_isCurrent(sequence)) {
        _semanticPending = false;
        final existing = _state.localError;
        _emit(
          _state.copyWith(
            isLocalLoading: _supplementPending,
            localError: [
              if (existing != null) existing,
              'E5: $error',
            ].join('\n'),
          ),
        );
      }
    }
  }

  Future<Map<String, double>> _rankingBoosts(CompletionQuery query) async {
    final signals = _rankingSignals;
    if (signals == null) return const {};
    try {
      return await signals.boosts(query);
    } catch (_) {
      return const {};
    }
  }

  /// Pinyin, approximate, cross-lingual and spelling fallbacks: they see the
  /// literal results first and add rows ranked below them.
  Future<void> _loadSupplements(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
    List<CompletionCandidate> primary,
  ) async {
    final errors = <String>[];
    final batches = await Future.wait(
      _supplementalSources.map((source) async {
        try {
          return await source.supplement(query, primary);
        } catch (error) {
          errors.add('${source.runtimeType}: $error');
          return const <CompletionCandidate>[];
        }
      }),
    );
    if (!_isCurrent(sequence)) return;
    var rows = batches.expand((batch) => batch).toList(growable: false);
    rows = await _applyDictionaryTranslations(rows, query, sequence, settings);
    rows = await _applyCachedLlmTranslations(rows, query, sequence, settings);
    if (!_isCurrent(sequence)) return;
    _supplementPending = false;
    final existing = _state.localError;
    _emit(
      _state.copyWith(
        isLocalLoading: _semanticPending,
        candidates: rows.isEmpty
            ? _state.candidates
            : CompletionRanker.mergeAndSort(
                [..._state.candidates, ...rows],
                query: query,
                boosts: _boosts,
              ),
        localError: errors.isEmpty
            ? existing
            : [if (existing != null) existing, ...errors].join('\n'),
      ),
    );
    if (rows.isNotEmpty) _scheduleLlmTranslations(query, sequence, settings);
  }

  Future<_RelatedTagResolution?> _resolveRelatedTag(
    CompletionQuery fallbackQuery,
  ) async {
    // Prefix matches must stay in normal completion so an incomplete tag is
    // never guessed as the source of a related-tag query.
    final lookupQuery = fallbackQuery.copyWith(
      limit: math.min(fallbackQuery.limit, 20),
    );
    final results = await Future.wait(
      _tagLookupSources.map((source) async {
        try {
          return await source.search(lookupQuery);
        } catch (_) {
          return const <CompletionCandidate>[];
        }
      }),
    );
    final candidates = CompletionRanker.mergeAndSort(
      results.expand((batch) => batch),
      query: lookupQuery,
    );
    if (candidates.isEmpty) return null;

    final exact = candidates.where(_isExactTagMatch).firstOrNull;
    return _RelatedTagResolution(
      canonicalTag: (exact ?? candidates.first).canonicalTag,
      isExact: exact != null,
    );
  }

  static bool _isExactTagMatch(CompletionCandidate candidate) =>
      switch (candidate.matchKind) {
        CompletionMatchKind.englishExact ||
        CompletionMatchKind.aliasExact ||
        CompletionMatchKind.chineseExact => true,
        _ => false,
      };

  Future<void> _expandRelatedLocalResults(
    CompletionQuery query,
    AutocompleteSettings settings,
    int sequence,
  ) async {
    final localResults = await Future.wait(
      _localSources.map((source) async {
        try {
          return _LocalSourceResult(await source.search(query));
        } catch (error) {
          return _LocalSourceResult(
            const <CompletionCandidate>[],
            error: '${source.runtimeType}: $error',
          );
        }
      }),
    );
    if (!_isCurrent(sequence)) return;

    final localErrors = localResults
        .map((result) => result.error)
        .whereType<String>()
        .toList(growable: false);
    var expanded = CompletionRanker.mergeAndSort(
      localResults.expand((result) => result.candidates),
      query: query,
    ).where((candidate) => !candidate.isExisting).toList(growable: false);
    expanded = await _applyDictionaryTranslations(
      expanded,
      query,
      sequence,
      settings,
    );
    expanded = await _applyCachedLlmTranslations(
      expanded,
      query,
      sequence,
      settings,
    );
    if (!_isCurrent(sequence)) return;

    final merged = CompletionRanker.mergeAndSort(
      [..._state.candidates, ...expanded],
      query: query,
    ).where((candidate) => !candidate.isExisting).toList(growable: false);
    _emit(
      _state.copyWith(
        candidates: merged,
        isLocalLoading: false,
        localError: localErrors.isEmpty ? null : localErrors.join('\n'),
        clearLocalError: localErrors.isEmpty,
      ),
    );
  }

  Future<List<CompletionCandidate>> _applyDictionaryTranslations(
    List<CompletionCandidate> candidates,
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    if (query.kind == CompletionQueryKind.libraryAlias ||
        !settings.showTranslations ||
        candidates.isEmpty) {
      return candidates;
    }
    final missing = candidates
        .where((candidate) => candidate.translation?.isNotEmpty != true)
        .map((candidate) => candidate.canonicalTag)
        .toList();
    Map<String, String> translations;
    try {
      translations = await _dictionaryTranslations.resolve(
        missing,
        locale: query.locale,
      );
    } catch (_) {
      return candidates;
    }
    if (!_isCurrent(sequence) || translations.isEmpty) return candidates;
    return candidates
        .map(
          (candidate) => translations[candidate.canonicalTag] == null
              ? candidate
              : candidate.copyWith(
                  translation: translations[candidate.canonicalTag],
                  sources: {
                    ...candidate.sources,
                    CompletionSourceKind.zhDictionary,
                  },
                ),
        )
        .toList(growable: false);
  }

  Future<List<CompletionCandidate>> _applyCachedLlmTranslations(
    List<CompletionCandidate> candidates,
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    final resolver = _llmTranslations;
    if (resolver is! CachedTranslationResolver ||
        query.kind == CompletionQueryKind.libraryAlias ||
        !settings.showTranslations ||
        !settings.llmTranslationEnabled ||
        !query.locale.toLowerCase().startsWith('zh') ||
        candidates.isEmpty) {
      return candidates;
    }
    final missing = candidates
        .where((candidate) => candidate.translation?.isNotEmpty != true)
        .map((candidate) => candidate.canonicalTag)
        .toList(growable: false);
    if (missing.isEmpty) return candidates;
    Map<String, String> translations;
    try {
      translations = await resolver.resolveCached(
        missing,
        locale: query.locale,
      );
    } catch (_) {
      return candidates;
    }
    if (!_isCurrent(sequence) || translations.isEmpty) return candidates;
    return candidates
        .map((candidate) {
          final translation = translations[candidate.canonicalTag];
          return translation == null
              ? candidate
              : candidate.copyWith(
                  translation: translation,
                  sources: {...candidate.sources, CompletionSourceKind.ai},
                );
        })
        .toList(growable: false);
  }

  Future<void> _loadRemote(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    List<CompletionCandidate> remote;
    try {
      remote = query.relatedTag != null && query.token.isEmpty
          ? await _danbooru.relatedTags(query.relatedTag!, limit: query.limit)
          : await _danbooru.search(query);
    } catch (error) {
      if (_isCurrent(sequence)) {
        _emit(
          _state.copyWith(
            isRemoteLoading: false,
            remoteError: error.toString(),
          ),
        );
      }
      return;
    }
    if (!_isCurrent(sequence)) return;
    remote = _filterCategory(remote, query);
    var merged = _mergeRemoteWithoutReordering(
      local: _state.candidates,
      remote: remote,
      query: query,
    );
    if (query.relatedTag != null) {
      merged = merged
          .where((candidate) => !candidate.isExisting)
          .toList(growable: false);
    }
    merged = await _applyDictionaryTranslations(
      merged,
      query,
      sequence,
      settings,
    );
    merged = await _applyCachedLlmTranslations(
      merged,
      query,
      sequence,
      settings,
    );
    if (!_isCurrent(sequence)) return;
    merged = _preserveCurrentTranslationState(merged);
    final semantic = _state.candidates.where(
      (row) => row.semanticScore != null,
    );
    if (semantic.isNotEmpty) {
      merged = CompletionRanker.mergeAndSort(
        [...merged, ...semantic],
        query: query,
        boosts: _boosts,
      );
    }
    final remoteError = _danbooru.lastError;
    _emit(
      _state.copyWith(
        candidates: merged,
        isRemoteLoading: false,
        remoteError: remoteError,
        clearRemoteError: remoteError == null,
      ),
    );
    _scheduleLlmTranslations(query, sequence, settings);
  }

  List<CompletionCandidate> _preserveCurrentTranslationState(
    List<CompletionCandidate> candidates,
  ) {
    final currentByTag = {
      for (final candidate in _state.candidates)
        candidate.canonicalTag: candidate,
    };
    return candidates
        .map((candidate) {
          final current = currentByTag[candidate.canonicalTag];
          if (current == null) return candidate;
          final currentTranslation = current.translation;
          return candidate.copyWith(
            translation: currentTranslation?.isNotEmpty == true
                ? currentTranslation
                : candidate.translation,
            sources: {...candidate.sources, ...current.sources},
            isTranslating: current.isTranslating,
          );
        })
        .toList(growable: false);
  }

  List<CompletionCandidate> _mergeRemoteWithoutReordering({
    required List<CompletionCandidate> local,
    required List<CompletionCandidate> remote,
    required CompletionQuery query,
  }) {
    final localIds = local.map((candidate) => candidate.stableId).toSet();
    final mergedPool = CompletionRanker.mergeAndSort(
      [...local, ...remote],
      query: query,
      limit: local.length + remote.length,
      boosts: _boosts,
    );
    final byId = {
      for (final candidate in mergedPool) candidate.stableId: candidate,
    };
    final stableLocal = local
        .map((candidate) => byId[candidate.stableId] ?? candidate)
        .toList(growable: false);
    final onlineOnly = mergedPool
        .where((candidate) => !localIds.contains(candidate.stableId))
        .toList(growable: false);

    // Local rows stay in place while online-only tags are appended. Reserving
    // extra rows is the only way to expose new Danbooru tags without replacing
    // the already-visible local list or moving the keyboard selection.
    if (CompletionResultLimits.isAll(query.limit)) {
      return [...stableLocal, ...onlineOnly];
    }
    final baselineGap = math.max(0, query.limit - stableLocal.length);
    final supplementLimit = ((query.limit + 1) ~/ 2).clamp(1, 50);
    final remoteSlots = math.max(baselineGap, supplementLimit);
    return [...stableLocal, ...onlineOnly.take(remoteSlots)];
  }

  static List<CompletionCandidate> _filterCategory(
    List<CompletionCandidate> candidates,
    CompletionQuery query,
  ) {
    final category = query.categoryFilter;
    if (category == null) return candidates;
    return candidates
        .where((candidate) => candidate.category == category)
        .toList(growable: false);
  }

  void _scheduleLlmTranslations(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) {
    if (_llmRequested.isNotEmpty ||
        _llmInFlight ||
        _pendingLlmTags.isNotEmpty) {
      return;
    }
    _queueVisibleLlmTranslations(
      query: query,
      sequence: sequence,
      settings: settings,
      candidates: _state.candidates.take(8),
      delay: _llmDebounceDuration,
    );
  }

  /// Requests translations only for the latest settled viewport.
  ///
  /// Callers debounce scroll movement before invoking this method. Replacing
  /// the pending batch prevents a fast scroll from billing for every row that
  /// merely passed through the viewport.
  void translateVisibleCandidates({
    required int firstIndex,
    required int lastIndex,
    required AutocompleteSettings settings,
  }) {
    final query = _state.query;
    if (query == null || _state.candidates.isEmpty) return;
    final first = firstIndex.clamp(0, _state.candidates.length - 1);
    final last = lastIndex.clamp(first, _state.candidates.length - 1);
    _queueVisibleLlmTranslations(
      query: query,
      sequence: _sequence,
      settings: settings,
      candidates: _state.candidates.getRange(first, last + 1),
      delay: Duration.zero,
    );
  }

  void _queueVisibleLlmTranslations({
    required CompletionQuery query,
    required int sequence,
    required AutocompleteSettings settings,
    required Iterable<CompletionCandidate> candidates,
    required Duration delay,
  }) {
    if (query.kind == CompletionQueryKind.libraryAlias ||
        !settings.showTranslations ||
        !settings.llmTranslationEnabled ||
        !query.locale.toLowerCase().startsWith('zh')) {
      return;
    }
    _llmDebounce?.cancel();
    _llmDebounce = null;
    _pendingLlmTags = candidates
        .where(
          (candidate) =>
              candidate.translation?.isNotEmpty != true &&
              !candidate.isTranslating &&
              !_llmRequested.contains(candidate.canonicalTag),
        )
        .map((candidate) => candidate.canonicalTag)
        .take(8)
        .toList(growable: false);
    if (_pendingLlmTags.isEmpty || _llmInFlight) return;
    _llmDebounce = Timer(delay, () {
      _llmDebounce = null;
      _startPendingLlmTranslation(query, sequence);
    });
  }

  void _startPendingLlmTranslation(CompletionQuery query, int sequence) {
    if (!_isCurrent(sequence) || _llmInFlight) return;
    final missing = _pendingLlmTags
        .where(
          (tag) =>
              !_llmRequested.contains(tag) &&
              _state.candidates.any(
                (candidate) =>
                    candidate.canonicalTag == tag &&
                    candidate.translation?.isNotEmpty != true,
              ),
        )
        .take(8)
        .toList(growable: false);
    _pendingLlmTags = const [];
    if (missing.isEmpty) return;
    _llmInFlight = true;
    _llmRequested.addAll(missing);
    final missingSet = missing.toSet();
    _emit(
      _state.copyWith(
        candidates: _state.candidates
            .map(
              (candidate) => missingSet.contains(candidate.canonicalTag)
                  ? candidate.copyWith(isTranslating: true)
                  : candidate,
            )
            .toList(growable: false),
      ),
    );
    unawaited(_resolveLlm(missing, query, sequence));
  }

  Future<void> _resolveLlm(
    List<String> missing,
    CompletionQuery query,
    int sequence,
  ) async {
    try {
      final translations = await _llmTranslations.resolve(
        missing,
        locale: query.locale,
      );
      if (!_isCurrent(sequence)) return;
      _emit(
        _state.copyWith(
          candidates: _state.candidates
              .map((candidate) {
                if (!missing.contains(candidate.canonicalTag)) return candidate;
                final translation = translations[candidate.canonicalTag];
                return candidate.copyWith(
                  translation: translation,
                  isTranslating: false,
                  sources: translation == null
                      ? candidate.sources
                      : {...candidate.sources, CompletionSourceKind.ai},
                );
              })
              .toList(growable: false),
          clearTranslationError: true,
        ),
      );
    } catch (error) {
      if (!_isCurrent(sequence)) return;
      _emit(
        _state.copyWith(
          candidates: _state.candidates
              .map(
                (candidate) => missing.contains(candidate.canonicalTag)
                    ? candidate.copyWith(isTranslating: false)
                    : candidate,
              )
              .toList(growable: false),
          translationError: error.toString(),
        ),
      );
    } finally {
      if (_isCurrent(sequence)) {
        _llmInFlight = false;
        _startPendingLlmTranslation(query, sequence);
      }
    }
  }

  bool _isCurrent(int sequence) => !_disposed && sequence == _sequence;

  void _cancelPendingLlmTranslation() {
    _llmDebounce?.cancel();
    _llmDebounce = null;
    _llmRequested.clear();
    _pendingLlmTags = const [];
    _llmInFlight = false;
    final resolver = _llmTranslations;
    if (resolver is CancellableTranslationResolver) {
      resolver.cancelPending();
    }
  }

  void _emit(CompletionState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _semanticDebounce?.cancel();
    _disposed = true;
    _sequence++;
    _cancelPendingLlmTranslation();
    _remoteDebounce?.cancel();
    _danbooru.cancelPending();
    super.dispose();
  }
}

class _LocalSourceResult {
  const _LocalSourceResult(this.candidates, {this.error});

  final List<CompletionCandidate> candidates;
  final String? error;
}

class _RelatedTagResolution {
  const _RelatedTagResolution({
    required this.canonicalTag,
    required this.isExact,
  });

  final String canonicalTag;
  final bool isExact;
}
