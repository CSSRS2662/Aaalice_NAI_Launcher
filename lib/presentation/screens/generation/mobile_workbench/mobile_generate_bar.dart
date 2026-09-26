import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/generation/image_generation_selectors.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/anlas/opus_stamina_bar.dart';
import '../../../widgets/common/anlas_cost_badge.dart';
import '../../../widgets/common/themed_button.dart';
import '../mobile_generation_view_data.dart';
import '../widgets/generation_controls/generate_button.dart';
import '../widgets/generation_controls/random_mode_toggle.dart';

/// 生成页底栏：体力条（仅 V5 且有额度数据时）+ 抽卡开关、加入队列与生成按钮。
///
/// 各页签共用同一个生成入口；进度直接填充在生成按钮内部。
class MobileGenerateBar extends StatelessWidget {
  const MobileGenerateBar({
    super.key,
    required this.data,
    required this.onGenerate,
    required this.onCancel,
    required this.onSkipCurrent,
    required this.onAddToQueue,
  });

  final MobileGenerationViewData data;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;
  final VoidCallback onSkipCurrent;
  final VoidCallback onAddToQueue;

  bool get _canSkipCurrentBatch =>
      data.isLauncherGenerating &&
      data.batchStatus.currentImage > 0 &&
      data.batchStatus.totalImages > data.batchStatus.currentImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = MobileGenerateActionButton(
      isGenerating: data.isGenerating,
      showCancel: data.isLauncherGenerating,
      isPreparing: data.batchStatus.isPreparing,
      cooldownRemainingSeconds: data.cooldownRemainingSeconds,
      showCost: !data.isUpscaleMode,
      requiresLogin: data.requiresLogin,
      onGenerate: onGenerate,
      onCancel: onCancel,
    );
    final main = _canSkipCurrentBatch
        ? LayoutBuilder(
            builder: (context, constraints) {
              final progress =
                  '${data.batchStatus.currentImage}/${data.batchStatus.totalImages}';
              final skip = ThemedButton(
                key: const ValueKey('generation-mobile-skip-current'),
                onPressed: onSkipCurrent,
                icon: const Icon(Icons.skip_next),
                label: Text(
                  '${context.l10n.generation_skipCurrentBatch} $progress',
                  textAlign: TextAlign.center,
                ),
                style: ThemedButtonStyle.outlined,
              );
              final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
              if (largeText || constraints.maxWidth < 300) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [skip, const SizedBox(height: 8), primary],
                );
              }
              return Row(
                children: [
                  Expanded(child: skip),
                  const SizedBox(width: 8),
                  Expanded(child: primary),
                ],
              );
            },
          )
        : primary;

    return SafeArea(
      top: false,
      child: ColoredBox(
        key: const ValueKey('generation-mobile-bottom-bar'),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 4),
                child: OpusStaminaBar(),
              ),
              Row(
                key: const ValueKey('generation-mobile-action-row'),
                children: [
                  if (data.showRandomTools)
                    SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: RandomModeToggle(
                          enabled: data.randomModeEnabled,
                          compact: true,
                        ),
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('generation-add-current-to-queue'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(44),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                    ),
                    onPressed: onAddToQueue,
                    icon: const Icon(Icons.playlist_add_rounded),
                    tooltip: context.l10n.queue_addCurrentTask,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: main),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 生成主按钮：空闲时为强调色，生成中转为中性底并在内部填充进度。
class MobileGenerateActionButton extends StatelessWidget {
  const MobileGenerateActionButton({
    super.key,
    required this.isGenerating,
    required this.showCancel,
    required this.isPreparing,
    required this.cooldownRemainingSeconds,
    required this.showCost,
    required this.requiresLogin,
    required this.onGenerate,
    required this.onCancel,
  });

  final bool isGenerating;

  /// 启动器自身的生成可以取消；Krita 占用时只能等待。
  final bool showCancel;

  /// 已提交但尚未开跑，按钮必须立刻给出反馈。
  final bool isPreparing;
  final int cooldownRemainingSeconds;
  final bool showCost;
  final bool requiresLogin;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final appTheme = theme.appTheme;
    final cancelMode = showCancel || isPreparing;
    final waiting = isGenerating && !cancelMode;
    final coolingDown = !cancelMode && cooldownRemainingSeconds > 0;
    final enabled =
        cancelMode || requiresLogin || (!isGenerating && !coolingDown);
    final background = cancelMode || waiting
        ? colors.surfaceContainerHighest
        : colors.primary;
    final foreground = cancelMode || waiting
        ? colors.onSurface
        : colors.onPrimary;
    final radius = BorderRadius.circular(appTheme.controlRadius + 4);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : appTheme.fastDuration;

    final Widget content;
    if (cancelMode) {
      content = _CancelLabel(preparing: isPreparing, color: foreground);
    } else if (waiting) {
      content = IconTheme.merge(
        data: IconThemeData(color: foreground),
        child: const GenerateButtonSpinner(),
      );
    } else {
      content = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            requiresLogin
                ? Icons.login_rounded
                : coolingDown
                ? Icons.hourglass_bottom_outlined
                : Icons.auto_awesome,
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              requiresLogin
                  ? context.l10n.auth_login
                  : coolingDown
                  ? context.l10n.generation_cooldownRemaining(
                      cooldownRemainingSeconds,
                    )
                  : context.l10n.generation_generate,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(color: foreground),
            ),
          ),
          if (showCost && !requiresLogin && !coolingDown)
            const AnlasCostBadge(isGenerating: false),
        ],
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        key: const ValueKey('generation-mobile-generate'),
        duration: duration,
        curve: appTheme.standardCurve,
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: enabled || cancelMode
              ? background
              : background.withValues(alpha: 0.5),
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? (cancelMode ? onCancel : onGenerate) : null,
            borderRadius: radius,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (cancelMode)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: radius,
                      child: _ProgressFill(color: colors.primary),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: foreground),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度填充单独订阅进度字段，避免逐帧重建整个底栏。
class _ProgressFill extends ConsumerWidget {
  const _ProgressFill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      imageGenerationNotifierProvider.select(selectGenerationProgress),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        key: const ValueKey('generation-mobile-progress-fill'),
        widthFactor: progress.clamp(0.0, 1.0),
        heightFactor: 1,
        child: ColoredBox(color: color.withValues(alpha: 0.24)),
      ),
    );
  }
}

class _CancelLabel extends ConsumerWidget {
  const _CancelLabel({required this.preparing, required this.color});

  final bool preparing;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final percent =
        (ref.watch(
                  imageGenerationNotifierProvider.select(
                    selectGenerationProgress,
                  ),
                ) *
                100)
            .clamp(0, 100)
            .round();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (preparing)
          IconTheme.merge(
            data: IconThemeData(color: color),
            child: const GenerateButtonSpinner(),
          )
        else
          Icon(Icons.stop_circle_outlined, size: 20, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            preparing
                ? context.l10n.common_cancel
                : context.l10n.mobileWorkbench_cancelProgress(percent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
