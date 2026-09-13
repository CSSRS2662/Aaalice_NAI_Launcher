/// 分辨率预设分组
enum ResolutionGroup {
  normal,
  large,
  wallpaper,
  small,
  custom,
}

/// 分辨率类型
enum ResolutionType {
  portrait,
  landscape,
  square,
  custom,
}

/// 分辨率预设
class ResolutionPreset {
  final String id;
  final ResolutionGroup group;
  final ResolutionType type;
  final int width;
  final int height;

  const ResolutionPreset({
    required this.id,
    required this.group,
    required this.type,
    required this.width,
    required this.height,
  });

  /// 显示名称（如 "Portrait (832×1216)"）
  String getDisplayName(String typeName) {
    if (type == ResolutionType.custom) {
      return typeName;
    }
    return '$typeName ($width×$height)';
  }

  /// 所有预设列表
  static const List<ResolutionPreset> presets = [
    // NORMAL
    ResolutionPreset(
      id: 'normal_portrait',
      group: ResolutionGroup.normal,
      type: ResolutionType.portrait,
      width: 832,
      height: 1216,
    ),
    ResolutionPreset(
      id: 'normal_landscape',
      group: ResolutionGroup.normal,
      type: ResolutionType.landscape,
      width: 1216,
      height: 832,
    ),
    ResolutionPreset(
      id: 'normal_square',
      group: ResolutionGroup.normal,
      type: ResolutionType.square,
      width: 1024,
      height: 1024,
    ),
    // LARGE
    ResolutionPreset(
      id: 'large_portrait',
      group: ResolutionGroup.large,
      type: ResolutionType.portrait,
      width: 1024,
      height: 1536,
    ),
    ResolutionPreset(
      id: 'large_landscape',
      group: ResolutionGroup.large,
      type: ResolutionType.landscape,
      width: 1536,
      height: 1024,
    ),
    ResolutionPreset(
      id: 'large_square',
      group: ResolutionGroup.large,
      type: ResolutionType.square,
      width: 1472,
      height: 1472,
    ),
    // WALLPAPER
    ResolutionPreset(
      id: 'wallpaper_portrait',
      group: ResolutionGroup.wallpaper,
      type: ResolutionType.portrait,
      width: 1088,
      height: 1920,
    ),
    ResolutionPreset(
      id: 'wallpaper_landscape',
      group: ResolutionGroup.wallpaper,
      type: ResolutionType.landscape,
      width: 1920,
      height: 1088,
    ),
    // SMALL
    ResolutionPreset(
      id: 'small_portrait',
      group: ResolutionGroup.small,
      type: ResolutionType.portrait,
      width: 512,
      height: 768,
    ),
    ResolutionPreset(
      id: 'small_landscape',
      group: ResolutionGroup.small,
      type: ResolutionType.landscape,
      width: 768,
      height: 512,
    ),
    ResolutionPreset(
      id: 'small_square',
      group: ResolutionGroup.small,
      type: ResolutionType.square,
      width: 640,
      height: 640,
    ),
    // CUSTOM
    ResolutionPreset(
      id: 'custom',
      group: ResolutionGroup.custom,
      type: ResolutionType.custom,
      width: 0,
      height: 0,
    ),
  ];

  /// 根据 ID 查找预设
  static ResolutionPreset? findById(String id) {
    try {
      return presets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 根据宽高查找匹配的预设
  static ResolutionPreset? findBySize(int width, int height) {
    try {
      return presets.firstWhere(
        (p) =>
            p.width == width &&
            p.height == height &&
            p.type != ResolutionType.custom,
      );
    } catch (_) {
      return null;
    }
  }

  /// 获取指定分组的预设列表
  static List<ResolutionPreset> getByGroup(ResolutionGroup group) {
    return presets.where((p) => p.group == group).toList();
  }

  /// 按分组整理的预设映射
  static Map<ResolutionGroup, List<ResolutionPreset>> get groupedPresets {
    final map = <ResolutionGroup, List<ResolutionPreset>>{};
    for (final group in ResolutionGroup.values) {
      map[group] = getByGroup(group);
    }
    return map;
  }
}

/// 用户保存的自定义分辨率。
///
/// 持久化只使用稳定的 `宽x高` 字符串，避免将展示文案或运行时对象写入设置。
class CustomResolutionPreset {
  const CustomResolutionPreset({required this.width, required this.height});

  final int width;
  final int height;

  String get id => 'saved_custom_${width}_$height';
  String get storageValue => '${width}x$height';
  String get displaySize => '$width×$height';

  static CustomResolutionPreset? fromStorageValue(String value) {
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value.trim());
    if (match == null) return null;

    final width = int.tryParse(match.group(1)!);
    final height = int.tryParse(match.group(2)!);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return CustomResolutionPreset(width: width, height: height);
  }

  @override
  bool operator ==(Object other) =>
      other is CustomResolutionPreset &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
