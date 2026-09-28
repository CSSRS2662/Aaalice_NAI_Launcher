import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';

/// User-chosen column counts for compact title grids.
///
/// Phones show exactly the chosen count. Wider panes keep the same density by
/// capping each cell at the width that choice has on a phone, so they add
/// columns instead of stretching cells; large text removes columns before
/// titles become unreadable.
abstract final class GridColumnCount {
  static const int min = 1;
  static const int max = 3;
  static const int fallback = 2;

  /// Widest cell for each choice. A phone pane is narrower than the choice
  /// times its cap, so it keeps exactly the chosen count.
  static const List<double> _maxCellWidths = [480, 240, 160];

  static int clamp(int columns) => columns.clamp(min, max);

  static int next(int columns) => columns >= max ? min : clamp(columns + 1);

  static IconData icon(int columns) => switch (clamp(columns)) {
    1 => Icons.view_agenda_outlined,
    2 => Icons.grid_view_outlined,
    _ => Icons.apps_rounded,
  };

  static int resolve({
    required double width,
    required int preferred,
    required double spacing,
    required double minCellWidth,
  }) {
    if (!width.isFinite || width <= 0) return 1;
    final target = clamp(preferred);
    final maxCellWidth = _maxCellWidths[target - 1];
    final fitting = ((width + spacing) / (minCellWidth + spacing)).floor();
    final needed = ((width + spacing) / (maxCellWidth + spacing)).ceil();
    return math.max(1, math.min(math.max(target, needed), fitting));
  }

  static double cellWidth({
    required double width,
    required int columns,
    required double spacing,
  }) => (width - spacing * (columns - 1)) / columns;
}

/// Icon-only switch that cycles 1 → 2 → 3 columns; the icon shows the result.
class GridColumnCountButton extends StatelessWidget {
  const GridColumnCountButton({
    super.key,
    required this.columns,
    required this.onPressed,
  });

  final int columns;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final extent = context.interactionPolicy.minimumControlExtent;
    return IconButton(
      tooltip: context.l10n.common_columnCountTooltip(columns),
      constraints: BoxConstraints.tightFor(width: extent, height: extent),
      onPressed: onPressed,
      icon: Icon(GridColumnCount.icon(columns), size: 20),
    );
  }
}
