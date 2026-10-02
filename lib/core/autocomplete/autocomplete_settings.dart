import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/storage_keys.dart';
import '../storage/local_storage_service.dart';
import 'completion_models.dart';
import 'lexical/pinyin_syllables.dart';

class AutocompleteSettings {
  const AutocompleteSettings({
    this.enabled = true,
    this.resultLimit = CompletionResultLimits.all,
    this.showAliases = true,
    this.showTranslations = true,
    this.autoInsertComma = true,
    this.replaceUnderscores = false,
    this.openOnTagClick = false,
    this.danbooruEnabled = true,
    this.relatedTagsEnabled = true,
    this.autoDownloadRelatedData = true,
    this.llmTranslationEnabled = false,
    this.zhInstallPromptDismissed = false,
    this.pinyinSearchEnabled = true,
    this.pinyinFullEnabled = true,
    this.pinyinZiranmaEnabled = true,
    this.fuzzyPinyinRules = FuzzyPinyinRule.defaults,
    this.approximateMatchEnabled = true,
    this.crossLingualEnabled = true,
    this.spellCorrectionEnabled = true,
    this.contextRankingEnabled = true,
    this.personalRankingEnabled = true,
    this.showMatchNotes = true,
  });

  final bool enabled;
  final int resultLimit;
  final bool showAliases;
  final bool showTranslations;
  final bool autoInsertComma;
  final bool replaceUnderscores;
  final bool openOnTagClick;
  final bool danbooruEnabled;
  final bool relatedTagsEnabled;
  final bool autoDownloadRelatedData;
  final bool llmTranslationEnabled;
  final bool zhInstallPromptDismissed;

  /// Match Chinese labels by pinyin: homophones of a Chinese query, and
  /// letters read as full pinyin, Ziranma double pinyin or initials.
  final bool pinyinSearchEnabled;
  final bool pinyinFullEnabled;
  final bool pinyinZiranmaEnabled;
  final Set<FuzzyPinyinRule> fuzzyPinyinRules;

  /// Chinese labels that share most characters with the query, in order.
  final bool approximateMatchEnabled;

  /// Split a Chinese query into words and search their English tag tokens.
  final bool crossLingualEnabled;

  /// Correct English typos and try other word forms when nothing matches.
  final bool spellCorrectionEnabled;

  /// Prefer tags that often appear with the tags around the cursor.
  final bool contextRankingEnabled;

  /// Prefer tags this device accepted before.
  final bool personalRankingEnabled;

  /// Show how a non-literal row matched (pinyin, typo fix, …).
  final bool showMatchNotes;

  AutocompleteSettings copyWith({
    bool? enabled,
    int? resultLimit,
    bool? showAliases,
    bool? showTranslations,
    bool? autoInsertComma,
    bool? replaceUnderscores,
    bool? openOnTagClick,
    bool? danbooruEnabled,
    bool? relatedTagsEnabled,
    bool? autoDownloadRelatedData,
    bool? llmTranslationEnabled,
    bool? zhInstallPromptDismissed,
    bool? pinyinSearchEnabled,
    bool? pinyinFullEnabled,
    bool? pinyinZiranmaEnabled,
    Set<FuzzyPinyinRule>? fuzzyPinyinRules,
    bool? approximateMatchEnabled,
    bool? crossLingualEnabled,
    bool? spellCorrectionEnabled,
    bool? contextRankingEnabled,
    bool? personalRankingEnabled,
    bool? showMatchNotes,
  }) {
    return AutocompleteSettings(
      enabled: enabled ?? this.enabled,
      resultLimit: resultLimit ?? this.resultLimit,
      showAliases: showAliases ?? this.showAliases,
      showTranslations: showTranslations ?? this.showTranslations,
      autoInsertComma: autoInsertComma ?? this.autoInsertComma,
      replaceUnderscores: replaceUnderscores ?? this.replaceUnderscores,
      openOnTagClick: openOnTagClick ?? this.openOnTagClick,
      danbooruEnabled: danbooruEnabled ?? this.danbooruEnabled,
      relatedTagsEnabled: relatedTagsEnabled ?? this.relatedTagsEnabled,
      autoDownloadRelatedData:
          autoDownloadRelatedData ?? this.autoDownloadRelatedData,
      llmTranslationEnabled:
          llmTranslationEnabled ?? this.llmTranslationEnabled,
      zhInstallPromptDismissed:
          zhInstallPromptDismissed ?? this.zhInstallPromptDismissed,
      pinyinSearchEnabled: pinyinSearchEnabled ?? this.pinyinSearchEnabled,
      pinyinFullEnabled: pinyinFullEnabled ?? this.pinyinFullEnabled,
      pinyinZiranmaEnabled: pinyinZiranmaEnabled ?? this.pinyinZiranmaEnabled,
      fuzzyPinyinRules: fuzzyPinyinRules ?? this.fuzzyPinyinRules,
      approximateMatchEnabled:
          approximateMatchEnabled ?? this.approximateMatchEnabled,
      crossLingualEnabled: crossLingualEnabled ?? this.crossLingualEnabled,
      spellCorrectionEnabled:
          spellCorrectionEnabled ?? this.spellCorrectionEnabled,
      contextRankingEnabled:
          contextRankingEnabled ?? this.contextRankingEnabled,
      personalRankingEnabled:
          personalRankingEnabled ?? this.personalRankingEnabled,
      showMatchNotes: showMatchNotes ?? this.showMatchNotes,
    );
  }
}

