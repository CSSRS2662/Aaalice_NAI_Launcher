import 'dart:collection';

import '../utils/image_header_dimensions.dart';

/// 按文件路径缓存图片宽高比，供库页面的瀑布流在构建卡片前确定高度。
///
/// 库条目的原图导入后不会原地改写，路径即可作为键；读取失败按方形处理。
class ImageFileAspectRatioCache {
  ImageFileAspectRatioCache._();

  static final instance = ImageFileAspectRatioCache._();

  static const int _capacity = 4096;

  final LinkedHashMap<String, double> _ratios = LinkedHashMap();
  final Map<String, Future<void>> _pending = {};

  /// 已知的宽高比；未知时返回 null。
  double? ratioOf(String path) => _ratios[path];

  /// 为尚未知道宽高比的文件读取文件头。
  Future<void> resolve(Iterable<String> paths) {
    final work = <Future<void>>[];
    for (final path in paths) {
      if (_ratios.containsKey(path)) continue;
      work.add(
        _pending[path] ??= _read(
          path,
        ).whenComplete(() => _pending.remove(path)),
      );
    }
    return Future.wait(work);
  }

  Future<void> _read(String path) async {
    final size = await ImageHeaderDimensions.read(path);
    _ratios[path] = size == null ? 1.0 : size.width / size.height;
    while (_ratios.length > _capacity) {
      _ratios.remove(_ratios.keys.first);
    }
  }
}
