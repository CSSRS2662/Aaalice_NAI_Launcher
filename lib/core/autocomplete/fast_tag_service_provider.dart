import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ame_zh_lexicon.dart';
import 'fast_tag_service.dart';
import 'e5_translation_resolver.dart';
import 'tag_catalog_repository.dart';
import 'zh_dictionary_service.dart';

final tagCatalogRepositoryProvider = Provider<TagCatalogRepository>((ref) {
  final repository = TagCatalogRepository();
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});

final zhDictionaryServiceProvider = ChangeNotifierProvider<ZhDictionaryService>(
  (ref) {
    final service = ZhDictionaryService();
    unawaited(() async {
      await service.initialize();
      if (service.state.isInstalled) {
        await service.checkForUpdate();
      }
    }());
    return service;
  },
);

final fastTagServiceProvider = Provider<FastTagService>((ref) {
  // Download/check progress does not change translation content or its cache.
  ref.watch(
    zhDictionaryServiceProvider.select(
      (service) => (
        service.state.isInstalled,
        service.state.version,
        service.state.tagCount,
      ),
    ),
  );
  return FastTagService(
    catalog: ref.watch(tagCatalogRepositoryProvider),
    dictionary: ref.watch(zhDictionaryServiceProvider.notifier),
    fallbackTranslations: ref.watch(e5TranslationResolverProvider),
    lexicon: ref.watch(ameZhLexiconProvider),
  );
});

final e5TranslationResolverProvider = Provider<E5TranslationResolver>(
  (ref) => E5TranslationResolver(),
);

final ameZhLexiconProvider = Provider<AmeZhLexicon>((ref) => AmeZhLexicon());
