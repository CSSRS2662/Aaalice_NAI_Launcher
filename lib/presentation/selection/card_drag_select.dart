import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'card_selection_scope.dart';

/// Marks a card as a target for the [CardDragSelect] above it.
class CardDragSelectTarget extends StatelessWidget {
  const CardDragSelectTarget({
    super.key,
    required this.id,
    required this.child,
  });

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => MetaData(
    metaData: _TargetData(id, context),
    behavior: HitTestBehavior.translucent,
    child: child,
  );
}

class _TargetData {
  const _TargetData(this.id, this.context);

  final String id;
  final BuildContext context;
}

/// Long-press a card and, without lifting, drag across others to select every
/// card between the two, as in phone photo apps; dragging back releases cards
/// the drag added. The card's own long-press enters selection mode; this only
/// extends the selection while the finger moves, and scrolls when the finger
/// nears the top or bottom edge. Touch only — a mouse has Shift+click.
///
/// Place it below a [CardSelectionScope] and wrap each card in a
/// [CardDragSelectTarget] whose id is in the scope's ordered ids.
class CardDragSelect extends StatefulWidget {
  const CardDragSelect({super.key, required this.child});

  final Widget child;

  @override
  State<CardDragSelect> createState() => _CardDragSelectState();
}

class _CardDragSelectState extends State<CardDragSelect>
    with SingleTickerProviderStateMixin {
  static const double _edgeExtent = 72;
  static const double _maxScrollSpeed = 1200;

  int? _pointer;
  Offset _downPosition = Offset.zero;
  Duration _downTime = Duration.zero;
  Offset? _lastPosition;
  Timer? _armTimer;
  _DragSession? _session;
  late final Ticker _scrollTicker = createTicker(_onScrollTick);
  Duration _lastTick = Duration.zero;
  double _scrollSpeed = 0;

  @override
  void dispose() {
    _armTimer?.cancel();
    _scrollTicker.dispose();
    super.dispose();
  }

  CardSelectionScope? get _scope =>
      context.getInheritedWidgetOfExactType<CardSelectionScope>();

  void _onDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.stylus) {
      return;
    }
    if (_pointer != null) {
      // A second finger means pinch or scroll, never drag-select.
      _reset();
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _downTime = event.timeStamp;
    _lastPosition = event.position;
    // Just after the card's own long-press has entered selection mode.
    _armTimer = Timer(
      kLongPressTimeout + const Duration(milliseconds: 60),
      _arm,
    );
  }

  void _arm() {
    if (!mounted || _pointer == null) return;
    final scope = _scope;
    final target = _targetAt(_downPosition);
    // The commands hold the live state; the scope widget may not have
    // rebuilt since the card's long-press entered selection mode.
    if (scope == null || target == null || !scope.commands.state.isActive) {
      return;
    }
    final anchor = scope.orderedIds.indexOf(target.id);
    if (anchor < 0) return;
    scope.commands.select(target.id);
    final scrollable = Scrollable.maybeOf(target.context);
    _session = _DragSession(
      anchor: anchor,
      initial: {...scope.commands.state.selectedIds},
      scrollable: scrollable?.position.axis == Axis.vertical
          ? scrollable
          : null,
    );
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _lastPosition = event.position;
    final session = _session;
    if (session == null) {
      // Moving away before the long-press fires is a scroll.
      final beforeLongPress = event.timeStamp - _downTime < kLongPressTimeout;
      if (beforeLongPress &&
          (event.position - _downPosition).distance > kTouchSlop) {
        _reset();
      }
      return;
    }
    _extendTo(event.position);
    _updateAutoScroll(session, event.position);
  }

  void _onUp(PointerEvent event) {
    if (event.pointer == _pointer) _reset();
  }

  void _reset() {
    _armTimer?.cancel();
    _armTimer = null;
    _pointer = null;
    _session = null;
    _scrollSpeed = 0;
    if (_scrollTicker.isActive) _scrollTicker.stop();
  }

  void _extendTo(Offset globalPosition) {
    final session = _session;
    final scope = _scope;
    if (session == null || scope == null) return;
    final target = _targetAt(globalPosition);
    if (target == null) return;
    final index = scope.orderedIds.indexOf(target.id);
    if (index < 0 || index == session.current) return;
    session.current = index;
    final start = math.min(session.anchor, index);
    final end = math.max(session.anchor, index);
    final change = session.moveTo(
      scope.orderedIds.sublist(start, end + 1).toSet(),
    );
    if (change.select.isNotEmpty) scope.commands.selectAll(change.select);
    if (change.deselect.isNotEmpty) scope.commands.deselectAll(change.deselect);
    unawaited(HapticFeedback.selectionClick());
  }

  void _updateAutoScroll(_DragSession session, Offset globalPosition) {
    final box =
        session.scrollable?.context.findRenderObject() as RenderBox? ??
        context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || session.scrollable == null) return;
    final local = box.globalToLocal(globalPosition);
    final height = box.size.height;
    double depth = 0;
    if (local.dy < _edgeExtent) {
      depth = -(_edgeExtent - local.dy) / _edgeExtent;
    } else if (local.dy > height - _edgeExtent) {
      depth = (local.dy - (height - _edgeExtent)) / _edgeExtent;
    }
    _scrollSpeed = depth.clamp(-1.0, 1.0) * _maxScrollSpeed;
    if (_scrollSpeed != 0 && !_scrollTicker.isActive) {
      _lastTick = Duration.zero;
      _scrollTicker.start();
    } else if (_scrollSpeed == 0 && _scrollTicker.isActive) {
      _scrollTicker.stop();
    }
  }

  void _onScrollTick(Duration elapsed) {
    final position = _session?.scrollable?.position;
    final pointer = _lastPosition;
    if (position == null || pointer == null || _scrollSpeed == 0) return;
    final seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (seconds <= 0) return;
    final next = (position.pixels + _scrollSpeed * seconds).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return;
    position.jumpTo(next);
    // Cards move under a still finger; pick up the one now beneath it.
    _extendTo(pointer);
  }

  _TargetData? _targetAt(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(globalPosition));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is _TargetData) {
        return target.metaData as _TargetData;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: widget.child,
  );
}

/// One drag: cards in the anchor–finger range are selected; cards that leave
/// the range go back to how they were when the drag started.
class _DragSession {
  _DragSession({
    required this.anchor,
    required Set<String> initial,
    required this.scrollable,
  }) : _initial = initial,
       current = anchor;

  final int anchor;
  final Set<String> _initial;
  final ScrollableState? scrollable;
  int current;
  Set<String> _range = const {};

  ({Set<String> select, Set<String> deselect}) moveTo(Set<String> range) {
    final select = range.difference(_range).difference(_initial);
    final deselect = _range.difference(range).difference(_initial);
    _range = range;
    return (select: select, deselect: deselect);
  }
}
