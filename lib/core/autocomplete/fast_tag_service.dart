import 'completion_models.dart';
import 'completion_ranker.dart';
import 'tag_catalog_repository.dart';
import 'zh_dictionary_service.dart';

/// Reusable local tag search and translation boundary.
///
/// Consumers do not need to know which bundled or optional database owns a
/// result. Search and translation precedence live here so autocomplete,
/// prompt tools, and future modules share the same behavior.
class FastTagService implements CompletionSource, TranslationResolver {
  const FastTagService({
    required TagCatalogRepository catalog,
    required ZhDictionaryService dictionary,
    TranslationResolver? fallbackTranslations,
  }) : _catalog = catalog,
       _dictionary = dictionary,
       _fallbackTranslations = fallbackTranslations;

  final TagCatalogRepository _catalog;
  final ZhDictionaryService _dictionary;
  final TranslationResolver? _fallbackTranslations;

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    final bundledBatches = await Future.wait([
      _catalog.search(query),
      _catalog.searchTranslations(query),
    ]);
    final dictionaryResults = await _searchOptionalDictionary(query);
    return CompletionRanker.mergeAndSort([
      ...bundledBatches.expand((batch) => batch),
      ...dictionaryResults,
    ], query: query);
  }

  /// Resolves reviewed corrections before ffdkj and bundled gap-fillers after
  /// it. A later ffdkj update can therefore replace an ordinary fallback but
  /// cannot reintroduce a confirmed mistranslation.
  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async {
    if (!locale.toLowerCase().startsWith('zh') || canonicalTags.isEmpty) {
      return const {};
    }
    final normalized = canonicalTags
        .map((tag) => tag.trim().toLowerCase().replaceAll(' ', '_'))
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return const {};

    final overrides = await _catalog.resolveTranslations(
      normalized,
      mode: BundledTranslationMode.override,
    );
    final dictionaryTags = normalized
        .where((tag) => !overrides.containsKey(tag))
        .toList(growable: false);
    final dictionary = await _resolveOptionalDictionary(
      dictionaryTags,
      locale: locale,
    );
    final missingTags = dictionaryTags
        .where((tag) => !dictionary.containsKey(tag))
        .toList(growable: false);
    final fallbacks = await _catalog.resolveTranslations(
      missingTags,
      mode: BundledTranslationMode.missing,
    );
    final resolved = {...overrides, ...dictionary, ...fallbacks};
    final remaining = normalized
        .where((tag) => !resolved.containsKey(tag))
        .toList(growable: false);
    if (remaining.isNotEmpty && _fallbackTranslations != null) {
      try {
        final labels = await _fallbackTranslations.resolve(
          remaining,
          locale: locale,
        );
        for (final tag in remaining) {
          final label = labels[tag]?.trim();
          if (label != null && label.isNotEmpty) resolved[tag] = label;
        }
      } catch (_) {
        // Optional corpus labels must not break installed dictionary results.
      }
    }
    return resolved;
  }

  Future<Map<String, String>> resolveFuzzy(List<String> canonicalTags) async {
    try {
      return await _dictionary.resolveFuzzy(canonicalTags);
    } catch (_) {
      return const {};
    }
  }

  Future<List<CompletionCandidate>> _searchOptionalDictionary(
    CompletionQuery query,
  ) async {
    try {
      return await _dictionary.search(query);
    } catch (_) {
      // ffdkj is user-installed optional data; bundled completion must remain
      // available when that database is absent, outdated, or damaged.
      return const [];
    }
  }

  Future<Map<String, String>> _resolveOptionalDictionary(
    List<String> canonicalTags, {
    required String locale,
  }) async {
    try {
      return await _dictionary.resolve(canonicalTags, locale: locale);
    } catch (_) {
      // The bundled fallback is independently usable without ffdkj.
      return const {};
    }
  }
}
