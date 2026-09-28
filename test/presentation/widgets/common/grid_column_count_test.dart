import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/grid_column_count.dart';

void main() {
  int resolve(double width, int preferred, {double minCellWidth = 92}) =>
      GridColumnCount.resolve(
        width: width,
        preferred: preferred,
        spacing: 8,
        minCellWidth: minCellWidth,
      );

  test('手机宽度严格使用所选列数', () {
    for (final width in [296.0, 387.0, 420.0]) {
      expect(
        [
          for (final n in [1, 2, 3]) resolve(width, n),
        ],
        [1, 2, 3],
      );
    }
  });

  test('宽面板保持同一密度，增加列数而不拉宽格子', () {
    expect(resolve(956, 1), 2);
    expect(resolve(956, 2), 4);
    expect(resolve(956, 3), 6);
    for (final n in [1, 2, 3]) {
      final columns = resolve(1600, n);
      final cell = GridColumnCount.cellWidth(
        width: 1600,
        columns: columns,
        spacing: 8,
      );
      expect(cell, lessThanOrEqualTo([480, 240, 160][n - 1]));
    }
  });

  test('大字号下格子过窄时减少列数，至少保留一列', () {
    expect(resolve(296, 3, minCellWidth: 92 * 3), 1);
    expect(resolve(387, 3, minCellWidth: 92 * 1.5), 2);
    expect(resolve(0, 2), 1);
    expect(resolve(double.infinity, 2), 1);
  });

  test('列数在 1 到 3 之间循环', () {
    expect(GridColumnCount.next(1), 2);
    expect(GridColumnCount.next(2), 3);
    expect(GridColumnCount.next(3), 1);
    expect(GridColumnCount.clamp(9), 3);
    expect(GridColumnCount.clamp(0), 1);
  });
}