final autocompleteSettingsProvider =
    StateNotifierProvider<AutocompleteSettingsNotifier, AutocompleteSettings>((
      ref,
    ) {
      return AutocompleteSettingsNotifier(
        ref.read(localStorageServiceProvider),
      );
    });

class AutocompleteSettingsNotifier extends StateNotifier<AutocompleteSettings> {
  AutocompleteSettingsNotifier(this._storage) : super(_load(_storage));

  final LocalStorageService _storage;

  static AutocompleteSettings _load(LocalStorageService storage) {
    try {
      return AutocompleteSettings(
        enabled:
            storage.getSetting<bool>(
              StorageKeys.enableAutocomplete,
              defaultValue: true,
            ) ??
            true,
        resultLimit: _normalizeResultLimit(
          storage.getSetting<int>(
                StorageKeys.autocompleteResultLimit,
                defaultValue: CompletionResultLimits.all,
              ) ??
              CompletionResultLimits.all,
        ),
        showAliases:
            storage.getSetting<bool>(
              StorageKeys.autocompleteShowAliases,
              defaultValue: true,
            ) ??
            true,
        showTranslations:
            storage.getSetting<bool>(
              StorageKeys.autocompleteShowTranslations,
              defaultValue: true,
            ) ??
            true,
        autoInsertComma:
            storage.getSetting<bool>(
              StorageKeys.autocompleteAutoComma,
              defaultValue: true,
            ) ??
            true,
        replaceUnderscores:
            storage.getSetting<bool>(
              StorageKeys.autocompleteReplaceUnderscores,
              defaultValue: false,
            ) ??
            false,
        openOnTagClick:
            storage.getSetting<bool>(
              StorageKeys.autocompleteOpenOnTagClick,
              defaultValue: false,
            ) ??
            false,
        danbooruEnabled:
            storage.getSetting<bool>(
              StorageKeys.autocompleteDanbooruEnabled,
              defaultValue: true,
            ) ??
            true,
        relatedTagsEnabled:
            storage.getSetting<bool>(
              StorageKeys.enableCooccurrenceRecommendation,
              defaultValue: true,
            ) ??
            true,
        autoDownloadRelatedData:
            storage.getSetting<bool>(
              StorageKeys.autoDownloadCooccurrenceData,
              defaultValue: true,
            ) ??
            true,
        llmTranslationEnabled:
            storage.getSetting<bool>(
              StorageKeys.autocompleteLlmTranslationEnabled,
              defaultValue: false,
            ) ??
            false,
        zhInstallPromptDismissed:
            storage.getSetting<bool>(
              StorageKeys.autocompleteZhInstallPromptDismissed,
              defaultValue: false,
            ) ??
            false,
        pinyinSearchEnabled: _flag(
          storage,
          StorageKeys.autocompletePinyinSearch,
        ),
        pinyinFullEnabled: _flag(storage, StorageKeys.autocompletePinyinFull),
        pinyinZiranmaEnabled: _flag(
          storage,
          StorageKeys.autocompletePinyinZiranma,
        ),
        fuzzyPinyinRules: _fuzzyRules(storage),
        approximateMatchEnabled: _flag(
          storage,
          StorageKeys.autocompleteApproximateMatch,
        ),
        crossLingualEnabled: _flag(
          storage,
          StorageKeys.autocompleteCrossLingual,
        ),
        spellCorrectionEnabled: _flag(
          storage,
          StorageKeys.autocompleteSpellCorrection,
        ),
        contextRankingEnabled: _flag(
          storage,
          StorageKeys.autocompleteContextRanking,
        ),
        personalRankingEnabled: _flag(
          storage,
          StorageKeys.autocompletePersonalRanking,
        ),
        showMatchNotes: _flag(storage, StorageKeys.autocompleteShowMatchNotes),
      );
    } catch (_) {
      return const AutocompleteSettings();
    }
  }

  static bool _flag(LocalStorageService storage, String key) =>
      storage.getSetting<bool>(key, defaultValue: true) ?? true;

  static Set<FuzzyPinyinRule> _fuzzyRules(LocalStorageService storage) {
    final stored = storage.getSetting<dynamic>(StorageKeys.autocompleteFuzzyPinyin);
    if (stored is! List) return FuzzyPinyinRule.defaults;
    return {
      for (final id in stored.whereType<String>())
        if (FuzzyPinyinRule.fromId(id) case final rule?) rule,
    };
  }

