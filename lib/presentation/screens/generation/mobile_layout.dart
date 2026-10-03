import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../../data/services/auth_provider.dart';
import '../../providers/generation/image_generation_selectors.dart';
import '../../providers/generation/image_workflow_controller.dart';
import '../../providers/image_generation_provider.dart';
import '../../providers/krita/krita_bridge_notifier.dart';
import '../../widgets/common/owned_scroll_controller.dart';
import 'mobile_generation_controller.dart';
import 'mobile_generation_shell.dart';
import 'mobile_generation_view_data.dart';
import 'mobile_workbench/mobile_workbench_state.dart';
import 'widgets/prompt_input_controller.dart';

/// Stable mobile generation entry point. Stateful interaction and rendering
/// responsibilities live in dedicated controller and component classes.
class MobileGenerationLayout extends ConsumerStatefulWidget {
  const MobileGenerationLayout({
    super.key,
    this.historyViewport,
    this.promptInputController,
    this.promptInputKey,
  });

  final OwnedViewportOffset? historyViewport;
  final PromptInputController? promptInputController;
  final GlobalKey? promptInputKey;

  @override
  ConsumerState<MobileGenerationLayout> createState() =>
      _MobileGenerationLayoutState();
}

class _MobileGenerationLayoutState
    extends ConsumerState<MobileGenerationLayout> {
  late final MobileGenerationController _controller;
  late final OwnedViewportOffset _historyViewport;
  late final PromptInputController _promptInputController;
  late final GlobalKey _promptInputKey;
  late final bool _ownsPromptInputController;

  @override
  void initState() {
    super.initState();
    _controller = MobileGenerationController(ref);
    _historyViewport = widget.historyViewport ?? OwnedViewportOffset();
    _ownsPromptInputController = widget.promptInputController == null;
    _promptInputKey =
        widget.promptInputKey ??
        GlobalKey(debugLabel: 'mobile-generation-prompt');
    final params = ref.read(generationParamsNotifierProvider);
    _promptInputController =
        widget.promptInputController ??
        PromptInputController(
          prompt: params.prompt,
          negativePrompt: params.negativePrompt,
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsPromptInputController) _promptInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 一次生成结束时，若用户已离开图像页，给图像页签打上新结果标记。
    ref.listen(
      imageGenerationNotifierProvider.select((state) => state.isGenerating),
      (previous, next) {
        if (previous == true && !next) {
          ref
              .read(mobileWorkbenchNotifierProvider.notifier)
              .markResultArrived();
        }
      },
    );
    final batchStatus = ref.watch(
      imageGenerationNotifierProvider.select(selectGenerationButtonViewData),
    );
    final cooldownState = ref.watch(generationCooldownProvider);
    final isAuthenticated = ref.watch(
      authNotifierProvider.select((state) => state.isAuthenticated),
    );
    final supportsKrita = PlatformCapabilities.current.supportsKritaBridge;
    final isKritaGenerating = supportsKrita
        ? ref.watch(kritaBridgeNotifierProvider).isBridgeGenerating
        : false;
    final showRandomTools = ref.watch(randomPromptToolsVisibilityProvider);
    final isUpscaleMode = ref.watch(
      imageWorkflowControllerProvider.select((workflow) => workflow.isUpscale),
    );
    final randomModeEnabled = ref.watch(randomPromptModeProvider);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // The controller reports only show/hide changes, not every frame of
        // the keyboard animation.
        final keyboardVisible = _controller.keyboardVisible;
        final isLauncherGenerating = batchStatus.isGenerating;
        final isGenerating = isLauncherGenerating || isKritaGenerating;
        final data = MobileGenerationViewData(
          batchStatus: batchStatus,
          cooldownRemainingSeconds: cooldownState.remainingSeconds,
          keyboardVisible: keyboardVisible,
          isGenerating: isGenerating,
          isLauncherGenerating: isLauncherGenerating,
          requiresLogin: !isAuthenticated && !isGenerating,
          showRandomTools: showRandomTools,
          isUpscaleMode: isUpscaleMode,
          randomModeEnabled: randomModeEnabled,
        );
        return MobileGenerationShell(
          controller: _controller,
          data: data,
          historyViewport: _historyViewport,
          promptInputController: _promptInputController,
          promptInputKey: _promptInputKey,
        );
      },
    );
  }
}
