import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../themes/theme_extension.dart';
import 'mobile_workbench_state.dart';
import 'mobile_workbench_tab_bar.dart';

/// 移动端生成工作台：页签栏与可横滑切换的页签面板。
///
/// 面板首次进入（点按或横滑露出）时才构建，之后常驻以保留输入、滚动与
/// 选择状态；[eager] 中的面板从一开始就构建。横滑时相邻面板跟手移动，
/// 页签栏选中底同步连续移动；点按页签时新旧两个面板直接滑动衔接，不经过
/// 中间页签。Reduce Motion 下松手或点按都直接到终态。
class MobileWorkbenchView extends StatefulWidget {
  const MobileWorkbenchView({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.builders,
    this.eager = const {},
    this.showTabBar = true,
    this.swipeEnabled = true,
    this.referenceCount = 0,
    this.hasUnseenResult = false,
    this.tabBarPadding = const EdgeInsets.fromLTRB(12, 2, 12, 8),
  });

  final List<MobileWorkbenchTab> tabs;
  final MobileWorkbenchTab selected;
  final ValueChanged<MobileWorkbenchTab> onSelected;
  final Map<MobileWorkbenchTab, WidgetBuilder> builders;
  final Set<MobileWorkbenchTab> eager;
  final bool showTabBar;

  /// 软键盘弹出时关闭横滑，避免编辑中误切页签。
  final bool swipeEnabled;
  final int referenceCount;
  final bool hasUnseenResult;
  final EdgeInsetsGeometry tabBarPadding;

  @override
  State<MobileWorkbenchView> createState() => _MobileWorkbenchViewState();
}

/// 某一时刻的面板位置：停在 [index]，或正从 [from] 过渡到 [to]。
@immutable
class _PagerFrame {
  const _PagerFrame.settled(this.index)
    : from = null,
      to = null,
      progress = 0,
      overscroll = 0;

  const _PagerFrame.moving({
    required this.index,
    required int this.from,
    required int this.to,
    required this.progress,
  }) : overscroll = 0;

  const _PagerFrame.overscrolled(this.index, this.overscroll)
    : from = null,
      to = null,
      progress = 0;

  final int index;
  final int? from;
  final int? to;

  /// 0 表示停在 [from]，1 表示到达 [to]。
  final double progress;

  /// 首尾页继续拖动时的阻尼位移，单位为面板宽度。
  final double overscroll;

  bool get isMoving => from != null && to != null;

  double get position =>
      isMoving ? from! + (to! - from!) * progress : index.toDouble();

  /// 面板相对自身宽度的水平位移；不可见时为 null。
  double? offsetOf(int page) {
    if (isMoving) {
      final direction = (to! - from!).sign.toDouble();
      if (page == from) return -direction * progress;
      if (page == to) return direction * (1 - progress);
      return null;
    }
    return page == index ? -overscroll : null;
  }
}

