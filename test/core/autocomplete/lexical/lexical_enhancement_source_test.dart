import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/completion_ranker.dart';
import 'package:nai_launcher/core/autocomplete/lexical/completion_ranking_signals.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_enhancement_source.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_index_builder.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_search_index.dart';
import 'package:nai_launcher/core/autocomplete/lexical/search_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/lexical/tag_usage_history.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _tags = <(String, int)>[
  ('shirt', 900000),
  ('white_shirt', 400000),
  ('shirt_tucked_in', 20000),
  ('city', 50000),
  ('hair_flip', 30000),
  ('chair', 200000),
  ('sitting', 1000000),
  ('sitting_on_chair', 50000),
  ('sitting_on_office_chair', 3000),
];

// AME rows: tag, category, posts, label, aliases.
const _ame = <List<Object>>[
  ['shirt', 0, 900000, '衬衫', <String>[]],
  ['white_shirt', 0, 400000, '白衬衫', <String>[]],
  ['shirt_tucked_in', 0, 20000, '衬衫塞进裤腰', <String>[]],
  ['city', 0, 50000, '城市', <String>[]],
  [
    'hair_flip',
    0,
    30000,
    '拨头发',
    <String>['撩头发'],
  ],
  ['chair', 0, 200000, '椅子', <String>[]],
];

CompletionQuery _query(String token, {TagCategory? category}) =>
    CompletionQuery(
      fullText: token,
      cursorPosition: token.length,
      token: token,
      replacementRange: TextReplacementRange(start: 0, end: token.length),
      existingTags: const {},
      limit: 20,
      locale: 'zh',
      categoryFilter: category,
    );

class _FakeCatalog extends Fake implements TagCatalogRepository {
  final groups = <List<List<String>>>[];

  @override
  Future<List<TagCatalogRecord>> searchTokenGroups(
    List<List<String>> groups, {
    int limit = 300,
  }) async {
    this.groups.add(groups);
    final words = groups.expand((group) => group).toSet();
    return [
      if (words.containsAll({'sitting', 'chair'})) ...const [
        TagCatalogRecord(
          canonicalTag: 'sitting_on_office_chair',
          category: TagCategory.general,
          postCount: 3000,
        ),
        TagCatalogRecord(
          canonicalTag: 'sitting_on_chair',
          category: TagCategory.general,
          postCount: 50000,
        ),
      ],
      if (words.containsAll({'flip', 'hair'}))
        const TagCatalogRecord(
          canonicalTag: 'hair_flip',
          category: TagCategory.general,
          postCount: 30000,
        ),
    ];
  }

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async => [
    if (query.token == 'shirt')
      const CompletionCandidate(
        canonicalTag: 'shirt',
        category: TagCategory.general,
        postCount: 900000,
        matchKind: CompletionMatchKind.englishExact,
        sources: {CompletionSourceKind.base},
      ),
  ];
}

class _MemoryStorage extends Fake implements LocalStorageService {
  final values = <String, Object?>{};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) =>
      (values[key] as T?) ?? defaultValue;

  @override
  Future<void> setSetting<T>(String key, T value) async => values[key] = value;

  @override
  Future<void> deleteSetting(String key) async => values.remove(key);
}

