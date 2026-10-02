import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Swipe-down-to-close for the image viewer: the image follows the finger and
/// the backdrop fades; a release past [closeDistance] (or a downward fling)
/// closes, anything shorter springs back.
class DetailSwipeDismissController extends ChangeNotifier {
  DetailSwipeDismissController({
    required TickerProvider vsync,
    required this.onDismiss,
  }) : _spring = AnimationController(
         vsync: vsync,
         duration: const Duration(milliseconds: 180),
       ) {
    _spring.addListener(_onSpringTick);
  }

  /// Starts closing the viewer; false when the close was not started, in
  /// which case the image springs back.
  final bool Function() onDismiss;

  static const double closeDistance = 120;
  static const double flingVelocity = 900;
  static const double _fadeDistance = 400;

  final AnimationController _spring;
  double _offset = 0;
  double _springFrom = 0;
  bool _closing = false;

  /// Downward displacement of the image in logical pixels.
  double get offset => _offset;

  /// 0 at rest, 1 when the backdrop has fully faded.
  double get progress => (_offset / _fadeDistance).clamp(0.0, 1.0);

  void update(double deltaY) {
    if (_closing) return;
    _spring.stop();
    final next = math.max(0.0, _offset + deltaY);
    if (next == _offset) return;
    _offset = next;
    notifyListeners();
  }

  void end(double velocityY, {required bool reduceMotion}) {
    if (_closing || _offset == 0) return;
    final fling = velocityY > flingVelocity && _offset > 16;
    if (_offset > closeDistance || fling) {
      _closing = onDismiss();
      if (_closing) return;
    }
    if (reduceMotion) {
      _offset = 0;
      notifyListeners();
      return;
    }
    _springFrom = _offset;
    _spring.forward(from: 0);
  }

  void _onSpringTick() {
    _offset = _springFrom * (1 - Curves.easeOutCubic.transform(_spring.value));
    notifyListeners();
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }
}
