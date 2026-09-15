import 'package:nai_launcher/presentation/widgets/common/horizontal_action_strip.dart';
import 'package:flutter/material.dart';
import '../../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/image/image_params.dart'
    show ImageParamsExtension;
import '../../../providers/image_generation_provider.dart';
import '../../../providers/prompt_token_counter_provider.dart';
import '../../../widgets/prompt/prompt_token_count_bar.dart';
import '../../../widgets/common/translated_tag_text.dart';
import '../../../widgets/prompt/prompt_footer_style.dart';
import '../../../widgets/prompt/prompt_tag_mode_toggle.dart';

class PromptInputFooter extends ConsumerWidget {
  const PromptInputFooter({
    super.key,
    required this.target,
    required this.topPadding,
    this.leading,
    this.showTransparentBackground = true,
  });

  final PromptTokenCountTarget target;
  final double topPadding;
  final Widget? leading;
  final bool showTransparentBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenUsage = ref.watch(promptTokenUsageProvider(target));
    final tokenCount = RepaintBoundary(
      key: const ValueKey('generation_prompt_footer_count'),
      child: PromptTokenCountAsyncBar(usage: tokenUsage),
    );

    final leadingControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTransparentBackground) ...[
          const PromptTransparentBackgroundToggle(),
          const SizedBox(width: 4),
        ],
        PromptTagModeToggle(
          sessionId: target == PromptTokenCountTarget.negative
              ? PromptHistorySessionIds.generationNegative
              : PromptHistorySessionIds.generationPrompt,
        ),
      ],
    );

    final supportingContent = KeyedSubtree(
      key: const ValueKey('generation_prompt_footer_supporting'),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => HorizontalActionStrip(
                scrollKey: const ValueKey(
                  'generation_prompt_footer_actions_scroll',
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      leadingControls,
                      if (leading != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: leading,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          tokenCount,
        ],
      ),
    );

    return Padding(
      key: const ValueKey('generation_prompt_footer'),
      padding: EdgeInsets.only(top: topPadding),
      child: supportingContent,
    );
  }
}

class PromptTransparentBackgroundToggle extends ConsumerWidget {
  const PromptTransparentBackgroundToggle({
    super.key,
    this.switchStyle = false,
  });

  final bool switchStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => (
          supported: params.capabilities.supportsTransparentBackground,
          enabled: params.transparentBackground,
        ),
      ),
    );
    if (!state.supported) return const SizedBox.shrink();

    void toggle() => ref
        .read(generationParamsNotifierProvider.notifier)
        .updateTransparentBackground(!state.enabled);

    final Widget button;
    if (switchStyle) {
      button = Semantics(
        button: true,
        toggled: state.enabled,
        label: context.l10n.generation_transparentBackground,
        child: Material(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('generation_transparent_background_toggle'),
            onTap: toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.blur_on_rounded,
                      size: 20,
                      color: state.enabled
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        context.l10n.generation_transparentBackground,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: Transform.scale(
                          scale: 0.82,
                          child: Switch(
                            value: state.enabled,
                            onChanged: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      button = TextButton(
        key: const ValueKey('generation_transparent_background_toggle'),
        style: PromptFooterStyle.button(context).copyWith(
          backgroundColor: WidgetStatePropertyAll(
            state.enabled ? colors.primary : colors.surfaceContainerHigh,
          ),
          foregroundColor: WidgetStatePropertyAll(
            state.enabled ? colors.onPrimary : colors.onSurfaceVariant,
          ),
        ),
        onPressed: toggle,
        child: Semantics(
          toggled: state.enabled,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.enabled) ...[
                const Icon(
                  Icons.check_rounded,
                  size: PromptFooterStyle.iconSize,
                ),
                const SizedBox(width: 4),
              ],
              Text(context.l10n.generation_transparentBackground),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      richMessage: WidgetSpan(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.qualityTags_addToEnd,
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              TranslatedTagText(
                QualityTags.transparentBackgroundTag,
                style: TextStyle(color: Colors.green.shade700, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      preferBelow: true,
      verticalOffset: 20,
      waitDuration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: button,
    );
  }
}
