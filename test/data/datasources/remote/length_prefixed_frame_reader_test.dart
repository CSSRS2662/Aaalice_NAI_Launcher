import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/datasources/remote/length_prefixed_frame_reader.dart';

Uint8List _frame(List<int> payload) {
  final length = payload.length;
  return Uint8List.fromList([
    (length >> 24) & 0xff,
    (length >> 16) & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
    ...payload,
  ]);
}

void main() {
  test('returns frames split across chunks in order', () {
    final payloadA = List<int>.generate(70000, (i) => i % 251);
    final payloadB = [1, 2, 3];
    final stream = Uint8List.fromList([
      ..._frame(payloadA),
      ..._frame(payloadB),
    ]);
    final reader = LengthPrefixedFrameReader();
    final frames = <Uint8List>[];
    for (var offset = 0; offset < stream.length; offset += 1000) {
      final end = offset + 1000 < stream.length ? offset + 1000 : stream.length;
      reader.add(Uint8List.sublistView(stream, offset, end));
      for (var f = reader.nextFrame(); f != null; f = reader.nextFrame()) {
        frames.add(f);
      }
    }

    expect(frames, hasLength(2));
    expect(frames[0], payloadA);
    expect(frames[1], payloadB);
    expect(reader.isEmpty, isTrue);
  });

  test('frames stay intact after the reader reuses its buffer', () {
    final reader = LengthPrefixedFrameReader()..add(_frame([9, 9, 9]));
    final first = reader.nextFrame()!;
    reader.add(_frame(List<int>.filled(200000, 7)));
    final second = reader.nextFrame()!;

    expect(first, [9, 9, 9]);
    expect(second.length, 200000);
    expect(second.every((b) => b == 7), isTrue);
  });

  test('keeps a partial tail for the caller', () {
    final reader = LengthPrefixedFrameReader()
      ..add(_frame([5]))
      ..add([0x50, 0x4b, 0x03, 0x04, 0x14]);

    expect(reader.nextFrame(), [5]);
    expect(reader.nextFrame(), isNull);
    expect(reader.takeRemaining(), [0x50, 0x4b, 0x03, 0x04, 0x14]);
    expect(reader.isEmpty, isTrue);
  });
}
