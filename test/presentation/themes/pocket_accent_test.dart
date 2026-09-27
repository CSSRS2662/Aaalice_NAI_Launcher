import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/pocket_palette.dart';
import 'package:nai_launcher/presentation/themes/pocket_accent.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return ((first > second ? first : second) + 0.05) /
      ((first > second ? second : first) + 0.05);
}

void main() {
  test('预设与自定义颜色可以往返持久化，损坏值回到默认强调色', () {
    for (final preset in PocketAccent.presets) {
      expect(PocketAccent.fromStorage(preset.storageValue), preset);
    }
    final custom = PocketAccent.custom(const Color(0xFF3366CC));
    expect(custom.storageValue, 'custom:#3366CC');
    expect(PocketAccent.fromStorage(custom.storageValue), custom);

    for (final broken in [null, '', 'unknown', 'custom:', 'custom:#12']) {
      expect(PocketAccent.fromStorage(broken), PocketAccent.fallback);
    }
  });

  test('自定义颜色在浅色与深色画布上都保持可读', () {
    for (final color in const [
      Color(0xFFFFEB3B),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
      Color(0xFF0D1B3E),
      Color(0xFF808080),
    ]) {
      final accent = PocketAccent.custom(color);
      final light = const PocketPalette().lightScheme.surface;
      final dark = const PocketPalette().darkScheme.surface;
      expect(_contrast(accent.light, light), greaterThanOrEqualTo(3));
      expect(_contrast(accent.dark, dark), greaterThanOrEqualTo(4.5));
    }
  });

  test('强调色只改变 primary 系角色，中性色面保持不变', () {
    const base = PocketPalette();
    const blue = PocketPalette(accent: PocketAccent.blue);
    for (final (a, b) in [
      (base.lightScheme, blue.lightScheme),
      (base.darkScheme, blue.darkScheme),
    ]) {
      expect(b.primary, isNot(a.primary));
      expect(b.primaryContainer, isNot(a.primaryContainer));
      expect(b.surface, a.surface);
      expect(b.surfaceContainerLow, a.surfaceContainerLow);
      expect(b.surfaceContainer, a.surfaceContainer);
      expect(b.surfaceContainerHigh, a.surfaceContainerHigh);
      expect(b.secondary, a.secondary);
      expect(b.error, a.error);
    }
    expect(blue.lightScheme.primary, PocketAccent.blue.light);
    expect(blue.darkScheme.primary, PocketAccent.blue.dark);
  });
}
