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
import '../../../widgets/common/model_family_icon.dart';

/// 生成页顶栏：左侧为当前模型（点按展开模型菜单直接切换），右侧为余额、
/// 智能体与队列。移动端只在这里切换模型，参数页不再重复提供。
class MobileGenerationHeader extends ConsumerWidget
    implements PreferredSizeWidget {
  const MobileGenerationHeader({super.key, required this.onOpenAgent});

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
    final queueCount = ref.watch(
      replicationQueueNotifierProvider.select((state) => state.count),
    );
    return AppBar(
      key: const ValueKey('generation-mobile-header'),
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: const Align(
        alignment: AlignmentDirectional.centerStart,
        child: MobileModelMenu(),
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

/// 模型下拉菜单：列出全部可见模型，当前模型带勾选标记。
class MobileModelMenu extends ConsumerWidget {
  const MobileModelMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(
      generationParamsNotifierProvider.select((params) => params.model),
    );
    // 测试期的 custom 键归一到正式 ID，保证当前模型一定在候选项里。
    final current = ImageModels.migrateLegacyModel(model);
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final id in ImageModels.visibleModels(current: current))
          MenuItemButton(
            key: ValueKey('generation-mobile-model-$id'),
            style: MenuItemButton.styleFrom(
              minimumSize: const Size(220, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            leadingIcon: ModelFamilyIcon(
              modelId: id,
              displayName: ImageModels.modelDisplayNames[id],
              size: 20,
              color: id == current ? colors.primary : colors.onSurfaceVariant,
            ),
            trailingIcon: id == current
                ? Icon(Icons.check_rounded, size: 20, color: colors.primary)
                : const SizedBox(width: 20),
            onPressed: () => ref
                .read(generationParamsNotifierProvider.notifier)
                .updateModel(id),
            child: Text(
              MobileGenerationHeader.shortModelLabel(id),
              style: TextStyle(
                fontWeight: id == current ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => _ModelPill(
        label: MobileGenerationHeader.shortModelLabel(model),
        open: controller.isOpen,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _ModelPill extends StatelessWidget {
  const _ModelPill({
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(theme.appTheme.controlRadius + 2);
    return Semantics(
      button: true,
      expanded: open,
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
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : theme.appTheme.fastDuration,
                    curve: theme.appTheme.standardCurve,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
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
