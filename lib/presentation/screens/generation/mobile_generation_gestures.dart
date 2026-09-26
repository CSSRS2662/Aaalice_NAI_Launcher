import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MobileVerticalCloseGesture extends StatefulWidget {
  const MobileVerticalCloseGesture({
    super.key,
    required this.closeDirection,
    required this.onClose,
    required this.child,
  });

  final AxisDirection closeDirection;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<MobileVerticalCloseGesture> createState() =>
      _MobileVerticalCloseGestureState();
}

class _MobileVerticalCloseGestureState
    extends State<MobileVerticalCloseGesture> {
  static const double _distance = 88;
  static const double _velocity = 900;
  static const double _minimumFlingDistance = 24;
  static const double _axisAdvantage = 1.35;

  Offset? _start;
  Offset? _lastPosition;
  bool _hapticSent = false;

  bool _isClosingDirection(double value) =>
      widget.closeDirection == AxisDirection.up ? value < 0 : value > 0;

  bool _isCommitted(Offset delta, double velocity) {
    final vertical = delta.dy.abs();
    final verticalWins = vertical >= delta.dx.abs() * _axisAdvantage;
    final distanceCommitted = vertical >= _distance;
    final flingCommitted =
        vertical >= _minimumFlingDistance &&
        velocity.abs() >= _velocity &&
        velocity.sign == delta.dy.sign;
    return verticalWins &&
        _isClosingDirection(delta.dy) &&
        (distanceCommitted || flingCommitted);
  }

  void _handleUpdate(DragUpdateDetails details) {
    final start = _start;
    _lastPosition = details.globalPosition;
    if (start == null || _hapticSent) return;
    final delta = details.globalPosition - start;
    if (_isCommitted(delta, 0)) {
      _hapticSent = true;
      unawaited(HapticFeedback.lightImpact());
    }
  }

  void _handleEnd(DragEndDetails details) {
    final start = _start;
    final lastPosition = _lastPosition;
    if (start == null || lastPosition == null) return;
    final delta = lastPosition - start;
    final committed = _isCommitted(delta, details.primaryVelocity ?? 0);
    if (committed && !_hapticSent) {
      _hapticSent = true;
      unawaited(HapticFeedback.lightImpact());
    }
    _start = null;
    _lastPosition = null;
    if (committed) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (details) {
        _start = details.globalPosition;
        _lastPosition = details.globalPosition;
        _hapticSent = false;
      },
      onVerticalDragUpdate: _handleUpdate,
      onVerticalDragEnd: _handleEnd,
      onVerticalDragCancel: () {
        _start = null;
        _lastPosition = null;
        _hapticSent = false;
      },
      child: widget.child,
    );
  }
}
