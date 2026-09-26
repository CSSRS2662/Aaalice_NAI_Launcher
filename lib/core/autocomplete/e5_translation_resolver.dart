import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'completion_models.dart';

/// Existing corpus labels only; does not load or run the embedding model.
class E5TranslationResolver implements TranslationResolver {
  E5TranslationResolver({Future<String> Function()? loadLabels})
    : _loadLabels = loadLabels ?? _loadAsset;

  final Future<String> Function() _loadLabels;
  Future<Map<String, String>>? _labels;

  static Future<String> _loadAsset() =>
      rootBundle.loadString('assets/semantic_search/tags.json');

  Future<Map<String, String>> _load() async =>
      compute(_parseLabels, await _loadLabels());

  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async {
    if (!locale.toLowerCase().startsWith('zh') || canonicalTags.isEmpty) {
      return const {};
    }
    final loading = _labels ??= _load();
    try {
      final labels = await loading;
      return {
        for (final tag in canonicalTags)
          if (labels.containsKey(tag)) tag: labels[tag]!,
      };
    } catch (_) {
      if (identical(_labels, loading)) _labels = null;
      rethrow;
    }
  }
}

Map<String, String> _parseLabels(String source) {
  final rows = jsonDecode(source) as List;
  return {
    for (final row in rows.cast<List>())
      if ((row[2] as String).trim().isNotEmpty)
        row[0] as String: (row[2] as String).trim(),
  };
}
