import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';

class PromptWeightControls extends StatefulWidget {
  const PromptWeightControls({
    super.key,
    required this.weight,
    required this.onWeight,
    required this.onStep,
    this.enabled = true,
    this.trailing = const [],
    this.caption,
    this.onClose,
    this.onEdit,
    this.showEdit = false,
  });
  final double? weight;
  final ValueChanged<double> onWeight;
  final ValueChanged<double> onStep;
  final bool enabled;
  final List<Widget> trailing;
  final Widget? caption;
  final VoidCallback? onClose;
  final VoidCallback? onEdit;
  final bool showEdit;
  @override
  State<PromptWeightControls> createState() => _PromptWeightControlsState();
}

class _PromptWeightControlsState extends State<PromptWeightControls> {
  static const _minimumWeight = -3.0;
  static const _maximumWeight = 3.0;
  static const _weightStep = 0.05;
  static const _sliderDivisions = 120;

  double get _sliderValue {
    final weight = widget.weight;
    if (weight == null || !weight.isFinite) return 0;
    return _snapWeight(weight);
  }

  String get _valueLabel => widget.weight?.isFinite ?? false
      ? _sliderValue.toStringAsFixed(2)
      : context.l10n.tagMode_mixedWeights;

  double _snapWeight(double value) {
    final clamped = value.clamp(_minimumWeight, _maximumWeight);
    final step = ((clamped - _minimumWeight) / _weightStep).round();
    return double.parse(
      (_minimumWeight + step * _weightStep).toStringAsFixed(2),
    );
  }

  void _setWeight(double value) => widget.onWeight(_snapWeight(value));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final extent = context.interactionPolicy.minimumControlExtent.clamp(
      44.0,
      double.infinity,
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSlider(context, extent),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runAlignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: l10n.tooltip_resetWeight,
                onPressed: widget.enabled ? () => widget.onWeight(1) : null,
                constraints: BoxConstraints.tightFor(
                  width: extent,
                  height: extent,
                ),
                icon: const Icon(Icons.refresh, size: 18),
              ),
              if (widget.showEdit)
                TextButton.icon(
                  key: const ValueKey('tag-edit-button'),
                  onPressed: widget.onEdit,
                  style: TextButton.styleFrom(
                    minimumSize: Size(extent, extent),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.common_edit),
                ),
              ...widget.trailing,
              if (widget.onClose != null)
                IconButton(
                  tooltip: l10n.common_close,
                  onPressed: widget.onClose,
                  constraints: BoxConstraints.tightFor(
                    width: extent,
                    height: extent,
                  ),
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(BuildContext context, double extent) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('prompt-weight-slider-control'),
      color: controlSurfaceColor(theme.colorScheme),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child:
                        widget.caption ??
                        Text(
                          l10n.tagMode_weight,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  label: l10n.tagMode_weight,
                  value: _valueLabel,
                  liveRegion: true,
                  child: Text(
                    _valueLabel,
                    key: const ValueKey('prompt-weight-value'),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.tooltip_decreaseWeight,
                  onPressed: widget.enabled
                      ? () => widget.onStep(-_weightStep)
                      : null,
                  constraints: BoxConstraints.tightFor(
                    width: extent,
                    height: extent,
                  ),
                  icon: const Icon(Icons.remove, size: 18),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor: theme.colorScheme.onSurface
                          .withValues(alpha: 0.14),
                      thumbColor: theme.colorScheme.primary,
                      overlayColor: theme.colorScheme.primary.withValues(
                        alpha: 0.14,
                      ),
                      showValueIndicator: ShowValueIndicator.never,
                      tickMarkShape: SliderTickMarkShape.noTickMark,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 9,
                        disabledThumbRadius: 9,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 18,
                      ),
                    ),
                    child: Slider(
                      key: const ValueKey('prompt-weight-slider'),
                      value: _sliderValue,
                      min: _minimumWeight,
                      max: _maximumWeight,
                      divisions: _sliderDivisions,
                      onChanged: widget.enabled ? _setWeight : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.tooltip_increaseWeight,
                  onPressed: widget.enabled
                      ? () => widget.onStep(_weightStep)
                      : null,
                  constraints: BoxConstraints.tightFor(
                    width: extent,
                    height: extent,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
