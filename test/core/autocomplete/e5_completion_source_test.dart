import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/e5_completion_source.dart';

void main() {
  test('更新语义包后只清理哈希命名的旧版本目录', () async {
    final root = await Directory.systemTemp.createTemp('e5-pack-versions-');
    addTearDown(() => root.delete(recursive: true));
    final keep = 'a' * 64;
    final stale = 'b' * 64;
    await Directory('${root.path}/$keep').create();
    await File('${root.path}/$stale/vectors.f32').create(recursive: true);
    await Directory('${root.path}/notes').create();
    await File('${root.path}/${'c' * 64}').writeAsString('not a directory');

    await E5CompletionSource.removeStaleVersions(root, keep: keep);

    expect(Directory('${root.path}/$keep').existsSync(), isTrue);
    expect(Directory('${root.path}/$stale').existsSync(), isFalse);
    expect(Directory('${root.path}/notes').existsSync(), isTrue);
    expect(File('${root.path}/${'c' * 64}').existsSync(), isTrue);
  });
}
