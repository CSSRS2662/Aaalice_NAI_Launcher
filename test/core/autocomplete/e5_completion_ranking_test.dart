import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/completion_ranker.dart';

void main() {
  const query = CompletionQuery(
    fullText: '不穿袜子',
    cursorPosition: 4,
    token: '不穿袜子',
    replacementRange: TextReplacementRange(start: 0, end: 4),
    existingTags: {'already_used'},
    limit: 20,
    locale: 'zh-CN',
  );
  CompletionCandidate candidate(String tag, double similarity, int count) =>
      CompletionCandidate(
        canonicalTag: tag,
        category: TagCategory.general,
        postCount: count,
        matchKind: CompletionMatchKind.fullText,
        sources: const {CompletionSourceKind.base},
        semanticScore: similarity,
      );

  test('cosine ordering survives merge without popularity overriding it', () {
    final rows = CompletionRanker.mergeAndSort([
      candidate('no_socks', .91, 20),
      candidate('socks', .85, 9000000),
      candidate('already_used', .99, 1),
      const CompletionCandidate(
        canonicalTag: 'no_socks',
        category: TagCategory.general,
        postCount: 20,
        matchKind: CompletionMatchKind.fullText,
        sources: {CompletionSourceKind.zhDictionary},
        translation: '未穿袜',
      ),
    ], query: query);
    expect(rows.map((row) => row.canonicalTag), [
      'no_socks',
      'socks',
      'already_used',
    ]);
    expect(rows.first.semanticScore, .91);
    expect(rows.first.translation, '未穿袜');
    final mergedAgain = CompletionRanker.mergeAndSort(rows, query: query);
    expect(
      mergedAgain.map((row) => row.canonicalTag),
      rows.map((row) => row.canonicalTag),
    );
  });

  test('exact Chinese dictionary match stays ahead of semantic guesses', () {
    final rows = CompletionRanker.mergeAndSort([
      candidate('guess', .99, 9000000),
      const CompletionCandidate(
        canonicalTag: 'exact',
        category: TagCategory.general,
        postCount: 1,
        matchKind: CompletionMatchKind.chineseExact,
        sources: {CompletionSourceKind.zhDictionary},
      ),
    ], query: query);
    expect(rows.first.canonicalTag, 'exact');
  });
}
