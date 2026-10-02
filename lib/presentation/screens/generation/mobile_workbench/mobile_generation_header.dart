import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/image/resolution_preset.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/common/model_family_icon.dart';
import '../widgets/saved_resolution_presets.dart';

/// 生成页顶栏：只有模型（左）与尺寸（右）两个菜单，点按直接切换。移动端只在
/// 这里切换模型，参数页不再重复提供；输入与保存自定义尺寸仍在参数页。余额、
/// 智能体与队列在底栏。
class MobileGenerationHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const MobileGenerationHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// “NAI Diffusion V5 (Full)” → “V5 Full”，保留非官方前缀的模型全名。
  static String shortModelLabel(String model) =>
      (ImageModels.modelDisplayNames[model] ?? model)
          .replaceFirst('NAI Diffusion ', '')
          .replaceAll(RegExp(r'[()]'), '')
          .trim();

  static String sizeLabel(int width, int height) => '$width×$height';

  @override
  Widget build(BuildContext context) {
    return AppBar(
      key: const ValueKey('generation-mobile-header'),
      automaticallyImplyLeading: false,
      titleSpacing: 12,
      title: const MobileGenerationHeaderMenus(),
      actions: const [SizedBox(width: 12)],
    );
  }
}

/// Model at the start, size at the end. Each pill's share follows its natural
/// width, so both show in full when they fit and shrink together when they
/// don't.
class MobileGenerationHeaderMenus extends ConsumerWidget {
  const MobileGenerationHeaderMenus({super.key});

  static const double _gap = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(
      generationParamsNotifierProvider.select((params) => params.model),
    );
    final size = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => (params.width, params.height),
      ),
    );
    final modelLabel = MobileGenerationHeader.shortModelLabel(model);
    final sizeLabel = MobileGenerationHeader.sizeLabel(size.$1, size.$2);
    return Row(
      children: [
        Flexible(
          flex: _HeaderPill.flexFor(context, modelLabel),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: MobileModelMenu(label: modelLabel),
          ),
        ),
        const SizedBox(width: _gap),
        Flexible(
          flex: _HeaderPill.flexFor(context, sizeLabel),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: MobileSizeMenu(label: sizeLabel),
          ),
        ),
      ],
    );
  }
}

/// 模型下拉菜单：列出全部可见模型，当前模型带勾选标记。
class MobileModelMenu extends ConsumerWidget {
  const MobileModelMenu({super.key, this.label});

