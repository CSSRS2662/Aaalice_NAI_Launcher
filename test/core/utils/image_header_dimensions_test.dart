import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/image_header_dimensions.dart';

Uint8List _webp(String chunk, List<int> payload) {
  final body = [
    ...'WEBP'.codeUnits,
    ...chunk.codeUnits,
    ...[payload.length, 0, 0, 0],
    ...payload,
  ];
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...[body.length & 0xFF, (body.length >> 8) & 0xFF, 0, 0],
    ...body,
  ]);
}

void main() {
  final image = img.Image(width: 832, height: 1216);

  test('读取 PNG、JPEG、GIF 文件头中的尺寸', () {
    for (final bytes in [
      img.encodePng(image),
      img.encodeJpg(image),
      img.encodeGif(image),
    ]) {
      final size = ImageHeaderDimensions.parse(bytes);
      expect(size, isNotNull);
      expect(size!.width, 832);
      expect(size.height, 1216);
    }
  });

  test('读取 WebP 的 VP8X 与 VP8L 尺寸', () {
    // VP8X：4 字节标志后是 24 位的宽减一、高减一。
    final vp8x = _webp('VP8X', [0, 0, 0, 0, 0x3F, 0x03, 0, 0xBF, 0x04, 0]);
    expect(ImageHeaderDimensions.parse(vp8x), (width: 832, height: 1216));

    // VP8L：签名 0x2F 后 14 位宽减一、14 位高减一。
    const bits = (832 - 1) | ((1216 - 1) << 14);
    final vp8l = _webp('VP8L', [
      0x2F,
      bits & 0xFF,
      (bits >> 8) & 0xFF,
      (bits >> 16) & 0xFF,
      (bits >> 24) & 0xFF,
      0,
      0,
      0,
      0,
      0,
    ]);
    expect(ImageHeaderDimensions.parse(vp8l), (width: 832, height: 1216));
  });

  test('未知格式与截断的数据返回 null', () {
    expect(ImageHeaderDimensions.parse(Uint8List(0)), isNull);
    expect(
      ImageHeaderDimensions.parse(Uint8List.fromList('hello world'.codeUnits)),
      isNull,
    );
    final png = img.encodePng(image);
    expect(ImageHeaderDimensions.parse(png.sublist(0, 12)), isNull);
  });

  test('从文件读取时 JPEG 可越过较大的 EXIF 段找到 SOF', () async {
    final dir = await Directory.systemTemp.createTemp('image_header_');
    addTearDown(() => dir.delete(recursive: true));
    final withExif = img.Image(width: 640, height: 480)
      ..exif.imageIfd['ImageDescription'] = 'x' * 4000;
    final file = File('${dir.path}/photo.jpg')
      ..writeAsBytesSync(img.encodeJpg(withExif));

    final size = await ImageHeaderDimensions.read(file.path);
    expect(size, (width: 640, height: 480));
    expect(await ImageHeaderDimensions.read('${dir.path}/missing.png'), isNull);
  });
}