  Future<void> setPinyinSearchEnabled(bool value) => _set(
    state.copyWith(pinyinSearchEnabled: value),
    StorageKeys.autocompletePinyinSearch,
    value,
  );

  Future<void> setPinyinFullEnabled(bool value) => _set(
    state.copyWith(pinyinFullEnabled: value),
    StorageKeys.autocompletePinyinFull,
    value,
  );

  Future<void> setPinyinZiranmaEnabled(bool value) => _set(
    state.copyWith(pinyinZiranmaEnabled: value),
    StorageKeys.autocompletePinyinZiranma,
    value,
  );

  Future<void> setFuzzyPinyinRule(FuzzyPinyinRule rule, bool enabled) {
    final next = {...state.fuzzyPinyinRules};
    enabled ? next.add(rule) : next.remove(rule);
    final ordered = [
      for (final candidate in FuzzyPinyinRule.values)
        if (next.contains(candidate)) candidate,
    ];
    return _set(
      state.copyWith(fuzzyPinyinRules: Set.unmodifiable(ordered)),
      StorageKeys.autocompleteFuzzyPinyin,
      [for (final rule in ordered) rule.id],
    );
  }

  Future<void> setApproximateMatchEnabled(bool value) => _set(
    state.copyWith(approximateMatchEnabled: value),
    StorageKeys.autocompleteApproximateMatch,
    value,
  );

  Future<void> setCrossLingualEnabled(bool value) => _set(
    state.copyWith(crossLingualEnabled: value),
    StorageKeys.autocompleteCrossLingual,
    value,
  );

  Future<void> setSpellCorrectionEnabled(bool value) => _set(
    state.copyWith(spellCorrectionEnabled: value),
    StorageKeys.autocompleteSpellCorrection,
    value,
  );

  Future<void> setContextRankingEnabled(bool value) => _set(
    state.copyWith(contextRankingEnabled: value),
    StorageKeys.autocompleteContextRanking,
    value,
  );

  Future<void> setPersonalRankingEnabled(bool value) => _set(
    state.copyWith(personalRankingEnabled: value),
    StorageKeys.autocompletePersonalRanking,
    value,
  );

  Future<void> setShowMatchNotes(bool value) => _set(
    state.copyWith(showMatchNotes: value),
    StorageKeys.autocompleteShowMatchNotes,
    value,
  );

  Future<void> setEnabled(bool value) => _set(
    state.copyWith(enabled: value),
    StorageKeys.enableAutocomplete,
    value,
  );

  Future<void> setResultLimit(int value) {
    final normalized = _normalizeResultLimit(value);
    return _set(
      state.copyWith(resultLimit: normalized),
      StorageKeys.autocompleteResultLimit,
      normalized,
    );
  }

  static int _normalizeResultLimit(int value) =>
      CompletionResultLimits.isAll(value)
      ? CompletionResultLimits.all
      : value.clamp(5, 100);

  Future<void> setShowAliases(bool value) => _set(
    state.copyWith(showAliases: value),
    StorageKeys.autocompleteShowAliases,
    value,
  );

  Future<void> setShowTranslations(bool value) => _set(
    state.copyWith(showTranslations: value),
    StorageKeys.autocompleteShowTranslations,
    value,
  );

  Future<void> setAutoInsertComma(bool value) => _set(
    state.copyWith(autoInsertComma: value),
    StorageKeys.autocompleteAutoComma,
    value,
  );

  Future<void> setReplaceUnderscores(bool value) => _set(
    state.copyWith(replaceUnderscores: value),
    StorageKeys.autocompleteReplaceUnderscores,
    value,
  );

  Future<void> setOpenOnTagClick(bool value) => _set(
    state.copyWith(openOnTagClick: value),
    StorageKeys.autocompleteOpenOnTagClick,
    value,
  );

  Future<void> setDanbooruEnabled(bool value) => _set(
    state.copyWith(danbooruEnabled: value),
    StorageKeys.autocompleteDanbooruEnabled,
    value,
  );

  Future<void> setRelatedTagsEnabled(bool value) => _set(
    state.copyWith(relatedTagsEnabled: value),
    StorageKeys.enableCooccurrenceRecommendation,
    value,
  );

  Future<void> setAutoDownloadRelatedData(bool value) => _set(
    state.copyWith(autoDownloadRelatedData: value),
    StorageKeys.autoDownloadCooccurrenceData,
    value,
  );

  Future<void> setLlmTranslationEnabled(bool value) => _set(
    state.copyWith(llmTranslationEnabled: value),
    StorageKeys.autocompleteLlmTranslationEnabled,
    value,
  );

  Future<void> dismissZhInstallPrompt() => _set(
    state.copyWith(zhInstallPromptDismissed: true),
    StorageKeys.autocompleteZhInstallPromptDismissed,
    true,
  );

  Future<void> _set<T>(AutocompleteSettings next, String key, T value) async {
    state = next;
    await _storage.setSetting<T>(key, value);
  }
}
