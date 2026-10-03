import 'dart:math' as math;
import 'dart:typed_data';

/// Splits a byte stream into frames prefixed with a 4-byte big-endian length.
///
/// Bytes are kept in one growable [Uint8List]: a `List<int>` buffer copies and
/// unboxes the whole final image element by element on the UI isolate, which
/// costs several frames when a full-size PNG arrives.
class LengthPrefixedFrameReader {
  static const int _initialCapacity = 64 * 1024;

  Uint8List _bytes = Uint8List(0);
  int _start = 0;
  int _end = 0;

  /// Bytes received but not yet returned by [nextFrame].
  int get length => _end - _start;

  bool get isEmpty => length == 0;

  bool get isNotEmpty => !isEmpty;

  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _reserve(chunk.length);
    _bytes.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }

  /// Returns the next complete frame payload, or null until it has arrived.
  ///
  /// The payload is a copy, so it stays valid while the reader keeps growing.
  Uint8List? nextFrame() {
    if (length < 4) return null;
    final frameLength = readLength(_bytes, _start);
    if (length < 4 + frameLength) return null;
    final payloadStart = _start + 4;
    final payloadEnd = payloadStart + frameLength;
    final frame = Uint8List.fromList(
      Uint8List.sublistView(_bytes, payloadStart, payloadEnd),
    );
    _consume(payloadEnd);
    return frame;
  }

  /// Returns and clears every byte not yet returned by [nextFrame].
  Uint8List takeRemaining() {
    final remaining = Uint8List.fromList(
      Uint8List.sublistView(_bytes, _start, _end),
    );
    _consume(_end);
    return remaining;
  }

  static int readLength(List<int> bytes, [int offset = 0]) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  void _consume(int end) {
    _start = end;
    if (_start == _end) {
      _start = 0;
      _end = 0;
    }
  }

  void _reserve(int extra) {
    if (_end + extra <= _bytes.length) return;
    final needed = length + extra;
    if (needed <= _bytes.length) {
      _bytes.setRange(0, length, _bytes, _start);
    } else {
      var capacity = math.max(_initialCapacity, _bytes.length * 2);
      while (capacity < needed) {
        capacity *= 2;
      }
      final grown = Uint8List(capacity)..setRange(0, length, _bytes, _start);
      _bytes = grown;
    }
    _end = length;
    _start = 0;
  }
}
