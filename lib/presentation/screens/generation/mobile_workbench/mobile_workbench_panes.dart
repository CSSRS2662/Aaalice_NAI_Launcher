import 'package:flutter/material.dart';

import '../../../themes/theme_extension.dart';
import 'mobile_workbench_state.dart';

/// 按页签承载工作台各面板。
///
/// 面板首次进入时才构建，之后常驻以保留输入、滚动与选择状态；[eager] 中的
/// 面板从一开始就构建（提示词编辑器需要首帧即发布分区快照等副作用）。
/// 切换时只对新面板做一次单向淡入位移，Reduce Motion 下直接到终态。
class MobileWorkbenchPanes extends StatefulWidget {
  const MobileWorkbenchPanes({
    super.key,
    required this.selected,
    required this.builders,
    this.eager = const {},
  });

  final MobileWorkbenchTab selected;
  final Map<MobileWorkbenchTab, WidgetBuilder> builders;
  final Set<MobileWorkbenchTab> eager;

  @override
  State<MobileWorkbenchPanes> createState() => _MobileWorkbenchPanesState();
}

class _MobileWorkbenchPanesState extends State<MobileWorkbenchPanes>
    with SingleTickerProviderStateMixin {
  final Set<MobileWorkbenchTab> _built = {};
  late final AnimationController _entrance;
  double _direction = 0;

  @override
  void initState() {
    super.initState();
    _built
      ..addAll(widget.eager)
      ..add(widget.selected);
    _entrance = AnimationController(vsync: this, value: 1);
  }

  @override
  void didUpdateWidget(covariant MobileWorkbenchPanes oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built.addAll(widget.eager);
    if (oldWidget.selected == widget.selected) return;
    _built.add(widget.selected);
    _direction = widget.selected.index > oldWidget.selected.index ? 1 : -1;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      return;
    }
    _entrance
      ..duration = Theme.of(context).appTheme.normalDuration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = Theme.of(context).appTheme.enterCurve;
    final stack = IndexedStack(
      index: widget.selected.index,
      sizing: StackFit.expand,
      children: [
        for (final tab in MobileWorkbenchTab.values)
          KeyedSubtree(
            key: ValueKey('mobile-workbench-pane-${tab.name}'),
            child: _built.contains(tab)
                ? TickerMode(
                    enabled: tab == widget.selected,
                    child: widget.builders[tab]!(context),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
    return AnimatedBuilder(
      animation: _entrance,
      child: stack,
      builder: (context, child) {
        final t = curve.transform(_entrance.value);
        return Opacity(
          opacity: 0.35 + 0.65 * t,
          child: FractionalTranslation(
            translation: Offset(_direction * 0.03 * (1 - t), 0),
            child: child,
          ),
        );
      },
    );
  }
}
