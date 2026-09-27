import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// 从图片文件头读取像素尺寸，不解码图像数据。
///
/// 支持 PNG、JPEG、WebP（VP8 / VP8L / VP8X）与 GIF。瀑布流排版只需要宽高比，
/// 读取整张图片再解码代价过高；文件头之外的数据都不会被读取。
class ImageHeaderDimensions {
  const ImageHeaderDimensions._();

  /// PNG、WebP、GIF 的尺寸都在前 32 字节内；JPEG 的 SOF 段通常位于 EXIF
  /// 之后，按块向后查找，最多读取 [_maxJpegScan] 字节。
  static const int _headerBytes = 64;
  static const int _maxJpegScan = 512 * 1024;

  /// 读取 [path] 的尺寸；格式不支持或文件损坏时返回 null。
  static Future<({int width, int height})?> read(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final head = await file.read(_headerBytes);
      final quick = parse(head);
      if (quick != null) return quick;
      if (!_isJpeg(head)) return null;
      final length = await file.length();
      await file.setPosition(0);
      final scan = await file.read(math.min(length, _maxJpegScan));
      return _parseJpeg(scan);
    } on FileSystemException {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// 从已读取的文件头字节解析尺寸（JPEG 需要包含 SOF 段）。
  static ({int width, int height})? parse(Uint8List bytes) {
    return _parsePng(bytes) ??
        _parseGif(bytes) ??
        _parseWebp(bytes) ??
        (_isJpeg(bytes) ? _parseJpeg(bytes) : null);
  }

  static ({int width, int height})? _valid(int width, int height) =>
      width > 0 && height > 0 ? (width: width, height: height) : null;

  static ({int width, int height})? _parsePng(Uint8List b) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (b.length < 24) return null;
    for (var i = 0; i < signature.length; i++) {
      if (b[i] != signature[i]) return null;
    }
    // IHDR 必须是第一个块：长度(4) + "IHDR"(4) + 宽(4) + 高(4)。
    if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) {
      return null;
    }
    final data = ByteData.sublistView(b);
    return _valid(data.getUint32(16), data.getUint32(20));
  }

  static ({int width, int height})? _parseGif(Uint8List b) {
    if (b.length < 10 || b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46) {
      return null;
    }
    final data = ByteData.sublistView(b);
    return _valid(
      data.getUint16(6, Endian.little),
      data.getUint16(8, Endian.little),
    );
  }

  static ({int width, int height})? _parseWebp(Uint8List b) {
    if (b.length < 30 ||
        String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(b.sublist(8, 12)) != 'WEBP') {
      return null;
    }
    final data = ByteData.sublistView(b);
    switch (String.fromCharCodes(b.sublist(12, 16))) {
      case 'VP8 ':
        // 关键帧起始码 9D 01 2A 之后是 14 位宽高。
        return _valid(
          data.getUint16(26, Endian.little) & 0x3FFF,
          data.getUint16(28, Endian.little) & 0x3FFF,
        );
      case 'VP8L':
        if (b[20] != 0x2F) return null;
        final bits = data.getUint32(21, Endian.little);
        return _valid((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
      case 'VP8X':
        int read24(int offset) =>
            b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16);
        return _valid(read24(24) + 1, read24(27) + 1);
    }
    return null;
  }

  static bool _isJpeg(Uint8List b) =>
      b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;

  static ({int width, int height})? _parseJpeg(Uint8List b) {
    final data = ByteData.sublistView(b);
    var offset = 2;
    while (offset + 9 < b.length) {
      if (b[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = b[offset + 1];
      if (marker == 0xFF) {
        offset++;
        continue;
      }
      // SOF0–SOF15，排除 DHT(C4)、JPG(C8)、DAC(CC)。
      final isStartOfFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame) {
        return _valid(data.getUint16(offset + 7), data.getUint16(offset + 5));
      }
      // 没有长度字段的独立标记。
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
        offset += 2;
        continue;
      }
      final segmentLength = data.getUint16(offset + 2);
      if (segmentLength < 2) return null;
      offset += 2 + segmentLength;
    }
    return null;
  }
}
