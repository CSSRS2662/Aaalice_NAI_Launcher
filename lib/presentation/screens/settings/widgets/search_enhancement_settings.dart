import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/autocomplete_settings.dart';
import '../../../../core/autocomplete/lexical/lexical_search_providers.dart';
import '../../../../core/autocomplete/lexical/pinyin_syllables.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/themed_confirm_dialog.dart';
import 'settings_card.dart';

/// Non-AI search options for tag completion: pinyin readings, approximate
/// and word-split matches, English corrections, and context/habit ranking.
class SearchEnhancementSettings extends ConsumerWidget {
  const SearchEnhancementSettings({super.key});

  static const EdgeInsetsGeometry _nestedPadding = EdgeInsetsDirectional.only(
    start: 40,
    end: 16,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(autocompleteSettingsProvider);
    final notifier = ref.read(autocompleteSettingsProvider.notifier);
    final l10n = context.l10n;
    final pinyin = settings.pinyinSearchEnabled;

    return SettingsCard(
      title: l10n.autocomplete_searchEnhancementTitle,
      icon: Icons.manage_search_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_pinyinSearch),
            subtitle: Text(l10n.autocomplete_pinyinSearchSubtitle),
            value: pinyin,
            onChanged: notifier.setPinyinSearchEnabled,
          ),
          SwitchListTile.adaptive(
            contentPadding: _nestedPadding,
            title: Text(l10n.autocomplete_pinyinFull),
            subtitle: Text(l10n.autocomplete_pinyinFullSubtitle),
            value: settings.pinyinFullEnabled,
            onChanged: pinyin ? notifier.setPinyinFullEnabled : null,
          ),
          SwitchListTile.adaptive(
            contentPadding: _nestedPadding,
            title: Text(l10n.autocomplete_pinyinZiranma),
            subtitle: Text(l10n.autocomplete_pinyinZiranmaSubtitle),
            value: settings.pinyinZiranmaEnabled,
            onChanged: pinyin ? notifier.setPinyinZiranmaEnabled : null,
          ),
          _FuzzyPinyinRules(
            padding: _nestedPadding,
            enabled: pinyin,
            selected: settings.fuzzyPinyinRules,
            onChanged: notifier.setFuzzyPinyinRule,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_approximateMatch),
            subtitle: Text(l10n.autocomplete_approximateMatchSubtitle),
            value: settings.approximateMatchEnabled,
            onChanged: notifier.setApproximateMatchEnabled,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_crossLingual),
            subtitle: Text(l10n.autocomplete_crossLingualSubtitle),
            value: settings.crossLingualEnabled,
            onChanged: notifier.setCrossLingualEnabled,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_spellCorrection),
            subtitle: Text(l10n.autocomplete_spellCorrectionSubtitle),
            value: settings.spellCorrectionEnabled,
            onChanged: notifier.setSpellCorrectionEnabled,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_contextRanking),
            subtitle: Text(l10n.autocomplete_contextRankingSubtitle),
            value: settings.contextRankingEnabled,
            onChanged: notifier.setContextRankingEnabled,
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_personalRanking),
            subtitle: Text(l10n.autocomplete_personalRankingSubtitle),
            value: settings.personalRankingEnabled,
            onChanged: notifier.setPersonalRankingEnabled,
          ),
          Padding(
            padding: _nestedPadding,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('search-enhancement-clear-usage'),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: Text(l10n.autocomplete_clearUsageHistory),
                onPressed: () => _clearUsageHistory(context, ref),
              ),
            ),
          ),
          SwitchListTile.adaptive(
            title: Text(l10n.autocomplete_showMatchNotes),
            subtitle: Text(l10n.autocomplete_showMatchNotesSubtitle),
            value: settings.showMatchNotes,
            onChanged: notifier.setShowMatchNotes,
          ),
        ],
      ),
    );
  }

  static Future<void> _clearUsageHistory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final history = ref.read(tagUsageHistoryProvider);
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: context.l10n.autocomplete_clearUsageHistory,
      content: context.l10n.autocomplete_clearUsageHistoryConfirm,
      confirmText: context.l10n.common_confirm,
      cancelText: context.l10n.common_cancel,
      type: ThemedConfirmDialogType.danger,
      icon: Icons.delete_sweep_outlined,
    );
    if (!confirmed) return;
    await history.clear();
    if (context.mounted) {
      AppToast.success(context, context.l10n.autocomplete_usageHistoryCleared);
    }
  }
}

class _FuzzyPinyinRules extends StatelessWidget {
  const _FuzzyPinyinRules({
    required this.padding,
    required this.enabled,
    required this.selected,
    required this.onChanged,
  });

  final EdgeInsetsGeometry padding;
  final bool enabled;
  final Set<FuzzyPinyinRule> selected;
  final Future<void> Function(FuzzyPinyinRule rule, bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabledColor = theme.disabledColor;
    return Padding(
      padding: padding.add(const EdgeInsets.only(top: 4, bottom: 8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.autocomplete_fuzzyPinyin,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: enabled ? null : disabledColor,
            ),
          ),
          Text(
            context.l10n.autocomplete_fuzzyPinyinSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled
                  ? theme.colorScheme.onSurfaceVariant
                  : disabledColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final rule in FuzzyPinyinRule.values)
                FilterChip(
                  key: ValueKey('fuzzy-pinyin-${rule.id}'),
                  label: Text(rule.id.replaceFirst('-', ' / ')),
                  selected: selected.contains(rule),
                  onSelected: enabled
                      ? (value) => onChanged(rule, value)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
