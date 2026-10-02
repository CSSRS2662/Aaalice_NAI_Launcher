import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import 'editable_double_field.dart';
import 'themed_slider.dart';

/// [ThemedSlider] for numeric parameters: −/+ move exactly one [step] (hold to
/// repeat) and the trailing field takes a typed value. Dragging the thumb
/// stays for coarse moves; landing it on one value of a long track is hard on
/// a phone.
class SteppedSlider extends StatelessWidget {
  const SteppedSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.divisions,
    this.decimals = 0,
    this.idPrefix,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final int? divisions;

  /// Digits shown in the field and kept after stepping.
  final int decimals;

  /// Prefix for the `-decrease`, `-increase` and `-value` keys.
  final String? idPrefix;

  double _snap(double raw) {
    final snapped = (raw / step).round() * step;
    return double.parse(snapped.clamp(min, max).toStringAsFixed(decimals));
  }

  Key? _key(String suffix) =>
      idPrefix == null ? null : ValueKey('$idPrefix-$suffix');

  @override
  Widget build(BuildContext context) {
    final current = value.clamp(min, max).toDouble();
    final l10n = context.l10n;
    return Row(
      children: [
        _StepButton(
          key: _key('decrease'),
          icon: Icons.remove_rounded,
          label: l10n.common_decrease,
          onStep: current > min ? () => onChanged(_snap(value - step)) : null,
        ),
        Expanded(
          child: ThemedSlider(
            value: current,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        _StepButton(
          key: _key('increase'),
          icon: Icons.add_rounded,
          label: l10n.common_increase,
          onStep: current < max ? () => onChanged(_snap(value + step)) : null,
        ),
        const SizedBox(width: 4),
        EditableDoubleField(
          key: _key('value'),
          value: current,
          min: min,
          max: max,
          decimals: decimals,
          width: 56,
          onChanged: (typed) => onChanged(_snap(typed)),
        ),
      ],
    );
  }
}

/// Steps once per tap and repeats while held, faster the longer it is held.
class _StepButton extends StatefulWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onStep,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;
  int _repeats = 0;

  @override
  void didUpdateWidget(covariant _StepButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // At a bound the button disables itself; stop repeating there.
    if (widget.onStep == null) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _stop();
    widget.onStep?.call();
    _scheduleNext();
  }

  void _scheduleNext() {
    final delay = Duration(milliseconds: _repeats < 6 ? 140 : 60);
    _repeat = Timer(delay, () {
      if (!mounted || widget.onStep == null) return _stop();
      _repeats++;
      widget.onStep!.call();
      _scheduleNext();
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
    _repeats = 0;
  }

  @override
  Widget build(BuildContext context) {
    final extent = context.interactionPolicy.minimumControlExtent;
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.onStep != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      onTap: widget.onStep,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: extent,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          // Tap belongs to the InkWell, hold only to the inner detector: two
          // long-press recognizers would race and could miss the release.
          child: InkWell(
            onTap: widget.onStep,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: enabled ? (_) => _start() : null,
              onLongPressEnd: (_) => _stop(),
              onLongPressCancel: _stop,
              child: Icon(
                widget.icon,
                size: 20,
                color: enabled
                    ? colors.onSurfaceVariant
                    : colors.onSurface.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
