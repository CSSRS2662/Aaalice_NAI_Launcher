/// Bounded search-only variants. Never changes stored translations or tags.
/// Preserve negation: expanding to the garment alone would reverse intent.
List<String> chineseQueryVariants(String query) {
  final match = RegExp(
    r'^(?:不穿|没穿|没有穿|未穿)([\u3400-\u9fff]{2,12})$',
  ).firstMatch(query);
  if (match == null) return const [];
  final noun = match.group(1)!;
  final nouns = <String>{noun};
  // Only known garment suffixes: do not strip 子 from arbitrary Chinese nouns.
  const shortForms = {'袜子': '袜', '鞋子': '鞋', '裤子': '裤', '帽子': '帽'};
  for (final entry in shortForms.entries) {
    if (noun.endsWith(entry.key)) {
      nouns.add(
        noun.substring(0, noun.length - entry.key.length) + entry.value,
      );
    }
  }
  return [
    for (final noun in nouns)
      for (final prefix in const ['未穿', '不穿', '没穿', '没有穿', '没有', '无'])
        if ('$prefix$noun' != query) '$prefix$noun',
  ];
}

/// Explicit keyword conjunction, not automatic segmentation or translation.
/// The prompt parser normalizes spaces to underscores, so accept both.
/// Reject short/oversized groups rather than silently dropping constraints.
List<String> chineseQueryKeywords(String query) {
  final parts = query.trim().split(RegExp(r'[\s_\u3000]+'));
  if (parts.length < 2 || parts.length > 4) return const [];
  final word = RegExp(r'^[\u3400-\u9fff]{2,12}$');
  if (parts.any((part) => !word.hasMatch(part))) return const [];
  final unique = parts.toSet().toList(growable: false);
  return unique.length < 2 ? const [] : unique;
}