class _MobileWorkbenchViewState extends State<MobileWorkbenchView>
    with SingleTickerProviderStateMixin {
  final Set<MobileWorkbenchTab> _built = {};
  late final ValueNotifier<_PagerFrame> _frame;
  late final ValueNotifier<double> _position;
  late final AnimationController _settle;
  double _width = 1;
  double _drag = 0;
  bool _settleCommits = false;

  int get _index => _frame.value.index;

  @override
  void initState() {
    super.initState();
    final index = _indexOf(widget.selected);
    _built
      ..addAll(widget.eager)
      ..add(widget.tabs[index]);
    _frame = ValueNotifier(_PagerFrame.settled(index));
    _position = ValueNotifier(index.toDouble());
    _frame.addListener(() => _position.value = _frame.value.position);
    _settle = AnimationController(vsync: this)
      ..addListener(_onSettleTick)
      ..addStatusListener(_onSettleStatus);
  }

  @override
  void didUpdateWidget(covariant MobileWorkbenchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built.addAll(widget.eager);
    if (!listEquals(oldWidget.tabs, widget.tabs)) {
      _settle.stop();
      _drag = 0;
      final index = _indexOf(widget.selected);
      _built.add(widget.tabs[index]);
      _frame.value = _PagerFrame.settled(index);
      return;
    }
    if (!widget.swipeEnabled && !_settle.isAnimating && _drag != 0) {
      // 拖动中途停用横滑（例如软键盘弹出）：识别器被移除，不会再收到结束
      // 事件，直接回到当前页。
      _drag = 0;
      _frame.value = _PagerFrame.settled(_index);
    }
    final target = _indexOf(widget.selected);
    final frame = _frame.value;
    final heading = frame.isMoving && _settle.isAnimating && _settleCommits
        ? frame.to!
        : frame.index;
    if (target == heading) return;
    _built.add(widget.tabs[target]);
    _jumpTo(target);
  }

  @override
  void dispose() {
    _settle.dispose();
    _frame.dispose();
    _position.dispose();
    super.dispose();
  }

  int _indexOf(MobileWorkbenchTab tab) {
    final index = widget.tabs.indexOf(tab);
    return index < 0 ? 0 : index;
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  Duration get _normalDuration => Theme.of(context).appTheme.normalDuration;

  /// 外部选择（点按页签、生成跳转等）：新旧两页直接滑动衔接。
  void _jumpTo(int target) {
    _settle.stop();
    _drag = 0;
    final from = _index;
    if (_reduceMotion || from == target) {
      _frame.value = _PagerFrame.settled(target);
      return;
    }
    _frame.value = _PagerFrame.moving(
      index: from,
      from: from,
      to: target,
      progress: 0,
    );
    _animateSettle(commit: true, distance: 1);
  }

  /// 从当前进度（或首尾阻尼位移）动画到终点；时长按剩余距离缩短。
  void _animateSettle({required bool commit, required double distance}) {
    _settleCommits = commit;
    final frame = _frame.value;
    _settleBegin = frame.isMoving ? frame.progress : frame.overscroll;
    if (_reduceMotion) {
      _finishSettle();
      return;
    }
    final full = _normalDuration.inMilliseconds;
    final millis = (full * distance.clamp(0.0, 1.0)).round().clamp(80, full);
    _settle.duration = Duration(milliseconds: millis);
    _settle.forward(from: 0);
  }

  double _settleBegin = 0;

  void _onSettleTick() {
    final frame = _frame.value;
    final t = Theme.of(context).appTheme.enterCurve.transform(_settle.value);
    if (frame.isMoving) {
      final end = _settleCommits ? 1.0 : 0.0;
      _frame.value = _PagerFrame.moving(
        index: frame.index,
        from: frame.from!,
        to: frame.to!,
        progress: _settleBegin + (end - _settleBegin) * t,
      );
    } else {
      _frame.value = _PagerFrame.overscrolled(
        frame.index,
        _settleBegin * (1 - t),
      );
    }
  }

  void _onSettleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishSettle();
  }

  void _finishSettle() {
    final frame = _frame.value;
    final landed = frame.isMoving && _settleCommits ? frame.to! : frame.index;
    _frame.value = _PagerFrame.settled(landed);
    if (landed != _indexOf(widget.selected)) {
      widget.onSelected(widget.tabs[landed]);
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (_settle.isAnimating) {
      _settle.stop();
      _finishSettle();
    }
    _drag = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _drag -= details.primaryDelta ?? 0;
    final fraction = _drag / _width;
    final index = _index;
    final neighbor = index + fraction.sign.toInt();
    if (fraction == 0 || neighbor < 0 || neighbor >= widget.tabs.length) {
      _frame.value = _PagerFrame.overscrolled(
        index,
        (fraction * 0.2).clamp(-0.08, 0.08),
      );
      return;
    }
    final tab = widget.tabs[neighbor];
    if (_built.add(tab)) setState(() {});
    _frame.value = _PagerFrame.moving(
      index: index,
      from: index,
      to: neighbor,
      progress: fraction.abs().clamp(0.0, 1.0),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final frame = _frame.value;
    _drag = 0;
    if (!frame.isMoving) {
      _animateSettle(commit: false, distance: frame.overscroll.abs() * 4);
      return;
    }
    final direction = (frame.to! - frame.from!).sign;
    final fling = -(details.primaryVelocity ?? 0) / _width;
    final flingTowards = fling.abs() > 1.0 && fling.sign == direction;
    final flingBack = fling.abs() > 1.0 && fling.sign == -direction;
    final commit = flingTowards || (frame.progress > 0.5 && !flingBack);
    _animateSettle(
      commit: commit,
      distance: commit ? 1 - frame.progress : frame.progress,
    );
  }

  void _onDragCancel() {
    final frame = _frame.value;
    _drag = 0;
    _animateSettle(
      commit: false,
      distance: frame.isMoving ? frame.progress : frame.overscroll.abs() * 4,
    );
  }

  @override
  Widget build(BuildContext context) {
    final panes = [
      for (final tab in MobileWorkbenchTab.values)
        if (_built.contains(tab))
          _PaneSlot(
            key: ValueKey('mobile-workbench-pane-${tab.name}'),
            frame: _frame,
            page: widget.tabs.indexOf(tab),
            child: widget.builders[tab]!(context),
          ),
    ];
    // 横滑开关只改变识别器集合，不增删外层节点：软键盘弹出时停用横滑，
    // 如果因此改动树结构，面板会被重新挂载，编辑中的焦点随之丢失。
    final swipe = widget.swipeEnabled && widget.tabs.length > 1;
    final pager = RawGestureDetector(
      key: const ValueKey('mobile-workbench-swipe-region'),
      gestures: {
        if (swipe)
          _WorkbenchSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<_WorkbenchSwipeRecognizer>(
                () => _WorkbenchSwipeRecognizer(debugOwner: this),
                (recognizer) => recognizer
                  ..onStart = _onDragStart
                  ..onUpdate = _onDragUpdate
                  ..onEnd = _onDragEnd
                  ..onCancel = _onDragCancel,
              ),
      },
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
            return Stack(fit: StackFit.expand, children: panes);
          },
        ),
      ),
    );
    return Column(
      children: [
        if (widget.showTabBar)
          Padding(
            key: const ValueKey('mobile-workbench-tab-slot'),
            padding: widget.tabBarPadding,
            child: MobileWorkbenchTabBar(
              selected: widget.selected,
              tabs: widget.tabs,
              position: _position,
              referenceCount: widget.referenceCount,
              hasUnseenResult: widget.hasUnseenResult,
              onSelected: widget.onSelected,
            ),
          ),
        Expanded(
          key: const ValueKey('mobile-workbench-pane-slot'),
          child: pager,
        ),
      ],
    );
  }
}

