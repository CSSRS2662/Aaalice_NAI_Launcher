import 'completion_models.dart';

class CompletionRanker {
  const CompletionRanker._();

  /// Merges rows of the same tag and sorts them. [boosts] (context and
  /// habit, by stable id) reorder rows within a match kind, never across.
  static List<CompletionCandidate> mergeAndSort(
    Iterable<CompletionCandidate> candidates, {
    required CompletionQuery query,
    int? limit,
    Map<String, double> boosts = const {},
  }) {
    final merged = <String, CompletionCandidate>{};
    for (final incoming in candidates) {
      final key = incoming.stableId;
      final existing = merged[key];
      if (existing == null) {
        merged[key] = _score(
          incoming.copyWith(isExisting: query.existingTags.contains(key)),
          query,
          boosts,
        );
        continue;
      }

      final baseOwnsRecord = existing.sources.contains(
        CompletionSourceKind.base,
      );
      final aliases = <String>{
        ...existing.aliases,
        ...incoming.aliases,
      }.toList()..sort();
      final sources = <CompletionSourceKind>{
        ...existing.sources,
        ...incoming.sources,
      };
      final incomingWins =
          _matchPriority(incoming.matchKind) <
              _matchPriority(existing.matchKind) ||
          (incoming.matchKind == existing.matchKind &&
              incoming.matchQuality > existing.matchQuality);
      final matchKind = incomingWins ? incoming.matchKind : existing.matchKind;
      final translation = existing.translation?.trim().isNotEmpty == true
          ? existing.translation
          : incoming.translation;
      final matchedAlias = existing.matchedAlias ?? incoming.matchedAlias;
      final mergedCandidate = CompletionCandidate(
        canonicalTag: existing.canonicalTag,
        category: baseOwnsRecord ? existing.category : incoming.category,
        postCount: baseOwnsRecord ? existing.postCount : incoming.postCount,
        aliases: aliases,
        translation: translation,
        matchedAlias: matchedAlias,
        matchKind: matchKind,
        sources: sources,
        isExisting: query.existingTags.contains(key),
        isTranslating: existing.isTranslating || incoming.isTranslating,
        relatedScore: _greaterNullable(
          existing.relatedScore,
          incoming.relatedScore,
        ),
        cooccurrenceCount: _greaterNullable(
          existing.cooccurrenceCount,
          incoming.cooccurrenceCount,
        ),
        semanticScore: _greaterNullable(
          existing.semanticScore,
          incoming.semanticScore,
        ),
        matchHint: incomingWins ? incoming.matchHint : existing.matchHint,
        matchQuality: incomingWins
            ? incoming.matchQuality
            : existing.matchQuality,
      );
      merged[key] = _score(mergedCandidate, query, boosts);
    }

    final results = merged.values.toList()
      ..sort((a, b) {
        if (a.isExisting != b.isExisting) return a.isExisting ? 1 : -1;
        if (query.relatedTag != null) {
          final relatedScore = (b.relatedScore ?? 0).compareTo(
            a.relatedScore ?? 0,
          );
          if (relatedScore != 0) return relatedScore;
          final occurrences = (b.cooccurrenceCount ?? 0).compareTo(
            a.cooccurrenceCount ?? 0,
          );
          if (occurrences != 0) return occurrences;
        }
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        final count = b.postCount.compareTo(a.postCount);
        if (count != 0) return count;
        return a.canonicalTag.compareTo(b.canonicalTag);
      });
    return results.take(limit ?? query.limit).toList(growable: false);
  }

  static CompletionCandidate _score(
    CompletionCandidate candidate,
    CompletionQuery query,
    Map<String, double> boosts,
  ) {
    final priority = _matchPriority(candidate.matchKind);
    // Preserve exact/prefix/contains lexical matches. For fuzzy fallback rows,
    // cosine order must not be overwritten by tag popularity or source boosts.
    // Semantic rows sit in the full-text band, below every lexical kind.
    if (candidate.matchKind == CompletionMatchKind.fullText &&
        candidate.semanticScore != null) {
      return candidate.copyWith(
        score:
            1000000.0 -
            priority * 100000.0 +
            10000 +
            candidate.semanticScore!.clamp(-1, 1) * 80000,
      );
    }
    final sourceBoost = candidate.sources.contains(CompletionSourceKind.base)
        ? 2000.0
        : candidate.sources.contains(CompletionSourceKind.zhDictionary)
        ? 1000.0
        : 0.0;
    final popularity = candidate.postCount <= 0
        ? 0.0
        : candidate.postCount.toString().length * 10.0;
    final existingPenalty = candidate.isExisting ? 100000.0 : 0.0;
    // Quality spans 40000 so exact rows of a kind stay above prefix rows; the
    // context and habit boost (at most 6000) then reorders within those.
    final quality = candidate.matchQuality.clamp(0.0, 1.0) * 40000.0;
    final boost = (boosts[candidate.stableId] ?? 0).clamp(0.0, 6000.0);
    return candidate.copyWith(
      score:
          1000000.0 -
          priority * 100000.0 +
          quality +
          sourceBoost +
          popularity +
          boost -
          existingPenalty,
    );
  }

  static T? _greaterNullable<T extends num>(T? left, T? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left >= right ? left : right;
  }

  static int _matchPriority(CompletionMatchKind kind) => switch (kind) {
    CompletionMatchKind.englishExact => 0,
    CompletionMatchKind.englishPrefix => 1,
    CompletionMatchKind.aliasExact => 2,
    CompletionMatchKind.aliasPrefix => 3,
    CompletionMatchKind.chineseExact => 4,
    CompletionMatchKind.chinesePrefix => 5,
    CompletionMatchKind.chineseContains => 6,
    CompletionMatchKind.homophone => 7,
    CompletionMatchKind.spellCorrected => 8,
    CompletionMatchKind.englishVariant => 9,
    CompletionMatchKind.pinyin => 10,
    CompletionMatchKind.shuangpin => 11,
    CompletionMatchKind.crossLingual => 12,
    CompletionMatchKind.approximate => 13,
    CompletionMatchKind.fuzzyPinyin => 14,
    CompletionMatchKind.pinyinInitials => 15,
    CompletionMatchKind.related => 16,
    CompletionMatchKind.fullText => 17,
  };
}
