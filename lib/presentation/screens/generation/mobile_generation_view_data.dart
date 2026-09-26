import '../../providers/generation/image_generation_selectors.dart';

class MobileGenerationViewData {
  const MobileGenerationViewData({
    required this.batchStatus,
    required this.cooldownRemainingSeconds,
    required this.keyboardVisible,
    required this.isGenerating,
    required this.isLauncherGenerating,
    required this.requiresLogin,
    required this.showRandomTools,
    required this.isUpscaleMode,
    required this.randomModeEnabled,
  });

  final GenerationButtonViewData batchStatus;
  final int cooldownRemainingSeconds;
  final bool keyboardVisible;
  final bool isGenerating;
  final bool isLauncherGenerating;
  final bool requiresLogin;
  final bool showRandomTools;
  final bool isUpscaleMode;
  final bool randomModeEnabled;
}
