// Evaluates non-AI tag search on the real bundled catalog: each golden query
// is ranked with literal sources only ("before") and with the lexical
// enhancements merged in ("after").
//
//   flutter test tool/search_eval/search_eval_test.dart
//
// The first run builds the lexical index into tool/.tmp/search-eval/ (later
// runs reuse it); the report is written next to it. This is a development
// tool on the full data set, hence its own time limit.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/ame_zh_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/completion_ranker.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_enhancement_source.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_index_builder.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_search_index.dart';
import 'package:nai_launcher/core/autocomplete/lexical/search_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _catalogPath = 'assets/databases/tag_catalog.db';
const _outputDirectory = 'tool/.tmp/search-eval';
const _window = 20;

CompletionQuery _query(String token) => CompletionQuery(
  fullText: token,
  cursorPosition: token.length,
  token: token,
  replacementRange: TextReplacementRange(start: 0, end: token.length),
  existingTags: const {},
  limit: 50,
  locale: 'zh',
);

int? _rank(List<CompletionCandidate> rows, List<String> expected) {
  for (var i = 0; i < rows.length; i++) {
    if (expected.contains(rows[i].canonicalTag)) return i + 1;
  }
  return null;
}

void main() {
  test('非 AI 搜索评测', () async {
    sqfliteFfiInit();
    final catalogFile = File(_catalogPath);
    final header = catalogFile.openSync()..setPositionSync(0);
    final magic = utf8.decode(header.readSync(15), allowMalformed: true);
    header.closeSync();
    expect(magic, 'SQLite format 3', reason: 'run git lfs pull first');

    final pinyinGz = File(
      'assets/search_lexicon/hanzi_pinyin.json.gz',
    ).readAsBytesSync();
    final wordsGz = File(
      'assets/search_lexicon/zh_en_lexicon.json.gz',
    ).readAsBytesSync();
    final ameGz = File(AmeZhLexicon.assetKey).readAsBytesSync();
    final lexicon = SearchLexicon.decode(
      pinyinGz: pinyinGz,
      crossLingualGz: wordsGz,
    );

    // sqflite resolves relative paths against its own directory.
    final catalogPath = catalogFile.absolute.path;
    final outputDirectory = Directory(_outputDirectory).absolute.path;
    final catalogDb = await databaseFactoryFfi.openDatabase(
      catalogPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final catalog = TagCatalogRepository(database: catalogDb);
    final ame = AmeZhLexicon(
      loadBytes: () async => Uint8List.fromList(ameGz),
      decode: (bytes) async => AmeZhLexiconIndex.decode(bytes),
    );
    final stopwatch = Stopwatch()..start();
    final index = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: buildLexicalIndex,
      resolveSources: () async => LexicalIndexSources(
        indexPath: '$outputDirectory/lexical_index.db',
        catalogPath: catalogPath,
        catalogVersion: catalogFile.lengthSync().toString(),
        ameLexiconGz: ameGz,
        pinyinGz: pinyinGz,
        crossLingualGz: wordsGz,
      ),
    );
    expect(await index.ready(), isNotNull);
    final indexMs = stopwatch.elapsedMilliseconds;
    final enhancements = LexicalEnhancementSource(
      index: index,
      lexicon: () async => lexicon,
      catalog: catalog,
      settings: () => const AutocompleteSettings(),
    );

    final golden =
        jsonDecode(
              File('tool/search_eval/golden_queries.json').readAsStringSync(),
            )
            as Map;
    final results = <Map<String, Object?>>[];
    final lines = <String>[];
    var hitsBefore = 0;
    var hitsAfter = 0;
    var top5After = 0;
    for (final item in (golden['queries'] as List).cast<Map>()) {
      final token = item['query'] as String;
      final expected = (item['expect'] as List).cast<String>();
      final query = _query(token);
      final timer = Stopwatch()..start();
      final primary = CompletionRanker.mergeAndSort([
        ...await catalog.search(query),
        ...await ame.search(query),
      ], query: query);
      final supplement = await enhancements.supplement(query, primary);
      final merged = CompletionRanker.mergeAndSort([
        ...primary,
        ...supplement,
      ], query: query);
      final elapsed = timer.elapsedMilliseconds;
      final before = _rank(primary, expected);
      final after = _rank(merged, expected);
      final row = after == null ? null : merged[after - 1];
      if (before != null && before <= _window) hitsBefore++;
      if (after != null && after <= _window) hitsAfter++;
      if (after != null && after <= 5) top5After++;
      results.add({
        'query': token,
        'expect': expected,
        'via': item['via'],
        'before': before,
        'after': after,
        'matchKind': row?.matchKind.name,
        'matchHint': row?.matchHint,
        'top5': [
          for (final row in merged.take(5))
            '${row.canonicalTag} (${row.matchKind.name}${row.translation == null ? '' : ' ${row.translation}'})',
        ],
        'ms': elapsed,
      });
      lines.add(
        '${token.padRight(14)} ${'${before ?? '-'}'.padLeft(4)} → '
        '${'${after ?? '-'}'.padLeft(4)}  ${row?.matchKind.name ?? ''}'
        '  [${merged.take(3).map((row) => row.canonicalTag).join(', ')}]'
        '  ${elapsed}ms',
      );
      // Literal matches must never be pushed down by the enhancements.
      if (before != null) {
        expect(after, lessThanOrEqualTo(before), reason: token);
      }
    }
    final total = results.length;
    final summary =
        'index ${indexMs}ms · hit@$_window before $hitsBefore/$total, '
        'after $hitsAfter/$total · top5 after $top5After/$total';
    Directory(_outputDirectory).createSync(recursive: true);
    File('$_outputDirectory/report.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'summary': summary, 'results': results}),
    );
    // ignore: avoid_print
    print([...lines, summary].join('\n'));

    await index.dispose();
    await catalogDb.close();
  });
}
