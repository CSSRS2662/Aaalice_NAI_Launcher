import 'dart:math' as math;

import '../autocomplete_settings.dart';
import '../completion_models.dart';
import 'tag_usage_history.dart';

/// Boosts from the prompt around the cursor (tags that often appear with the
/// nearby ones, from the optional co-occurrence pack) and from this device's
/// accepted completions. Each part adds at most 3000 to a score; match kinds
/// stay 100000 apart, so boosts only reorder rows of the same kind.
class DefaultCompletionRankingSignals implements CompletionRankingSignals {
  DefaultCompletionRankingSignals({
    required TagUsageHistory history,
    required AutocompleteSettings Function() settings,
    CompletionSource? cooccurrence,
  }) : _history = history,
       _settings = settings,
       _cooccurrence = cooccurrence;

  final TagUsageHistory _history;
  final AutocompleteSettings Function() _settings;
  final CompletionSource? _cooccurrence;

  static const double maxBoost = 3000;
  static const int contextTags = 6;
  static const int relatedPerTag = 300;

  String? _contextKey;
  Map<String, double> _contextBoosts = const {};

  @override
  Future<Map<String, double>> boosts(CompletionQuery query) async {
    if (query.relatedTag != null || query.kind != CompletionQueryKind.tag) {
      return const {};
    }
    final settings = _settings();
    final result = <String, double>{};
    if (settings.contextRankingEnabled && _cooccurrence != null) {
      for (final entry in (await _context(query)).entries) {
        result[entry.key] = entry.value;
      }
    }
    if (settings.personalRankingEnabled && !_history.isEmpty) {
      // Candidates are not known yet; the few hundred remembered tags are
      // cheap to score. A tag used five times recently is near the cap.
      for (final tag in _history.tags) {
        final score = _history.score(tag);
        if (score <= 0) continue;
        result[tag] = (result[tag] ?? 0) + math.min(maxBoost, score * 1200);
      }
    }
    return result;
  }

  Future<Map<String, double>> _context(CompletionQuery query) async {
    final nearby = nearbyTags(query);
    if (nearby.isEmpty) return const {};
    final key = nearby.join(',');
    if (key == _contextKey) return _contextBoosts;
    final boosts = <String, double>{};
    for (final tag in nearby) {
      final List<CompletionCandidate> related;
      try {
        related = await _cooccurrence!.search(
          query.copyWith(token: '', relatedTag: tag, limit: relatedPerTag),
        );
      } catch (_) {
        continue;
      }
      final best = related.fold<double>(
        0,
        (max, row) => math.max(max, row.relatedScore ?? 0),
      );
      if (best <= 0) continue;
      for (final row in related) {
        final value = (row.relatedScore ?? 0) / best * maxBoost;
        final id = row.stableId;
        if (value > (boosts[id] ?? 0)) boosts[id] = value;
      }
    }
    _contextKey = key;
    _contextBoosts = boosts;
    return boosts;
  }

  /// Up to [contextTags] prompt tags closest before the cursor (the first
  /// ones when the cursor is at the start).
  static List<String> nearbyTags(CompletionQuery query) {
    if (query.existingTags.isEmpty) return const [];
    final cursor = query.cursorPosition.clamp(0, query.fullText.length);
    final before = query.fullText
        .substring(0, cursor)
        .toLowerCase()
        .replaceAll(' ', '_');
    final positioned = <(int, String)>[];
    for (final tag in query.existingTags) {
      final index = before.lastIndexOf(tag);
      if (index >= 0) positioned.add((index, tag));
    }
    if (positioned.isEmpty) {
      return query.existingTags.take(contextTags).toList(growable: false);
    }
    positioned.sort((a, b) => b.$1.compareTo(a.$1));
    return positioned.take(contextTags).map((item) => item.$2).toList();
  }
}
