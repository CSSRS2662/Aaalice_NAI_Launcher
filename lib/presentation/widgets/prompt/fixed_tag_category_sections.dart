import 'package:flutter/material.dart';

import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/tag_library/tag_library_category.dart';

/// Where a group of fixed tags belongs.
enum FixedTagSectionKind { category, unknownCategory, uncategorized }

/// Fixed tags that share a tag-library category, in their original order.
@immutable
class FixedTagCategorySection {
  const FixedTagCategorySection({
    required this.kind,
    required this.entries,
    this.categoryId,
    this.category,
  });

  final FixedTagSectionKind kind;
  final String? categoryId;

  /// Null for a category the library no longer has, and for no category.
  final TagLibraryCategory? category;
  final List<FixedTagEntry> entries;
}

/// Groups fixed tags by library category: known categories in library order,
/// then categories the library no longer has, then uncategorized tags. Empty
/// groups are left out. Shared by the sidebar and the management dialog so
/// both show the same grouping.
List<FixedTagCategorySection> groupFixedTagsByCategory(
  List<FixedTagEntry> entries,
  List<TagLibraryCategory> categories,
) {
  final grouped = <String?, List<FixedTagEntry>>{};
  for (final entry in entries) {
    grouped.putIfAbsent(entry.categoryId, () => []).add(entry);
  }
  final known = {for (final category in categories) category.id};
  return [
    for (final category in categories.sortedByOrder())
      if (grouped[category.id]?.isNotEmpty ?? false)
        FixedTagCategorySection(
          kind: FixedTagSectionKind.category,
          categoryId: category.id,
          category: category,
          entries: grouped[category.id]!,
        ),
    for (final id in grouped.keys)
      if (id != null && !known.contains(id))
        FixedTagCategorySection(
          kind: FixedTagSectionKind.unknownCategory,
          categoryId: id,
          entries: grouped[id]!,
        ),
    if (grouped[null]?.isNotEmpty ?? false)
      FixedTagCategorySection(
        kind: FixedTagSectionKind.uncategorized,
        entries: grouped[null]!,
      ),
  ];
}

/// Stable accent for a category id; uncategorized tags use the outline color.
Color fixedTagCategoryColor(String? categoryId, ColorScheme colors) {
  if (categoryId == null) return colors.outline;
  final hash = categoryId.codeUnits.fold<int>(
    0,
    (previous, codeUnit) => (previous * 31 + codeUnit) & 0x7fffffff,
  );
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.58, 0.55).toColor();
}
