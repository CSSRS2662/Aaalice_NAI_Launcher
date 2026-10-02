import 'package:flutter/material.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';

/// How a non-literal row matched (pinyin, typo fix, …); null for literal
/// matches, which need no explanation.
String? completionMatchNoteLabel(
  BuildContext context,
  CompletionCandidate candidate,
) {
  final l10n = context.l10n;
  return switch (candidate.matchKind) {
    CompletionMatchKind.homophone => l10n.autocomplete_matchHomophone,
    CompletionMatchKind.fuzzyPinyin => l10n.autocomplete_matchFuzzyPinyin,
    CompletionMatchKind.pinyin => l10n.autocomplete_matchPinyin,
    CompletionMatchKind.shuangpin => l10n.autocomplete_matchShuangpin,
    CompletionMatchKind.pinyinInitials => l10n.autocomplete_matchInitials,
    CompletionMatchKind.approximate => l10n.autocomplete_matchApproximate,
    CompletionMatchKind.crossLingual => l10n.autocomplete_matchCrossLingual,
    CompletionMatchKind.spellCorrected => l10n.autocomplete_matchSpellCorrected,
    CompletionMatchKind.englishVariant => l10n.autocomplete_matchEnglishVariant,
    CompletionMatchKind.fullText when candidate.semanticScore != null =>
      l10n.autocomplete_matchSemantic,
    _ => null,
  };
}

/// A small label in front of a row's secondary text; the hint (corrected
/// word, split words) is in the tooltip.
class CompletionMatchNote extends StatelessWidget {
  const CompletionMatchNote({super.key, required this.label, this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    final hint = this.hint;
    return Tooltip(
      message: hint == null || hint.isEmpty ? label : '$label · $hint',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 9,
            height: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
