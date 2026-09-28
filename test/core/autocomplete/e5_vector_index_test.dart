import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/e5_vector_index.dart';

void main() {
  // Rows (dimension 4): tag 0 -> [x]; tag 1 -> [y, x]; tag 2 -> [-x].
  E5VectorIndex build() => E5VectorIndex.fromQuantized(
    dimension: 4,
    values: Int8List.fromList([
      ...[127, 0, 0, 0],
      ...[0, 127, 0, 0],
      ...[127, 0, 0, 0],
      ...[-127, 0, 0, 0],
    ]),
    scales: Float32List.fromList([1 / 127, 1 / 127, 1 / 127, 1 / 127]),
    viewCounts: const [1, 2, 1],
  );

  test('标签取其所有视图中的最高分，同分时保留靠前的标签', () {
    final index = build();

    expect(index.tagCount, 3);
    expect(index.viewCount, 4);
    final hits = index.search(Float32List.fromList([1, 0, 0, 0]), 3);
    expect([for (final hit in hits) hit.$1], [0, 1, 2]);
    expect(hits[0].$2, closeTo(1, 1e-6));
    expect(hits[1].$2, closeTo(1, 1e-6));
    expect(hits[2].$2, closeTo(-1, 1e-6));
  });

  test('只命中第二个视图时同样按最高分排序并截断到上限', () {
    final hits = build().search(Float32List.fromList([0, 1, 0, 0]), 1);

    expect(hits.single.$1, 1);
    expect(hits.single.$2, closeTo(1, 1e-6));
  });

  test('向量行、缩放系数与视图数不一致时拒绝加载', () {
    expect(
      () => E5VectorIndex.fromQuantized(
        dimension: 4,
        values: Int8List(8),
        scales: Float32List(2),
        viewCounts: const [1, 2],
      ),
      throwsFormatException,
    );
    expect(
      () => E5VectorIndex.fromQuantized(
        dimension: 4,
        values: Int8List(4),
        scales: Float32List(2),
        viewCounts: const [2],
      ),
      throwsFormatException,
    );
    expect(
      () => E5VectorIndex.fromQuantized(
        dimension: 4,
        values: Int8List(8),
        scales: Float32List(2),
        viewCounts: const [2, 0],
      ),
      throwsFormatException,
    );
    expect(
      () => E5VectorIndex.fromQuantized(
        dimension: 6,
        values: Int8List(6),
        scales: Float32List(1),
        viewCounts: const [1],
      ),
      throwsArgumentError,
    );
  });

  test('查询维度不符时报错', () {
    expect(() => build().search(Float32List(3), 5), throwsArgumentError);
  });
}
