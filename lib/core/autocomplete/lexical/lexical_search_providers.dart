import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../database/asset_database_manager.dart';
import '../../storage/local_storage_service.dart';
import '../ame_zh_lexicon.dart';
import '../autocomplete_providers.dart';
import '../autocomplete_settings.dart';
import 'completion_ranking_signals.dart';
import 'lexical_enhancement_source.dart';
import 'lexical_search_index.dart';
import 'search_lexicon.dart';
import 'tag_usage_history.dart';

/// Bundled pinyin and word data: raw bytes for the index build, decoded
/// tables (off the UI isolate) for query parsing.
class SearchLexiconAssets {
  SearchLexiconAssets({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<(Uint8List, Uint8List)>? _bytes;
  Future<SearchLexicon>? _lexicon;

  Future<(Uint8List, Uint8List)> bytes() => _bytes ??= () async {
    final pinyin = await _bundle.load(SearchLexicon.pinyinAsset);
    final words = await _bundle.load(SearchLexicon.crossLingualAsset);
    return (_view(pinyin), _view(words));
  }();

  Future<SearchLexicon> lexicon() => _lexicon ??= _decode();

  Future<SearchLexicon> _decode() async {
    try {
      final (pinyin, words) = await bytes();
      return await Isolate.run(
        () => SearchLexicon.decode(pinyinGz: pinyin, crossLingualGz: words),
      );
    } catch (_) {
      _bytes = null;
      _lexicon = null;
      rethrow;
    }
  }

  static Uint8List _view(ByteData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

final searchLexiconAssetsProvider = Provider<SearchLexiconAssets>(
  (ref) => SearchLexiconAssets(),
);

/// The device-local pinyin/character/spelling index, rebuilt in the
/// background whenever the catalog, bundled data or ffdkj dictionary change.
final lexicalSearchIndexProvider = Provider<LexicalSearchIndex>((ref) {
  final assets = ref.watch(searchLexiconAssetsProvider);
  final dictionary = ref.watch(zhDictionaryServiceProvider.notifier);
  Future<String>? catalogVersion;
  Future<Uint8List>? ameBytes;
  final index = LexicalSearchIndex(
    resolveSources: () async {
      try {
        // Settle the dictionary first so startup builds the index only once.
        await dictionary.initialize().catchError((_) {});
        await AssetDatabaseManager.initialize();
        final (pinyin, words) = await assets.bytes();
        final directory = await getApplicationSupportDirectory();
        return LexicalIndexSources(
          indexPath: p.join(directory.path, 'autocomplete', 'lexical_index.db'),
          catalogPath: AssetDatabaseManager.instance.tagCatalogDbPath,
          catalogVersion: await (catalogVersion ??= _catalogVersion()),
          ameLexiconGz: await (ameBytes ??= _assetBytes(AmeZhLexicon.assetKey)),
          pinyinGz: pinyin,
          crossLingualGz: words,
          zhDictionaryPath: dictionary.installedDatabasePath,
          zhDictionaryVersion: dictionary.state.version,
        );
      } catch (_) {
        catalogVersion = null;
        ameBytes = null;
        return null;
      }
    },
  );
  ref.onDispose(() => unawaited(index.dispose()));
  return index;
});

Future<String> _catalogVersion() async {
  final manifest =
      jsonDecode(await rootBundle.loadString('assets/databases/manifest.json'))
          as Map<String, dynamic>;
  final catalog =
      (manifest['databases'] as Map)[AssetDatabaseManager.tagCatalogDb] as Map;
  return (catalog['sha256'] as String).substring(0, 16);
}

Future<Uint8List> _assetBytes(String key) async {
  final data = await rootBundle.load(key);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

final lexicalEnhancementSourceProvider = Provider<LexicalEnhancementSource>((
  ref,
) {
  final assets = ref.watch(searchLexiconAssetsProvider);
  return LexicalEnhancementSource(
    index: ref.watch(lexicalSearchIndexProvider),
    lexicon: assets.lexicon,
    catalog: ref.watch(tagCatalogRepositoryProvider),
    settings: () => ref.read(autocompleteSettingsProvider),
  );
});

/// Device-local record of accepted completions; never synced.
final tagUsageHistoryProvider = Provider<TagUsageHistory>(
  (ref) => TagUsageHistory(ref.read(localStorageServiceProvider)),
);

final completionRankingSignalsProvider =
    Provider<DefaultCompletionRankingSignals>(
      (ref) => DefaultCompletionRankingSignals(
        history: ref.watch(tagUsageHistoryProvider),
        settings: () => ref.read(autocompleteSettingsProvider),
        cooccurrence: ref.watch(cooccurrenceCompletionSourceProvider),
      ),
    );