/// 单个面板的位置、可见性与交互；子树实例在横滑过程中保持不变。
class _PaneSlot extends StatelessWidget {
  const _PaneSlot({
    super.key,
    required this.frame,
    required this.page,
    required this.child,
  });

  final ValueListenable<_PagerFrame> frame;

  /// 在当前页签列表中的下标；不在列表中（例如宽横屏下的图像页）为 -1。
  final int page;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_PagerFrame>(
      valueListenable: frame,
      child: child,
      builder: (context, frame, child) {
        final offset = page < 0 ? null : frame.offsetOf(page);
        final visible = offset != null;
        final settled = visible && !frame.isMoving && page == frame.index;
        return Offstage(
          offstage: !visible,
          child: TickerMode(
            enabled: visible,
            child: IgnorePointer(
              ignoring: !settled,
              child: ExcludeSemantics(
                excluding: !settled,
                child: FractionalTranslation(
                  translation: Offset(offset ?? 0, 0),
                  // 横滑时只移动已绘制的图层，面板内容不逐帧重绘。
                  child: RepaintBoundary(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 页签横滑识别。
///
/// Android 上文本框的拖动选择识别器在横向越过 touch slop 时立即胜出，手指
/// 落在未聚焦的提示词上便无法横滑。按下点落在文本编辑区时，改用一半的横向
/// 阈值并要求明显的水平方向，让页签切换先于文本拖动胜出；其他位置沿用默认
/// 阈值，滑块、横向列表、拖动排序等内部控件仍然优先。
class _WorkbenchSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _WorkbenchSwipeRecognizer({super.debugOwner});

  bool _startedOnText = false;
  Offset _origin = Offset.zero;
  Offset _latest = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _startedOnText = _hitsEditableText(event);
    _origin = event.position;
    _latest = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _latest = event.position;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (!_startedOnText) {
      return super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
    }
    final delta = _latest - _origin;
    final slop = computeHitSlop(pointerDeviceKind, gestureSettings) / 2;
    return delta.dx.abs() > slop && delta.dx.abs() > delta.dy.abs() * 2;
  }

  static bool _hitsEditableText(PointerDownEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    return result.path.any((entry) => entry.target is RenderEditable);
  }
}
