import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/queue/replication_task.dart';
import '../../../data/models/queue/replication_task_generation_snapshot.dart';
import '../../../data/services/auth_provider.dart';
import '../../providers/generation/image_workflow_controller.dart';
import '../../providers/image_generation_provider.dart';
import '../../providers/krita/krita_bridge_notifier.dart';
import '../../providers/mobile_shell_overlay_provider.dart';
import '../../providers/replication_queue_provider.dart';
import '../../utils/asset_protection_guard.dart';
import '../../widgets/common/app_toast.dart';
import 'mobile_workbench/mobile_workbench_state.dart';

class MobileGenerationController extends ChangeNotifier
    with WidgetsBindingObserver {
  MobileGenerationController(this.ref)
    : shellOverlayNotifier = ref.read(
        mobileShellOverlayNotifierProvider.notifier,
      ) {
    WidgetsBinding.instance.addObserver(this);
  }

  final WidgetRef ref;
  final MobileShellOverlayNotifier shellOverlayNotifier;
  final FocusScopeNode agentFocusScope = FocusScopeNode(
    debugLabel: 'Mobile agent chat',
  );

  bool agentFullScreen = false;
  bool agentHasOpened = false;
  bool keyboardVisible = false;
  bool _disposed = false;

  @override
  void didChangeMetrics() {
    if (!_disposed) notifyListeners();
  }

  void updateKeyboardVisibility(bool visible) {
    keyboardVisible = visible;
  }

  void selectTab(MobileWorkbenchTab tab) {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(mobileWorkbenchNotifierProvider.notifier).select(tab);
  }

  void openAgentChat() {
    FocusManager.instance.primaryFocus?.unfocus();
    shellOverlayNotifier.setActive(MobileShellOverlay.agentChat, true);
    agentHasOpened = true;
    agentFullScreen = true;
    notifyListeners();
  }

  void closeAgentChat() {
    FocusManager.instance.primaryFocus?.unfocus();
    shellOverlayNotifier.setActive(MobileShellOverlay.agentChat, false);
    agentFullScreen = false;
    notifyListeners();
  }

  void handleBack() {
    if (agentFullScreen) handleAgentBack();
  }

  void handleAgentBack() {
    if (agentFocusScope.hasFocus && !agentFocusScope.hasPrimaryFocus) {
      agentFocusScope.unfocus();
      return;
    }
    closeAgentChat();
  }

  void openAgentSettings(BuildContext context) {
    closeAgentChat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !context.mounted) return;
      context.goNamed('settings', queryParameters: const {'section': 'agent'});
    });
  }

  /// 各页签共用的生成入口；开始生成后切到图像页直接呈现流式预览。
  Future<void> generate(BuildContext context) async {
    if (!ref.read(authNotifierProvider).isAuthenticated) {
      await context.pushNamed('login');
      return;
    }

    final params = ref.read(generationParamsNotifierProvider);
    if (PlatformCapabilities.current.supportsKritaBridge &&
        ref.read(kritaBridgeNotifierProvider).isBridgeGenerating) {
      AppToast.warning(context, context.l10n.toast_kritaBusy);
      return;
    }
    if (params.prompt.isEmpty) {
      AppToast.info(context, context.l10n.generation_pleaseInputPrompt);
      selectTab(MobileWorkbenchTab.prompt);
      return;
    }
    final confirmed = await AssetProtectionGuard.confirmHighAnlasCost(
      context: context,
      ref: ref,
    );
    if (!confirmed || _disposed || !context.mounted) return;
    selectTab(MobileWorkbenchTab.image);
    ref.read(imageGenerationNotifierProvider.notifier).generate(params);
  }

  void cancelGeneration() =>
      ref.read(imageGenerationNotifierProvider.notifier).cancel();

  void skipCurrentRequest() =>
      ref.read(imageGenerationNotifierProvider.notifier).skipCurrentRequest();

  Future<void> addCurrentPromptToQueue(BuildContext context) async {
    final params = ref.read(generationParamsNotifierProvider);
    if (params.prompt.isEmpty) {
      AppToast.info(context, context.l10n.generation_pleaseInputPrompt);
      return;
    }
    final queuedParams = params.copyWith(nSamples: 1);
    // 与立即生成时读取的聚焦状态一致，任务执行时不再借用生成页届时的状态
    final workflow = ref.read(imageWorkflowControllerProvider);
    final focused = QueuedFocusedInpaint(
      enabled: workflow.focusedInpaintEnabled,
      contextPadding: workflow.minimumContextMegaPixels,
      selectionRect: workflow.focusedSelectionRect,
      contextCrop: workflow.focusedContextCrop,
    );
    final task = ReplicationTask.create(
      prompt: params.prompt,
      negativePrompt: params.negativePrompt,
      applyNegativePrompt: true,
      characterPrompts: params.characters
          .map(
            (character) => ReplicationCharacterPromptSnapshot(
              prompt: character.prompt,
              negativePrompt: character.negativePrompt,
              positionX: params.useCoords ? character.positionX : null,
              positionY: params.useCoords ? character.positionY : null,
            ),
          )
          .toList(growable: false),
      generationSnapshot: ReplicationTaskGenerationSnapshot.encode(
        queuedParams,
        batchSize: ref.read(imagesPerRequestProvider),
        focused: focused,
      ),
      source: ReplicationTaskSource.local,
      seed: params.seed,
      sampler: params.sampler,
      steps: params.steps,
      cfgScale: params.scale,
      model: params.model,
      width: params.width,
      height: params.height,
    );
    final added = await ref
        .read(replicationQueueNotifierProvider.notifier)
        .add(task);
    if (_disposed || !context.mounted) return;
    if (!added) {
      AppToast.warning(context, context.l10n.onlineGallery_queueFullMax);
      return;
    }
    AppToast.success(context, context.l10n.queue_taskAdded);
  }

  @override
  void dispose() {
    agentFocusScope.dispose();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    shellOverlayNotifier.clearGenerationOverlays();
    super.dispose();
  }
}
