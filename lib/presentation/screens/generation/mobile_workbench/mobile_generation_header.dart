import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../agent_chat/widgets/agent_chat_entry_button.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../providers/replication_queue_provider.dart';
import '../../../router/shell_panels_overlay.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/anlas/anlas_balance_chip.dart';

/// 生成页顶栏：左侧为当前模型（点按前往参数页），右侧为余额、智能体与队列。
class MobileGenerationHeader extends ConsumerWidget
    implements PreferredSizeWidget {
  const MobileGenerationHeader({
    super.key,
    required this.onSelectModel,
    required this.onOpenAgent,
  });

  final VoidCallback onSelectModel;
  final VoidCallback onOpenAgent;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// “NAI Diffusion V5 (Full)” → “V5 Full”，保留非官方前缀的模型全名。
  static String shortModelLabel(String model) =>
      (ImageModels.modelDisplayNames[model] ?? model)
          .replaceFirst('NAI Diffusion ', '')
          .replaceAll(RegExp(r'[()]'), '')
          .trim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(
      generationParamsNotifierProvider.select((params) => params.model),
    );
    final queueCount = ref.watch(
      replicationQueueNotifierProvider.select((state) => state.count),
    );
    return AppBar(
      key: const ValueKey('generation-mobile-header'),
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: Align(
        alignment: AlignmentDirectional.centerStart,
        child: _ModelPill(
          label: shortModelLabel(model),
          onPressed: onSelectModel,
        ),
      ),
      actions: [
        const AnlasBalanceChip(compact: true),
        const SizedBox(width: 2),
        AgentChatEntryButton(onPressed: onOpenAgent),
        IconButton(
          key: const ValueKey('generation-mobile-queue-action'),
          tooltip: context.l10n.mobileWorkbench_queue,
          onPressed: () =>
              ref.read(shellPanelProvider.notifier).state = ShellPanel.queue,
          icon: Badge(
            isLabelVisible: queueCount > 0,
            label: Text(queueCount > 99 ? '99+' : '$queueCount'),
            child: const Icon(Icons.format_list_bulleted_rounded),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _ModelPill extends StatelessWidget {
  const _ModelPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(theme.appTheme.controlRadius + 2);
    return Semantics(
      button: true,
      label: context.l10n.mobileWorkbench_selectModel(label),
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: controlSurfaceColor(colors),
        borderRadius: radius,
        child: InkWell(
          key: const ValueKey('generation-mobile-model-action'),
          onTap: onPressed,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
