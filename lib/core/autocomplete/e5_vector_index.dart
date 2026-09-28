import 'dart:typed_data';

/// Multi-view E5 vectors: each tag owns consecutive rows and scores by its best
/// row, matching the offline evaluation. Rows ship as int8 with one float32
/// scale per row and are expanded once so queries can use SIMD dot products.
class E5VectorIndex {
  E5VectorIndex._(this.dimension, this._rows, this._starts);

  factory E5VectorIndex.fromQuantized({
    required int dimension,
    required Int8List values,
    required Float32List scales,
    required List<int> viewCounts,
  }) {
    if (dimension <= 0 || dimension % 4 != 0) {
      throw ArgumentError.value(
        dimension,
        'dimension',
        'must be a multiple of 4',
      );
    }
    if (values.length != scales.length * dimension) {
      throw const FormatException('E5 vector rows and scales do not match');
    }
    final starts = Int32List(viewCounts.length + 1);
    var total = 0;
    for (var tag = 0; tag < viewCounts.length; tag++) {
      final count = viewCounts[tag];
      if (count < 1) {
        throw const FormatException('Every E5 tag needs at least one view');
      }
      starts[tag] = total;
      total += count;
    }
    starts[viewCounts.length] = total;
    if (total != scales.length) {
      throw const FormatException(
        'E5 view counts do not match the vector rows',
      );
    }
    final rows = Float32List(values.length);
    for (var row = 0; row < scales.length; row++) {
      final scale = scales[row];
      final offset = row * dimension;
      for (var d = 0; d < dimension; d++) {
        rows[offset + d] = values[offset + d] * scale;
      }
    }
    return E5VectorIndex._(dimension, rows.buffer.asFloat32x4List(), starts);
  }

  final int dimension;
  final Float32x4List _rows;
  final Int32List _starts;

  int get tagCount => _starts.length - 1;

  int get viewCount => _starts[tagCount];

  /// Tag positions with their best cosine score, highest first. Ties keep the
  /// earlier tag, as the single-view pack did.
  List<(int, double)> search(Float32List query, int limit) {
    if (query.length != dimension) {
      throw ArgumentError.value(query.length, 'query', 'dimension mismatch');
    }
    final lanes = dimension ~/ 4;
    final probe = Float32List.fromList(query).buffer.asFloat32x4List();
    final best = <(int, double)>[];
    for (var tag = 0; tag < tagCount; tag++) {
      var score = double.negativeInfinity;
      for (var view = _starts[tag]; view < _starts[tag + 1]; view++) {
        var sum = Float32x4.zero();
        final offset = view * lanes;
        for (var lane = 0; lane < lanes; lane++) {
          sum += _rows[offset + lane] * probe[lane];
        }
        final value = sum.x + sum.y + sum.z + sum.w;
        if (value > score) score = value;
      }
      if (best.length == limit && score <= best.last.$2) continue;
      final position = best.indexWhere((item) => score > item.$2);
      best.insert(position < 0 ? best.length : position, (tag, score));
      if (best.length > limit) best.removeLast();
    }
    return best;
  }
}
