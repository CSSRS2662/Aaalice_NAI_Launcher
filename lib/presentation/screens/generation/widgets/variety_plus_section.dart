import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/image/image_params.dart';
import '../../../providers/image_generation_provider.dart';
import 'generation_param_sections.dart';

/// Variety+ 单独成节：标题与开关一行，下方简述作用。模型不支持时不显示。
class VarietyPlusSection extends ConsumerWidget {
  const VarietyPlusSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => (
          supported: params.capabilities.supportsVarietyPlus,
          enabled: params.varietyPlus,
        ),
      ),
    );
    if (!data.supported) return const SizedBox.shrink();
    final theme = Theme.of(context);
    void toggle(bool value) => ref
        .read(generationParamsNotifierProvider.notifier)
        .updateVarietyPlus(value);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: MergeSemantics(
        child: InkWell(
          key: const ValueKey('generation-variety-plus'),
          onTap: () => toggle(!data.enabled),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ParamSectionTitle('Variety+'),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.generation_varietyPlusDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                key: const ValueKey('generation-variety-plus-switch'),
                value: data.enabled,
                onChanged: toggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
