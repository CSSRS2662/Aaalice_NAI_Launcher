import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/metadata/hash_calculator.dart';

void main() {
  final calculator = FileHashCalculator();

  test(
    'background hash matches SHA-256 and is shared by later calls',
    () async {
      final bytes = Uint8List.fromList(
        List<int>.generate(
          FileHashCalculator.backgroundHashThresholdBytes + 1,
          (i) => i % 256,
        ),
      );
      final expected = sha256.convert(bytes).toString();

      final first = calculator.calculateFromBytesAsync(bytes);
      final concurrent = calculator.calculateFromBytesAsync(bytes);
      expect(identical(first, concurrent), isTrue);
      expect(await first, expected);

      expect(calculator.calculateFromBytes(bytes), expected);
      expect(await calculator.calculateFromBytesAsync(bytes), expected);
    },
  );

  test('small buffers hash synchronously with the same result', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final expected = sha256.convert(bytes).toString();

    expect(await calculator.calculateFromBytesAsync(bytes), expected);
    expect(calculator.calculateFromBytes(bytes), expected);
  });

  test('equal content in another buffer gets its own correct hash', () {
    final a = Uint8List.fromList([4, 5, 6]);
    final b = Uint8List.fromList([4, 5, 7]);

    expect(calculator.calculateFromBytes(a), sha256.convert(a).toString());
    expect(calculator.calculateFromBytes(b), sha256.convert(b).toString());
  });
}
