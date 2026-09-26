import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/chinese_query_variants.dart';

void main() {
  test('explicit Chinese keyword conjunction is bounded and lossless', () {
    expect(chineseQueryKeywords('蓝色 眼睛'), ['蓝色', '眼睛']);
    expect(chineseQueryKeywords('眼睛_蓝色'), ['眼睛', '蓝色']);
    expect(chineseQueryKeywords('蓝色　眼睛 蓝色'), ['蓝色', '眼睛']);
    for (final query in [
      '蓝色眼睛',
      '不 穿 袜子',
      '蓝色 %_',
      'blue eyes',
      '蓝色 眼睛 长发 裙子 袜子',
      '蓝色 蓝色',
    ]) {
      expect(chineseQueryKeywords(query), isEmpty, reason: query);
    }
  });
  test('colloquial garment negation reaches existing labels', () {
    for (final query in ['不穿袜子', '没穿袜子', '没有穿袜子']) {
      final variants = chineseQueryVariants(query);
      expect(variants, containsAll(['未穿袜', '没有袜子']));
      expect(variants, isNot(contains(query)));
      expect(variants, isNot(contains('袜')));
      expect(variants.length, lessThanOrEqualTo(12));
    }
  });
  test('preserves modifiers and avoids arbitrary suffix stripping', () {
    expect(chineseQueryVariants('不穿长袜子'), contains('未穿长袜'));
    expect(chineseQueryVariants('不穿裙子'), isNot(contains('未穿裙')));
  });
  test('does not expand unrelated or reversed intent', () {
    for (final query in ['穿袜子', '不是不穿袜子', '袜子', 'no_socks', '%_', '']) {
      expect(chineseQueryVariants(query), isEmpty);
    }
  });
}
