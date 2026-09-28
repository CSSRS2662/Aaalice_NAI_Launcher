import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/ame_zh_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';

const _rows = <List<Object?>>[
  [
    'braid',
    0,
    600000,
    '辫子',
    <String>['麻花辫'],
  ],
  ['twin_braids', 0, 200000, '双麻花辫', <String>[]],
  ['no_socks', 0, 20000, '未穿袜', <String>[]],
  [
    'hakurei_reimu',
    4,
    80000,
    '博丽灵梦',
    <String>['灵梦', '红白'],
  ],
  ['red_and_white', 7, 900, '红白配色', <String>[]],
  [
    'alias_only',
    0,
    10,
    '',
    <String>['别名词'],
  ],
];

CompletionQuery _query(String token, {int limit = 20, TagCategory? category}) =>
    CompletionQuery(
      fullText: token,
      cursorPosition: token.length,
      token: token,
      replacementRange: TextReplacementRange(start: 0, end: token.length),
      existingTags: const {},
      limit: limit,
      locale: 'zh-CN',
      categoryFilter: category,
    );

void main() {
  final index = AmeZhLexiconIndex.fromRows(_rows);

  test('译名精确、前缀、包含依次排序，别名命中会记录匹配的别名', () {
    final results = index.search(_query('麻花辫'));

    expect(results.map((c) => c.canonicalTag), ['braid', 'twin_braids']);
    expect(results.first.matchKind, CompletionMatchKind.chineseExact);
    expect(results.first.matchedAlias, '麻花辫');
    expect(results.first.translation, isNull);
    expect(results.first.sources, {CompletionSourceKind.zhDictionary});
    expect(results.last.matchKind, CompletionMatchKind.chineseContains);
    expect(results.last.matchedAlias, isNull);
  });

  test('昵称与作品/角色分类都能反查，分类筛选生效', () {
    final all = index.search(_query('红白'));
    expect(all.map((c) => c.canonicalTag), ['hakurei_reimu', 'red_and_white']);
    expect(all.first.category, TagCategory.character);
    expect(all.last.category, TagCategory.general);

    final general = index.search(_query('红白', category: TagCategory.general));
    expect(general.single.canonicalTag, 'red_and_white');
  });

  test('否定句式沿用现有的查询变体，空格分隔的关键词需全部命中', () {
    expect(index.search(_query('不穿袜子')).single.canonicalTag, 'no_socks');
    final keywords = index.search(_query('博丽 灵梦'));
    expect(keywords.single.canonicalTag, 'hakurei_reimu');
    expect(keywords.single.matchKind, CompletionMatchKind.fullText);
  });

  test('单字查询在请求全部结果时仍受限，缺字直接无结果', () {
    final rows = [
      for (var i = 0; i < 150; i++) ['tag_$i', 0, i, '字$i', <String>[]],
    ];
    final large = AmeZhLexiconIndex.fromRows(rows);
    expect(
      large.search(_query('字', limit: CompletionResultLimits.all)),
      hasLength(CompletionResultLimits.oneCharacter),
    );
    expect(index.search(_query('无此词')), isEmpty);
  });

  test('解析按规范名返回译名，仅有别名的词条不提供译名', () {
    expect(index.resolve(['braid', 'Hakurei Reimu', 'alias_only', 'missing']), {
      'braid': '辫子',
      'Hakurei Reimu': '博丽灵梦',
    });
  });

  test('包装层只处理中文查询与中文界面，加载失败会短暂退避', () async {
    final gz = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode({'version': 1, 'entries': _rows}))),
    );
    var loads = 0;
    final lexicon = AmeZhLexicon(
      loadBytes: () async {
        loads++;
        return gz;
      },
      decode: (bytes) async => AmeZhLexiconIndex.decode(bytes),
    );
    expect(await lexicon.search(_query('braid')), isEmpty);
    expect(await lexicon.resolve(['braid'], locale: 'en-US'), isEmpty);
    expect(await lexicon.resolve(['braid'], locale: 'zh-CN'), {'braid': '辫子'});
    expect(
      (await lexicon.search(_query('灵梦'))).single.canonicalTag,
      'hakurei_reimu',
    );
    expect(loads, 1);

    var attempts = 0;
    final broken = AmeZhLexicon(
      loadBytes: () async {
        attempts++;
        throw const FileSystemException('missing asset');
      },
    );
    await expectLater(broken.search(_query('辫子')), throwsA(anything));
    await expectLater(broken.search(_query('辫子')), throwsStateError);
    expect(attempts, 1);
  });

  test('随包词库与清单一致，关键词条可用', () {
    final manifest =
        jsonDecode(File('assets/zh_lexicon/manifest.json').readAsStringSync())
            as Map;
    final file = manifest['file'] as Map;
    final bytes = File('assets/zh_lexicon/${file['name']}').readAsBytesSync();
    expect(bytes.length, file['bytes']);
    expect(sha256.convert(bytes).toString(), file['sha256']);
    expect(manifest['source']['license'], 'MIT');

    final bundled = AmeZhLexiconIndex.decode(bytes);
    expect(bundled.length, manifest['entries']);
    expect(bundled.search(_query('麻花辫')).first.canonicalTag, 'braid');
    expect(bundled.resolve(['hatsune_miku']), {'hatsune_miku': '初音未来'});
    expect(
      File('assets/zh_lexicon/LICENSE.amenorira.txt').existsSync(),
      isTrue,
    );
  });
}