  /// Pill text; defaults to the short name of the current model.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(
      generationParamsNotifierProvider.select((params) => params.model),
    );
    // 测试期的 custom 键归一到正式 ID，保证当前模型一定在候选项里。
    final current = ImageModels.migrateLegacyModel(model);
    final colors = Theme.of(context).colorScheme;
    final pillLabel = label ?? MobileGenerationHeader.shortModelLabel(model);
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final id in ImageModels.visibleModels(current: current))
          MenuItemButton(
            key: ValueKey('generation-mobile-model-$id'),
            style: _menuItemStyle,
            leadingIcon: ModelFamilyIcon(
              modelId: id,
              displayName: ImageModels.modelDisplayNames[id],
              size: 20,
              color: id == current ? colors.primary : colors.onSurfaceVariant,
            ),
            trailingIcon: _CheckMark(selected: id == current),
            onPressed: () => ref
                .read(generationParamsNotifierProvider.notifier)
                .updateModel(id),
            child: Text(
              MobileGenerationHeader.shortModelLabel(id),
              style: TextStyle(
                fontWeight: id == current ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => _HeaderPill(
        key: const ValueKey('generation-mobile-model-action'),
        label: pillLabel,
        semanticLabel: context.l10n.mobileWorkbench_selectModel(pillLabel),
        open: controller.isOpen,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// 尺寸下拉菜单：按分组列出官方预设与参数页保存的自定义尺寸，只能选择。
class MobileSizeMenu extends ConsumerStatefulWidget {
  const MobileSizeMenu({super.key, this.label});

  /// Pill text; defaults to the current width×height.
  final String? label;

  @override
  ConsumerState<MobileSizeMenu> createState() => _MobileSizeMenuState();
}

class _MobileSizeMenuState extends ConsumerState<MobileSizeMenu> {
  List<CustomResolutionPreset> _saved = const [];

  @override
  void initState() {
    super.initState();
    _saved = _loadSaved();
  }

  // Saved sizes change on the parameter page; reread them on every open.
  List<CustomResolutionPreset> _loadSaved() =>
      loadSavedResolutionPresets(ref.read(localStorageServiceProvider));

  void _select(int width, int height) => ref
      .read(generationParamsNotifierProvider.notifier)
      .updateSize(width, height);

  @override
  Widget build(BuildContext context) {
    final size = ref.watch(
      generationParamsNotifierProvider.select(
        (params) => (params.width, params.height),
      ),
    );
    final l10n = context.l10n;
    final pillLabel =
        widget.label ?? MobileGenerationHeader.sizeLabel(size.$1, size.$2);
    bool isCurrent(int width, int height) =>
        width == size.$1 && height == size.$2;

    Widget item({
      required String id,
      required IconData icon,
      required String label,
      required int width,
      required int height,
    }) {
      final selected = isCurrent(width, height);
      return MenuItemButton(
        key: ValueKey('generation-mobile-size-$id'),
        style: _menuItemStyle,
        leadingIcon: Icon(icon, size: 20),
        trailingIcon: _CheckMark(selected: selected),
        onPressed: () => _select(width, height),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
    }

    final groups = ResolutionPreset.groupedPresets;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      onOpen: () => setState(() => _saved = _loadSaved()),
      menuChildren: [
        for (final group in ResolutionGroup.values)
          if (group != ResolutionGroup.custom &&
              (groups[group]?.isNotEmpty ?? false)) ...[
            _MenuGroupLabel(_groupName(context, group)),
            for (final preset in groups[group]!)
              item(
                id: preset.id,
                icon: _typeIcon(preset.type),
                label:
                    '${_typeName(context, preset.type)}  '
                    '${MobileGenerationHeader.sizeLabel(preset.width, preset.height)}',
                width: preset.width,
                height: preset.height,
              ),
          ],
        if (_saved.isNotEmpty) ...[
          _MenuGroupLabel(l10n.resolution_groupCustom),
          for (final preset in _saved)
            item(
              id: preset.id,
              icon: Icons.bookmark_outline_rounded,
              label: preset.displaySize,
              width: preset.width,
              height: preset.height,
            ),
        ],
      ],
      builder: (context, controller, _) => _HeaderPill(
        key: const ValueKey('generation-mobile-size-action'),
        label: pillLabel,
        semanticLabel: l10n.mobileWorkbench_selectSize(pillLabel),
        open: controller.isOpen,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  static IconData _typeIcon(ResolutionType type) => switch (type) {
    ResolutionType.portrait => Icons.crop_portrait_rounded,
    ResolutionType.landscape => Icons.crop_landscape_rounded,
    ResolutionType.square => Icons.crop_square_rounded,
    ResolutionType.custom => Icons.bookmark_outline_rounded,
  };

  static String _groupName(BuildContext context, ResolutionGroup group) {
    final l10n = context.l10n;
    return switch (group) {
      ResolutionGroup.normal => l10n.resolution_groupNormal,
      ResolutionGroup.large => l10n.resolution_groupLarge,
      ResolutionGroup.wallpaper => l10n.resolution_groupWallpaper,
      ResolutionGroup.small => l10n.resolution_groupSmall,
      ResolutionGroup.custom => l10n.resolution_groupCustom,
    };
  }

  static String _typeName(BuildContext context, ResolutionType type) {
    final l10n = context.l10n;
    return switch (type) {
      ResolutionType.portrait => l10n.resolution_typePortrait,
      ResolutionType.landscape => l10n.resolution_typeLandscape,
      ResolutionType.square => l10n.resolution_typeSquare,
      ResolutionType.custom => l10n.resolution_typeCustom,
    };
  }
}

final ButtonStyle _menuItemStyle = MenuItemButton.styleFrom(
  minimumSize: const Size(220, 48),
  padding: const EdgeInsets.symmetric(horizontal: 16),
);

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => selected
      ? Icon(
          Icons.check_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        )
      : const SizedBox(width: 20);
}

class _MenuGroupLabel extends StatelessWidget {
  const _MenuGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final bool open;
  final VoidCallback onPressed;

  // Horizontal padding, gap and chevron around the label.
  static const double _chromeWidth = 14 + 4 + 18 + 10;

  /// Flex weight proportional to the pill's natural width.
  static int flexFor(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + _chromeWidth;
    painter.dispose();
    return (width * 10).round().clamp(1, 1 << 20);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(theme.appTheme.controlRadius + 2);
    return Semantics(
      button: true,
      expanded: open,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      child: Material(
        color: controlSurfaceColor(colors),
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            // A squeezed pill (narrow phone, large text) drops the chevron
            // and padding first; the label then ellipsizes.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final roomy = constraints.maxWidth >= _chromeWidth + 24;
                return Padding(
                  padding: roomy
                      ? const EdgeInsets.fromLTRB(14, 6, 10, 6)
                      : const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (roomy) ...[
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : theme.appTheme.fastDuration,
                          curve: theme.appTheme.standardCurve,
                          child: Icon(
                            Icons.expand_more_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
