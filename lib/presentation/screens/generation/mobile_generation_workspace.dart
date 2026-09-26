import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/image/image_params.dart';
import '../../providers/image_generation_provider.dart';
import '../../themes/theme_extension.dart';
import '../../widgets/common/keyboard_dismiss_region.dart';
import '../../widgets/common/owned_scroll_controller.dart';
import 'mobile_generation_controller.dart';
import 'mobile_workbench/mobile_workbench_panes.dart';
import 'mobile_workbench/mobile_workbench_state.dart';
import 'mobile_workbench/mobile_workbench_tab_bar.dart';
import 'widgets/history_panel.dart';
import 'widgets/image_preview.dart';
import 'widgets/parameter_panel.dart';
import 'widgets/prompt_input.dart';
import 'widgets/prompt_input_controller.dart';

/// 当前模型下实际生效的参考输入数量，用于参考页签的计数。
int effectiveReferenceCount(ImageParams params) {
  final capabilities = params.capabilities;
  return (params.sourceImage != null ? 1 : 0) +
      (capabilities.supportsVibeTransfer
          ? params.enabledVibeReferencesV4.length
          : 0) +
      (capabilities.supportsPreciseReference
          ? params.enabledPreciseReferences.length
          : 0);
}

/// 移动端生成工作台：页签栏 + 各页签面板。
///
/// 竖屏时图像、提示词、参数、参考、历史共用一个页签栏；宽横屏时图像常驻
/// 左侧，右侧只保留编辑类页签。提示词编辑器始终挂载，保证分区快照、
/// 待导入提示词等副作用不依赖用户是否打开过提示词页。
/// 软键盘弹出时收起页签栏，把高度留给正在编辑的内容。
class MobileGenerationWorkspace extends ConsumerWidget {
  const MobileGenerationWorkspace({
    super.key,
    required this.controller,
    required this.historyViewport,
    required this.promptInputController,
    required this.promptInputKey,
    this.keyboardVisible = false,
  });

  static const double _minimumSplitHeight = 320;

  final MobileGenerationController controller;
  final OwnedViewportOffset historyViewport;
  final PromptInputController promptInputController;
  final GlobalKey promptInputKey;
  final bool keyboardVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workbench = ref.watch(mobileWorkbenchNotifierProvider);
    final referenceCount = ref.watch(
      generationParamsNotifierProvider.select(effectiveReferenceCount),
    );
    return KeyboardDismissRegion(
      child: MobileWorkspaceMotion(
        active: !controller.agentFullScreen,
        hiddenOffset: const Offset(0, -0.08),
        child: TickerMode(
          enabled: !controller.agentFullScreen,
          child: LayoutBuilder(
            key: const ValueKey('generation-workspace'),
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final split =
                  constraints.maxWidth >= 640 * textScale &&
                  constraints.maxHeight >= _minimumSplitHeight &&
                  constraints.maxWidth > constraints.maxHeight * 1.15;
              final selected =
                  split && workbench.tab == MobileWorkbenchTab.image
                  ? MobileWorkbenchTab.prompt
                  : workbench.tab;
              final workbenchColumn = Column(
                children: [
                  if (!keyboardVisible)
                    Padding(
                      key: const ValueKey('mobile-workbench-tab-slot'),
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: MobileWorkbenchTabBar(
                        selected: selected,
                        tabs: split
                            ? MobileWorkbenchTabBar.editingTabs
                            : MobileWorkbenchTab.values,
                        referenceCount: referenceCount,
                        hasUnseenResult: workbench.hasUnseenResult,
                        onSelected: controller.selectTab,
                      ),
                    ),
                  Expanded(
                    key: const ValueKey('mobile-workbench-pane-slot'),
                    child: MobileWorkbenchPanes(
                      selected: selected,
                      eager: const {MobileWorkbenchTab.prompt},
                      builders: {
                        MobileWorkbenchTab.image: (_) => split
                            ? const SizedBox.shrink()
                            : const ImagePreviewWidget(),
                        MobileWorkbenchTab.prompt: (_) => _MobilePromptPane(
                          editor: PromptInputWidget(
                            key: promptInputKey,
                            controller: promptInputController,
                            isMaximized: true,
                            showMaximizeButton: false,
                            active: selected == MobileWorkbenchTab.prompt,
                          ),
                        ),
                        MobileWorkbenchTab.params: (_) => const ParameterPanel(
                          key: ValueKey('generation-mobile-params-pane'),
                          content: ParameterPanelContent.generation,
                        ),
                        MobileWorkbenchTab.references: (_) =>
                            const ParameterPanel(
                              key: ValueKey(
                                'generation-mobile-references-pane',
                              ),
                              content: ParameterPanelContent.references,
                            ),
                        MobileWorkbenchTab.history: (_) => HistoryPanel(
                          key: const ValueKey('generation-mobile-history-pane'),
                          embedded: true,
                          viewportOffset: historyViewport,
                        ),
                      },
                    ),
                  ),
                ],
              );
              if (!split) return workbenchColumn;
              return Row(
                children: [
                  const Expanded(flex: 6, child: ImagePreviewWidget()),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  Expanded(flex: 5, child: workbenchColumn),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 提示词页。宽于 600 时编辑器改用完整工具栏布局，横屏大字号下高度不足，
/// 此时让整页保持最小高度并纵向滚动；窄屏工作台自带更紧凑的兜底。
class _MobilePromptPane extends StatelessWidget {
  const _MobilePromptPane({required this.editor});

  static const double _minimumWideHeight = 340;

  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: editor,
    );
    return LayoutBuilder(
      key: const ValueKey('generation-mobile-prompt-pane'),
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 2.0);
        final minimumHeight = _minimumWideHeight * textScale;
        if (constraints.maxWidth < 600 ||
            constraints.maxHeight >= minimumHeight) {
          return padded;
        }
        return SingleChildScrollView(
          key: const ValueKey('generation-mobile-prompt-scroll'),
          primary: false,
          child: SizedBox(height: minimumHeight, child: padded),
        );
      },
    );
  }
}

class MobileWorkspaceMotion extends StatelessWidget {
  const MobileWorkspaceMotion({
    super.key,
    required this.active,
    required this.hiddenOffset,
    required this.child,
  });

  final bool active;
  final Offset hiddenOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final appTheme = Theme.of(context).appTheme;
    final duration = disableAnimations
        ? Duration.zero
        : appTheme.normalDuration;
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeSemantics(
        excluding: !active,
        child: AnimatedSlide(
          offset: active || disableAnimations ? Offset.zero : hiddenOffset,
          duration: duration,
          curve: appTheme.standardCurve,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: duration,
            curve: appTheme.standardCurve,
            child: child,
          ),
        ),
      ),
    );
  }
}
