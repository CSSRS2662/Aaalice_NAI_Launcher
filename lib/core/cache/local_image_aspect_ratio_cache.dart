import 'dart:collection';

import '../../data/models/gallery/local_image_record.dart';
import '../utils/image_header_dimensions.dart';

/// 本地图片宽高比缓存，供瀑布流在构建卡片前确定每张图的高度。
///
/// NAI 生成图的元数据自带宽高，直接使用；其余图片读取文件头获取尺寸，
/// 结果按路径、大小与修改时间缓存，文件被替换后自动失效。
class LocalImageAspectRatioCache {
  LocalImageAspectRatioCache._();

  static final instance = LocalImageAspectRatioCache._();

  static const int _capacity = 4096;

  final LinkedHashMap<String, double> _ratios = LinkedHashMap();
  final Map<String, Future<void>> _pending = {};

  static String _keyOf(LocalImageRecord record) =>
      '${record.path}|${record.size}|${record.modifiedAt.millisecondsSinceEpoch}';

  /// 已知的宽高比；未知时返回 null。
  double? ratioOf(LocalImageRecord record) {
    final metadata = record.metadata;
    final width = metadata?.width;
    final height = metadata?.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return _ratios[_keyOf(record)];
  }

  /// 为尚未知道宽高比的图片读取文件头；读取失败的图片按方形处理。
  Future<void> resolve(Iterable<LocalImageRecord> records) {
    final work = <Future<void>>[];
    for (final record in records) {
      if (ratioOf(record) != null) continue;
      final key = _keyOf(record);
      work.add(
        _pending[key] ??= _read(
          record,
          key,
        ).whenComplete(() => _pending.remove(key)),
      );
    }
    return Future.wait(work);
  }

  Future<void> _read(LocalImageRecord record, String key) async {
    final size = await ImageHeaderDimensions.read(record.path);
    _ratios[key] = size == null ? 1.0 : size.width / size.height;
    while (_ratios.length > _capacity) {
      _ratios.remove(_ratios.keys.first);
    }
  }
}
