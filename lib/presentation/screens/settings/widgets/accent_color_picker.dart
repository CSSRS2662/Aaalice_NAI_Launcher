import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../themes/pocket_accent.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/image_editor/widgets/color_picker.dart';

/// 强调色的本地化名称；自定义颜色显示其十六进制值。
String accentColorLabel(AppLocalizations l10n, PocketAccent accent) =>
    switch (accent.id) {
      'ember' => l10n.settings_accentEmber,
      'blue' => l10n.settings_accentBlue,
      'indigo' => l10n.settings_accentIndigo,
      'violet' => l10n.settings_accentViolet,
      'rose' => l10n.settings_accentRose,
      'teal' => l10n.settings_accentTeal,
      'green' => l10n.settings_accentGreen,
      'graphite' => l10n.settings_accentGraphite,
      _ => '${l10n.settings_accentCustom} ${PocketAccent.hexOf(accent.seed)}',
    };

/// 强调色色板：预设色块依次排列，最后一个色块打开自定义颜色。
class AccentColorSwatches extends StatelessWidget {
  const AccentColorSwatches({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final PocketAccent selected;
  final ValueChanged<PocketAccent> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      key: const ValueKey('settings-accent-swatches'),
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final accent in PocketAccent.presets)
          _Swatch(
            key: ValueKey('settings-accent-${accent.id}'),
            label: accentColorLabel(l10n, accent),
            color: dark ? accent.dark : accent.light,
            selected: selected == accent,
            onTap: () => onSelected(accent),
          ),
        _Swatch(
          key: const ValueKey('settings-accent-custom'),
          label: selected.isCustom
              ? accentColorLabel(l10n, selected)
              : l10n.settings_accentCustom,
          color: selected.isCustom
              ? (dark ? selected.dark : selected.light)
              : null,
          selected: selected.isCustom,
          onTap: () async {
            final color = await showCustomAccentDialog(
              context,
              initial: selected.seed,
            );
            if (color != null) onSelected(PocketAccent.custom(color));
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  /// 为 null 时绘制色相环，表示“自定义”。
  final Color? color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double _extent = 48;
  static const double _dot = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final fill = color;
    final ring = selected ? colors.onSurface : Colors.transparent;
    final check = fill == null
        ? colors.onSurface
        : ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: InkResponse(
          onTap: onTap,
          radius: _extent / 2,
          child: SizedBox.square(
            dimension: _extent,
            child: Center(
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : theme.appTheme.fastDuration,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
                child: Container(
                  width: _dot,
                  height: _dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                    gradient: fill == null
                        ? const SweepGradient(
                            colors: [
                              Color(0xFFFF5252),
                              Color(0xFFFFD740),
                              Color(0xFF69F0AE),
                              Color(0xFF40C4FF),
                              Color(0xFF7C4DFF),
                              Color(0xFFFF4081),
                              Color(0xFFFF5252),
                            ],
                          )
                        : null,
                  ),
                  child: selected
                      ? Icon(Icons.check_rounded, size: 18, color: check)
                      : fill == null
                      ? const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 自定义强调色：色板取色并预览主按钮与选中态，确认后才应用到全局主题。
Future<Color?> showCustomAccentDialog(
  BuildContext context, {
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) => _CustomAccentDialog(initial: initial),
  );
}

class _CustomAccentDialog extends StatefulWidget {
  const _CustomAccentDialog({required this.initial});

  final Color initial;

  @override
  State<_CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<_CustomAccentDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final accent = PocketAccent.custom(_color);
    final preview = accent.applyTo(theme.colorScheme);
    // 色板内部依赖 LayoutBuilder，不能放进按固有宽度排版的 AlertDialog。
    return Dialog(
      key: const ValueKey('settings-accent-custom-dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.settings_accentCustomTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              HSVColorPicker(
                color: _color,
                hueHeight: 28,
                hexLabel: l10n.editor_colorHex,
                saturationBrightnessLabel:
                    l10n.editor_colorSaturationBrightness,
                hueLabel: l10n.editor_colorHue,
                onColorChanged: (color) => setState(() => _color = color),
              ),
              const SizedBox(height: 16),
              Row(
                key: const ValueKey('settings-accent-custom-preview'),
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: preview.primary,
                        foregroundColor: preview.onPrimary,
                      ),
                      onPressed: () {},
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(l10n.generation_generate),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: preview.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        theme.appTheme.controlRadius,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.check_rounded,
                        color: preview.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.common_cancel),
                  ),
                  FilledButton(
                    key: const ValueKey('settings-accent-custom-apply'),
                    onPressed: () => Navigator.pop(context, _color),
                    child: Text(l10n.common_apply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
