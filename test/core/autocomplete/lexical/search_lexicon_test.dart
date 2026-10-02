import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/lexical/english_words.dart';
import 'package:nai_launcher/core/autocomplete/lexical/pinyin_syllables.dart';
import 'package:nai_launcher/core/autocomplete/lexical/search_lexicon.dart';

void main() {
  late SearchLexicon lexicon;
  late PinyinSyllables syllables;

  setUpAll(() {
    lexicon = SearchLexicon.decode(
      pinyinGz: File(
        'assets/search_lexicon/hanzi_pinyin.json.gz',
      ).readAsBytesSync(),
      crossLingualGz: File(
        'assets/search_lexicon/zh_en_lexicon.json.gz',
      ).readAsBytesSync(),
    );
    syllables = lexicon.pinyin.syllables;
  });

  test('随包数据与清单一致，并附带 MIT 许可', () {
    final manifest =
        jsonDecode(
              File('assets/search_lexicon/manifest.json').readAsStringSync(),
            )
            as Map;
    for (final entry in (manifest['files'] as Map).entries) {
      final bytes = File(
        'assets/search_lexicon/${entry.key}',
      ).readAsBytesSync();
      expect(bytes.length, (entry.value as Map)['bytes'], reason: entry.key);
      expect(
        sha256.convert(bytes).toString(),
        (entry.value as Map)['sha256'],
        reason: entry.key,
      );
    }
    for (final source in (manifest['sources'] as Map).values) {
      expect((source as Map)['license'], 'MIT');
    }
    expect(File('assets/search_lexicon/LICENSE.ecdict.txt').existsSync(), true);
    expect(
      File('assets/search_lexicon/LICENSE.pinyin-data.txt').existsSync(),
      true,
    );
  });

  group('拼音读音', () {
    test('同音字得到相同读音，多音字保留候选', () {
      expect(lexicon.pinyin.readingVariants('陈山').first, ['chen', 'shan']);
      expect(lexicon.pinyin.readingVariants('衬衫').first, ['chen', 'shan']);
      final variants = lexicon.pinyin.readingVariants('长发');
      expect(
        variants,
        containsAll([
          ['chang', 'fa'],
          ['zhang', 'fa'],
        ]),
      );
      expect(variants.length, lessThanOrEqualTo(4));
    });

    test('全拼切分允许末尾不完整音节', () {
      expect(syllables.splitFullPinyin('chenshan').first.pieces, [
        'chen',
        'shan',
      ]);
      final partial = syllables.splitFullPinyin('chens').first;
      expect(partial.pieces, ['chen', 's']);
      expect(partial.partialLast, isTrue);
      // Whole syllables first, then the partial reading of the tail.
      expect(syllables.splitFullPinyin('xian').map((s) => s.pieces).take(2), [
        ['xian'],
        ['xi', 'an'],
      ]);
    });
  });

  group('自然码双拼', () {
    test('编码表覆盖声母、韵母与零声母', () {
      final cases = {
        'chen': 'if',
        'shan': 'uj',
        'zhuang': 'vd',
        'xiong': 'xs',
        'lve': 'lt',
        'a': 'aa',
        'e': 'ee',
        'an': 'an',
        'ang': 'ah',
        'eng': 'eg',
        'er': 'er',
        'ou': 'ou',
      };
      for (final entry in cases.entries) {
        expect(
          PinyinSyllables.ziranmaCodeOf(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('按键解码为音节，奇数末键作声母前缀', () {
      expect(syllables.splitZiranma('ifuj')!.pieces, ['chen', 'shan']);
      final partial = syllables.splitZiranma('ifu')!;
      expect(partial.pieces, ['chen', 'sh']);
      expect(partial.partialLast, isTrue);
      expect(syllables.splitZiranma('ah')!.pieces, ['ang']);
    });
  });

  test('模糊音只合并选中的音', () {
    const rules = FuzzyPinyinRule.defaults;
    expect(foldPinyin('cheng', rules), foldPinyin('chen', rules));
    expect(foldPinyin('xing', rules), foldPinyin('xin', rules));
    expect(foldPinyin('zhan', rules), isNot(foldPinyin('zan', rules)));
    expect(
      foldPinyin('zhan', {FuzzyPinyinRule.zZh}),
      foldPinyin('zan', {FuzzyPinyinRule.zZh}),
    );
    expect(foldPinyinFully('lang'), foldPinyinFully('nan'));
  });

  test('中文拆词并映射到英文 tag 词', () {
    final words = lexicon.crossLingual;
    expect(words.segment('坐在椅子上'), ['坐在', '椅子', '上']);
    expect(words.isDropped('上'), isTrue);
    expect(words.candidatesOf('坐在'), contains('sitting'));
    expect(words.candidatesOf('椅子'), contains('chair'));
    expect(words.segment('拨起头发'), contains('头发'));
    expect(words.candidatesOf('头发'), contains('hair'));
  });

  test('英文词形与拼写距离', () {
    expect(EnglishWords.stem('socks'), 'sock');
    expect(EnglishWords.stem('sitting'), EnglishWords.stem('sit'));
    expect(EnglishWords.distance('shrit', 'shirt'), 1);
    expect(EnglishWords.distance('sokcs', 'socks'), 1);
    expect(EnglishWords.allowedDistance(5), 1);
    expect(EnglishWords.allowedDistance(9), 2);
  });
}
