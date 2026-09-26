import 'package:flutter/material.dart';

import '../../widgets/common/themed_scaffold.dart';
import 'mobile_generation_controller.dart';
import 'mobile_generation_view_data.dart';
import 'mobile_workbench/mobile_generate_bar.dart';
import 'mobile_workbench/mobile_generation_header.dart';
import 'mobile_workbench/mobile_workbench_state.dart';

/// 生成页外框：顶栏、工作台与全局生成底栏。
///
/// 智能体全屏时隐藏顶栏与底栏；软键盘弹出时隐藏底栏，保护编辑区域。
class MobileGenerationChrome extends StatelessWidget {
  const MobileGenerationChrome({
    super.key,
    required this.controller,
    required this.data,
    required this.body,
  });

  final MobileGenerationController controller;
  final MobileGenerationViewData data;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      appBar: controller.agentFullScreen
          ? null
          : MobileGenerationHeader(
              onSelectModel: () =>
                  controller.selectTab(MobileWorkbenchTab.params),
              onOpenAgent: controller.openAgentChat,
            ),
      body: body,
      bottomNavigationBar: data.keyboardVisible || controller.agentFullScreen
          ? null
          : MobileGenerateBar(
              data: data,
              onGenerate: () => controller.generate(context),
              onCancel: controller.cancelGeneration,
              onSkipCurrent: controller.skipCurrentRequest,
              onAddToQueue: () => controller.addCurrentPromptToQueue(context),
            ),
    );
  }
}
