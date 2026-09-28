import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/common/grid_column_count.dart';
import 'entry_card.dart';

/// Shared grid geometry for the flat and grouped tag library views.
@immutable
class TagLibraryGridLayout {
  const TagLibraryGridLayout({
    required this.columns,
    required this.mainAxisExtent,
    required this.padding,
  });

  static const double spacing = 12;

  final int columns;
  final double mainAxisExtent;
  final double padding;

  SliverGridDelegate get delegate => SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisExtent: mainAxisExtent,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
  );
}

/// Resolves the user's column choice for the available width. Cells keep the
/// avatar-beside-name row while wide enough and otherwise become vertical
/// tiles, which need more height for the avatar and two lines of name.
TagLibraryGridLayout computeTagLibraryGridLayout(
  double availableWidth,
  double textScale, {
  int preferredColumns = GridColumnCount.fallback,
}) {
  final padding = availableWidth < 600 ? 12.0 : 16.0;
  final scale = textScale.clamp(1.0, 3.0);
  final width = math.max(0.0, availableWidth - padding * 2);
  final columns = GridColumnCount.resolve(
    width: width,
    preferred: preferredColumns,
    spacing: TagLibraryGridLayout.spacing,
    minCellWidth: 104 * scale,
  );
  final cellWidth = GridColumnCount.cellWidth(
    width: width,
    columns: columns,
    spacing: TagLibraryGridLayout.spacing,
  );
  // Vertical tile: 12 + 52 avatar + 8 + two name lines + 10, plus 4 of slack.
  final nameLines = 2 * 14 * entryCardNameLineHeight * scale;
  return TagLibraryGridLayout(
    columns: columns,
    mainAxisExtent: cellWidth < entryCardVerticalBreakpoint
        ? 86 + nameLines
        : 68 + (scale - 1) * 40,
    padding: padding,
  );
}
