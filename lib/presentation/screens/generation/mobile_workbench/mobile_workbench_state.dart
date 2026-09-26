import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/image_generation_provider.dart';

/// 移动端生成工作台的页签，顺序即页签栏从左到右的顺序。
enum MobileWorkbenchTab { image, prompt, params, references, history }

/// 当前页签与“有未查看的新结果”标记。
class MobileWorkbenchState {
  const MobileWorkbenchState({required this.tab, this.hasUnseenResult = false});

  final MobileWorkbenchTab tab;
  final bool hasUnseenResult;
}

/// 页签状态跨越布局断点和旋转保留，只在内存中存在。
class MobileWorkbenchNotifier extends Notifier<MobileWorkbenchState> {
  @override
  MobileWorkbenchState build() {
    final hasResult = ref
        .read(imageGenerationNotifierProvider)
        .displayImages
        .isNotEmpty;
    return MobileWorkbenchState(
      tab: hasResult ? MobileWorkbenchTab.image : MobileWorkbenchTab.prompt,
    );
  }

  void select(MobileWorkbenchTab tab) {
    final unseen = tab == MobileWorkbenchTab.image
        ? false
        : state.hasUnseenResult;
    if (tab == state.tab && unseen == state.hasUnseenResult) return;
    state = MobileWorkbenchState(tab: tab, hasUnseenResult: unseen);
  }

  /// 生成结束时调用：不在图像页时标记新结果，在图像页时无需提醒。
  void markResultArrived() {
    if (state.tab == MobileWorkbenchTab.image || state.hasUnseenResult) return;
    state = MobileWorkbenchState(tab: state.tab, hasUnseenResult: true);
  }
}

final mobileWorkbenchNotifierProvider =
    NotifierProvider<MobileWorkbenchNotifier, MobileWorkbenchState>(
      MobileWorkbenchNotifier.new,
    );
