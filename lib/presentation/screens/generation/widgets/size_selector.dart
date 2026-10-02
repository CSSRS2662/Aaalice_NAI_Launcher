import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/nai_resolution_adapter.dart';
import '../../../../data/models/image/resolution_preset.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/themed_dropdown.dart';
import 'saved_resolution_presets.dart';

/// 尺寸选择器 (带分组预设和自定义输入)
///
/// 从 ParameterPanel 提取的公开组件，经典布局的参数面板与
/// 官网式布局的置顶尺寸区共用。
class SizeSelector extends StatefulWidget {
  final int width;
  final int height;
  final void Function(int width, int height) onChanged;

  @visibleForTesting
  final LocalStorageService? storage;

  const SizeSelector({
    super.key,
    required this.width,
    required this.height,
    required this.onChanged,
    this.storage,
  });

  @override
  State<SizeSelector> createState() => _SizeSelectorState();
}

class _SizeSelectorState extends State<SizeSelector> {
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late FocusNode _widthFocusNode;
  late FocusNode _heightFocusNode;
  final FocusNode _dropdownFocusNode = FocusNode();
  late final LocalStorageService _storage;
  late List<CustomResolutionPreset> _savedCustomPresets;
  String? _selectedPresetId;
  bool _isUpdatingSavedPresets = false;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: widget.width.toString());
    _heightController = TextEditingController(text: widget.height.toString());
    _widthFocusNode = FocusNode();
    _heightFocusNode = FocusNode();
    _storage = widget.storage ?? LocalStorageService();
    _savedCustomPresets = _loadSavedCustomPresets();
    _updateSelectedPreset();
  }

  List<CustomResolutionPreset> _loadSavedCustomPresets() =>
      loadSavedResolutionPresets(_storage);

  @override
  void didUpdateWidget(covariant SizeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width || oldWidget.height != widget.height) {
      _syncFieldController(
        controller: _widthController,
        focusNode: _widthFocusNode,
        targetValue: widget.width,
      );
      _syncFieldController(
        controller: _heightController,
        focusNode: _heightFocusNode,
        targetValue: widget.height,
      );
      _updateSelectedPreset();
    }
  }

  void _syncFieldController({
    required TextEditingController controller,
    required FocusNode focusNode,
    required int targetValue,
  }) {
    final nextText = resolveManualSizeFieldSyncText(
      currentText: controller.text,
      targetValue: targetValue,
      hasFocus: focusNode.hasFocus,
    );
    if (nextText == null) {
      return;
    }

    controller.value = controller.value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
      composing: TextRange.empty,
    );
  }

  void _updateSelectedPreset() {
    final matchedPreset = ResolutionPreset.findBySize(
      widget.width,
      widget.height,
    );
    final savedPreset = _findSavedPresetBySize(widget.width, widget.height);
    _selectedPresetId = matchedPreset?.id ?? savedPreset?.id ?? 'custom';
  }

  CustomResolutionPreset? _findSavedPresetById(String id) {
    for (final preset in _savedCustomPresets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  CustomResolutionPreset? _findSavedPresetBySize(int width, int height) {
    for (final preset in _savedCustomPresets) {
      if (preset.width == width && preset.height == height) return preset;
    }
    return null;
  }

  ({int width, int height}) _manualSize() => (
    width: int.tryParse(_widthController.text) ?? 0,
    height: int.tryParse(_heightController.text) ?? 0,
  );

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _widthFocusNode.dispose();
    _heightFocusNode.dispose();
    _dropdownFocusNode.dispose();
    super.dispose();
  }

  String _getGroupName(BuildContext context, ResolutionGroup group) {
    final l10n = context.l10n;
    return switch (group) {
      ResolutionGroup.normal => l10n.resolution_groupNormal,
      ResolutionGroup.large => l10n.resolution_groupLarge,
      ResolutionGroup.wallpaper => l10n.resolution_groupWallpaper,
      ResolutionGroup.small => l10n.resolution_groupSmall,
      ResolutionGroup.custom => l10n.resolution_groupCustom,
    };
  }

  String _getTypeName(BuildContext context, ResolutionType type) {
    final l10n = context.l10n;
    return switch (type) {
      ResolutionType.portrait => l10n.resolution_typePortrait,
      ResolutionType.landscape => l10n.resolution_typeLandscape,
      ResolutionType.square => l10n.resolution_typeSquare,
      ResolutionType.custom => l10n.resolution_typeCustom,
    };
  }

  void _onPresetSelected(String? presetId) {
    if (presetId == null) return;

    // 选择后取消焦点
    _dropdownFocusNode.unfocus();

    setState(() {
      _selectedPresetId = presetId;
    });

    if (presetId == 'custom') {
      // 保持当前宽高不变
      return;
    }

    final savedPreset = _findSavedPresetById(presetId);
    if (savedPreset != null) {
      widget.onChanged(savedPreset.width, savedPreset.height);
      return;
    }

    final preset = ResolutionPreset.findById(presetId);
    if (preset != null) {
      widget.onChanged(preset.width, preset.height);
    }
  }

  void _onManualSizeChanged() {
    final newWidth = int.tryParse(_widthController.text) ?? widget.width;
    final newHeight = int.tryParse(_heightController.text) ?? widget.height;

    // 检查是否匹配某个预设
    final matchedPreset = ResolutionPreset.findBySize(newWidth, newHeight);
    final savedPreset = _findSavedPresetBySize(newWidth, newHeight);
    setState(() {
      _selectedPresetId = matchedPreset?.id ?? savedPreset?.id ?? 'custom';
    });

    if (newWidth != widget.width || newHeight != widget.height) {
      widget.onChanged(newWidth, newHeight);
    }
  }

  List<DropdownMenuItem<String>> _buildDropdownItems(BuildContext context) {
    final theme = Theme.of(context);
    final items = <DropdownMenuItem<String>>[];
    final groupedPresets = ResolutionPreset.groupedPresets;

    for (final group in ResolutionGroup.values) {
      final presets = groupedPresets[group] ?? [];
      if (presets.isEmpty) continue;

      // 分组标题 (不可选中)
      items.add(
        DropdownMenuItem<String>(
          enabled: false,
          value: '_header_${group.name}',
          child: Text(
            _getGroupName(context, group),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );

      // 分组内的预设
      for (final preset in presets) {
        final typeName = _getTypeName(context, preset.type);
        items.add(
          DropdownMenuItem<String>(
            value: preset.id,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                preset.getDisplayName(typeName),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        );
      }

      if (group == ResolutionGroup.custom) {
        for (final preset in _savedCustomPresets) {
          items.add(
            DropdownMenuItem<String>(
              value: preset.id,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  preset.displaySize,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          );
        }
      }
    }

    return items;
  }

  Future<void> _saveOrDeleteCustomPreset() async {
    if (_isUpdatingSavedPresets) return;
    final size = _manualSize();
    if (NaiResolutionAdapter.validateGenerationResolution(
          size.width,
          size.height,
        ) !=
        null) {
      return;
    }

    final existing = _findSavedPresetBySize(size.width, size.height);
    final nextPresets = existing == null
        ? <CustomResolutionPreset>[
            ..._savedCustomPresets,
            CustomResolutionPreset(width: size.width, height: size.height),
          ]
        : _savedCustomPresets
              .where((preset) => preset != existing)
              .toList(growable: false);

    final previousPresets = _savedCustomPresets;
    final previousSelectedPresetId = _selectedPresetId;
    setState(() {
      _savedCustomPresets = nextPresets;
      _selectedPresetId = existing == null
          ? CustomResolutionPreset(width: size.width, height: size.height).id
          : 'custom';
      _isUpdatingSavedPresets = true;
    });
    try {
      await _storage.setCustomResolutionPresets(
        nextPresets.map((preset) => preset.storageValue).toList(),
      );
      if (!mounted) return;
      setState(() => _isUpdatingSavedPresets = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savedCustomPresets = previousPresets;
        _selectedPresetId = previousSelectedPresetId;
        _isUpdatingSavedPresets = false;
      });
      AppToast.error(context, context.l10n.globalSettings_saveFailed(error));
    }
  }

  Widget _buildDimensionField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
  }) {
    return ThemedTextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      labelText: label,
      style: const TextStyle(fontSize: 13),
      onChanged: (_) => _onManualSizeChanged(),
    );
  }

  Widget _buildSwapButton(BuildContext context) {
    return IconButton(
      onPressed: () {
        final temp = _widthController.text;
        _widthController.text = _heightController.text;
        _heightController.text = temp;
        _onManualSizeChanged();
      },
      icon: const Icon(Icons.swap_horiz, size: 20),
      tooltip: context.l10n.common_swap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildCustomPresetAction(BuildContext context) {
    final size = _manualSize();
    final savedPreset = _findSavedPresetBySize(size.width, size.height);
    final matchesBuiltIn =
        ResolutionPreset.findBySize(size.width, size.height) != null;
    final valid =
        NaiResolutionAdapter.validateGenerationResolution(
          size.width,
          size.height,
        ) ==
        null;
    final deleting = savedPreset != null;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
      child: TextButton(
        key: ValueKey(
          deleting ? 'delete-custom-resolution' : 'save-custom-resolution',
        ),
        onPressed:
            !_isUpdatingSavedPresets && valid && (deleting || !matchesBuiltIn)
            ? () => unawaited(_saveOrDeleteCustomPreset())
            : null,
        style: deleting
            ? TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        child: Text(
          deleting ? context.l10n.common_delete : context.l10n.common_save,
        ),
      ),
    );
  }

  Widget _buildSizeInputs(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final customMode =
        _selectedPresetId == 'custom' ||
        _findSavedPresetById(_selectedPresetId ?? '') != null;

    Widget fieldsAndSwap() => Row(
      children: [
        Expanded(
          child: _buildDimensionField(
            controller: _widthController,
            focusNode: _widthFocusNode,
            label: l10n.resolution_width,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '×',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: _buildDimensionField(
            controller: _heightController,
            focusNode: _heightFocusNode,
            label: l10n.resolution_height,
          ),
        ),
        const SizedBox(width: 4),
        _buildSwapButton(context),
      ],
    );

    if (!customMode) return fieldsAndSwap();

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledLabelSize = MediaQuery.textScalerOf(context).scale(14);
        final action = _buildCustomPresetAction(context);
        if (constraints.maxWidth >= 344 && scaledLabelSize <= 22) {
          return Row(
            children: [
              Expanded(child: fieldsAndSwap()),
              const SizedBox(width: 4),
              action,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fieldsAndSwap(),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final resolutionIssue = NaiResolutionAdapter.validateGenerationResolution(
      widget.width,
      widget.height,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 预设下拉菜单
        ThemedDropdown<String>(
          key: ValueKey('resolution-preset-$_selectedPresetId'),
          value: _selectedPresetId,
          focusNode: _dropdownFocusNode,
          items: _buildDropdownItems(context),
          selectedItemBuilder: (context) {
            // 自定义选中项显示
            return _buildDropdownItems(context).map((item) {
              final savedPreset = _findSavedPresetById(item.value ?? '');
              if (savedPreset != null) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_getTypeName(context, ResolutionType.custom)} · '
                    '${savedPreset.displaySize}',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }
              final preset = ResolutionPreset.findById(item.value ?? '');
              if (preset == null) {
                return const Text('');
              }
              final typeName = _getTypeName(context, preset.type);
              final groupName = _getGroupName(context, preset.group);
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  preset.type == ResolutionType.custom
                      ? typeName
                      : '$groupName - ${preset.getDisplayName(typeName)}',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList();
          },
          onChanged: _onPresetSelected,
        ),

        const SizedBox(height: 8),

        // 宽高输入框
        _buildSizeInputs(context),
        if (resolutionIssue != null) ...[
          const SizedBox(height: 6),
          Text(
            l10n.generation_invalidResolutionHint(
              resolutionIssue.width,
              resolutionIssue.height,
              resolutionIssue.suggestedWidth,
              resolutionIssue.suggestedHeight,
            ),
            key: const ValueKey('invalid-resolution-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

@visibleForTesting
String? resolveManualSizeFieldSyncText({
  required String currentText,
  required int targetValue,
  required bool hasFocus,
}) {
  if (hasFocus) {
    return null;
  }

  final nextText = targetValue.toString();
  if (currentText == nextText) {
    return null;
  }

  return nextText;
}