void main() {
  late Directory directory;
  late LexicalSearchIndex index;
  late SearchLexicon lexicon;
  late _FakeCatalog catalog;
  var settings = const AutocompleteSettings();

  LexicalEnhancementSource source() => LexicalEnhancementSource(
    index: index,
    lexicon: () async => lexicon,
    catalog: catalog,
    settings: () => settings,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    directory = Directory.systemTemp.createTempSync('lexical_index_test');
    final catalogPath = '${directory.path}/catalog.db';
    final db = await databaseFactoryFfi.openDatabase(catalogPath);
    await db.execute(
      'CREATE TABLE tags(name TEXT, category INTEGER, post_count INTEGER)',
    );
    await db.execute(
      'CREATE TABLE zh_translations(tag TEXT, zh_cn TEXT, mode TEXT)',
    );
    for (final (name, posts) in _tags) {
      await db.insert('tags', {
        'name': name,
        'category': 0,
        'post_count': posts,
      });
    }
    await db.close();

    final pinyinGz = File(
      'assets/search_lexicon/hanzi_pinyin.json.gz',
    ).readAsBytesSync();
    final wordsGz = File(
      'assets/search_lexicon/zh_en_lexicon.json.gz',
    ).readAsBytesSync();
    lexicon = SearchLexicon.decode(pinyinGz: pinyinGz, crossLingualGz: wordsGz);
    final ameGz = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode({'entries': _ame}))),
    );
    index = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: buildLexicalIndex,
      resolveSources: () async => LexicalIndexSources(
        indexPath: '${directory.path}/index/lexical_index.db',
        catalogPath: catalogPath,
        catalogVersion: 'fixture',
        ameLexiconGz: ameGz,
        pinyinGz: pinyinGz,
        crossLingualGz: wordsGz,
      ),
    );
    expect(await index.ready(), isNotNull);
  });

  tearDownAll(() async {
    await index.dispose();
    directory.deleteSync(recursive: true);
  });

  setUp(() {
    settings = const AutocompleteSettings();
    catalog = _FakeCatalog();
  });

  test('同音中文命中衬衫，以读音开头的标签排在后面', () async {
    final rows = await source().supplement(_query('陈山'), const []);
    final shirt = rows.firstWhere((row) => row.canonicalTag == 'shirt');
    expect(shirt.matchKind, CompletionMatchKind.homophone);
    expect(shirt.translation, '衬衫');
    expect(shirt.matchQuality, 1);
    final tucked = rows.firstWhere(
      (row) => row.canonicalTag == 'shirt_tucked_in',
    );
    expect(tucked.matchQuality, lessThan(shirt.matchQuality));
    // Mid-label homophones are left out.
    expect(rows.map((row) => row.canonicalTag), isNot(contains('white_shirt')));
  });

  test('模糊音只在开启的音对下命中', () async {
    var rows = await source().supplement(_query('城山'), const []);
    expect(
      rows.where((row) => row.matchKind == CompletionMatchKind.fuzzyPinyin),
      contains(
        predicate<CompletionCandidate>((r) => r.canonicalTag == 'shirt'),
      ),
    );
    settings = settings.copyWith(fuzzyPinyinRules: const {});
    rows = await source().supplement(_query('城山'), const []);
    expect(rows.map((row) => row.canonicalTag), isNot(contains('shirt')));
  });

  test('自然码双拼、全拼和首字母都能找到衬衫', () async {
    Future<CompletionCandidate> first(String letters) async =>
        (await source().supplement(_query(letters), const [])).first;

    final shuangpin = await first('ifuj');
    expect(shuangpin.canonicalTag, 'shirt');
    expect(shuangpin.matchKind, CompletionMatchKind.shuangpin);

    final pinyin = await first('chenshan');
    expect(pinyin.canonicalTag, 'shirt');
    expect(pinyin.matchKind, CompletionMatchKind.pinyin);

    final initials = await first('cs');
    expect(initials.canonicalTag, 'shirt');
    expect(initials.matchKind, CompletionMatchKind.pinyinInitials);

    settings = settings.copyWith(pinyinZiranmaEnabled: false);
    final withoutZiranma = await source().supplement(_query('ifuj'), const []);
    expect(withoutZiranma, isEmpty);
  });

  test('多字近似匹配按共同字与顺序打分', () async {
    final rows = await source().supplement(_query('拨起头发'), const []);
    final approximate = rows.firstWhere(
      (row) => row.matchKind == CompletionMatchKind.approximate,
    );
    expect(approximate.canonicalTag, 'hair_flip');
    expect(approximate.matchQuality, closeTo(0.75, 0.001));
  });

  test('拆词匹配英文 tag，多余词越少越靠前', () async {
    final rows = await source().supplement(_query('坐在椅子上'), const []);
    final crossLingual = rows
        .where((row) => row.matchKind == CompletionMatchKind.crossLingual)
        .toList();
    expect(crossLingual.map((row) => row.canonicalTag), [
      'sitting_on_chair',
      'sitting_on_office_chair',
    ]);
    expect(crossLingual.first.matchHint, '坐在·椅子');
    expect(catalog.groups.single, [contains('sitting'), contains('chair')]);
  });

  test('能读成拼音的字母不当作英文拼写错误', () async {
    final rows = await source().supplement(_query('chenshan'), const []);
    expect(
      rows.where((row) => row.matchKind == CompletionMatchKind.spellCorrected),
      isEmpty,
    );
  });

  test('没有字面结果时纠正英文拼写', () async {
    final rows = await source().supplement(_query('shrit'), const []);
    final corrected = rows.firstWhere(
      (row) => row.matchKind == CompletionMatchKind.spellCorrected,
    );
    expect(corrected.canonicalTag, 'shirt');
    expect(corrected.matchHint, 'shirt');

    settings = settings.copyWith(spellCorrectionEnabled: false);
    expect(
      (await source().supplement(
        _query('shrit'),
        const [],
      )).where((row) => row.matchKind == CompletionMatchKind.spellCorrected),
      isEmpty,
    );
  });

  test('分类筛选与开关生效', () async {
    expect(
      await source().supplement(
        _query('陈山', category: TagCategory.character),
        const [],
      ),
      isEmpty,
    );
    settings = settings.copyWith(
      pinyinSearchEnabled: false,
      approximateMatchEnabled: false,
      crossLingualEnabled: false,
    );
    expect(await source().supplement(_query('陈山'), const []), isEmpty);
  });

  group('排序', () {
    CompletionCandidate row(
      String tag,
      CompletionMatchKind kind, {
      int posts = 100,
      double quality = 0,
    }) => CompletionCandidate(
      canonicalTag: tag,
      category: TagCategory.general,
      postCount: posts,
      matchKind: kind,
      sources: const {CompletionSourceKind.base},
      matchQuality: quality,
    );

    test('增强结果排在字面结果之后，加权只在同类内重排', () {
      final sorted = CompletionRanker.mergeAndSort(
        [
          row(
            'homophone_popular',
            CompletionMatchKind.homophone,
            posts: 9000000,
          ),
          row('literal', CompletionMatchKind.chinesePrefix),
          row('homophone_used', CompletionMatchKind.homophone, posts: 10),
          row('initials', CompletionMatchKind.pinyinInitials, quality: 1),
        ],
        query: _query('陈山'),
        boosts: const {'homophone_used': 6000, 'initials': 6000},
      );
      expect(sorted.map((row) => row.canonicalTag), [
        'literal',
        'homophone_used',
        'homophone_popular',
        'initials',
      ]);
    });

    test('语义结果排在拼音、拆词等词法增强之后', () {
      final sorted = CompletionRanker.mergeAndSort(
        [
          const CompletionCandidate(
            canonicalTag: 'semantic',
            category: TagCategory.general,
            postCount: 9000000,
            matchKind: CompletionMatchKind.fullText,
            sources: {CompletionSourceKind.base},
            semanticScore: 0.99,
          ),
          row('initials', CompletionMatchKind.pinyinInitials),
          row('split', CompletionMatchKind.crossLingual),
        ],
        query: _query('坐在椅子上'),
      );
      expect(sorted.map((row) => row.canonicalTag), [
        'split',
        'initials',
        'semantic',
      ]);
    });

    test('同一 tag 合并时保留更好的匹配方式和说明', () {
      final sorted = CompletionRanker.mergeAndSort([
        row('shirt', CompletionMatchKind.approximate, quality: 0.9),
        row('shirt', CompletionMatchKind.homophone, quality: 0.6),
      ], query: _query('陈山'));
      expect(sorted.single.matchKind, CompletionMatchKind.homophone);
      expect(sorted.single.matchQuality, 0.6);
    });
  });

  test('使用记录随次数增长、随时间衰减，可清除', () async {
    var now = DateTime.utc(2026, 10, 1);
    final storage = _MemoryStorage();
    final history = TagUsageHistory(storage, now: () => now);
    await history.record('shirt');
    await history.record('Shirt');
    await history.record('socks');
    expect(history.score('shirt'), greaterThan(history.score('socks')));
    final fresh = history.score('shirt');
    now = now.add(const Duration(days: 45));
    expect(
      TagUsageHistory(storage, now: () => now).score('shirt'),
      closeTo(fresh / 2, 0.001),
    );

    final signals = DefaultCompletionRankingSignals(
      history: history,
      settings: () => const AutocompleteSettings(),
    );
    final boosts = await signals.boosts(_query('s'));
    expect(boosts['shirt'], greaterThan(boosts['socks']!));
    expect(boosts['shirt'], lessThanOrEqualTo(3000));

    await history.clear();
    expect(history.isEmpty, isTrue);
    expect(storage.values, isEmpty);
  });

  test('索引构建失败后同一输入不立即重试', () async {
    var builds = 0;
    final failing = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: (_) async {
        builds++;
        throw StateError('no space');
      },
      resolveSources: () async => LexicalIndexSources(
        indexPath: '${directory.path}/failing/lexical_index.db',
        catalogPath: '${directory.path}/missing.db',
        catalogVersion: 'fixture',
        ameLexiconGz: Uint8List(0),
        pinyinGz: Uint8List(0),
        crossLingualGz: Uint8List(0),
      ),
    );
    expect(await failing.ready(), isNull);
    expect(await failing.ready(), isNull);
    expect(await failing.pinyinMatches('py : (^chen)'), isEmpty);
    expect(builds, 1);
    await failing.dispose();
  });

  test('上下文取光标前最近的 tag', () {
    const query = CompletionQuery(
      fullText: 'shirt, socks, smile, ',
      cursorPosition: 14,
      token: '',
      replacementRange: TextReplacementRange(start: 0, end: 0),
      existingTags: {'shirt', 'socks', 'smile'},
      limit: 20,
      locale: 'zh',
    );
    expect(DefaultCompletionRankingSignals.nearbyTags(query), [
      'socks',
      'shirt',
    ]);
  });
}
