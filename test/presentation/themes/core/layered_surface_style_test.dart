import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/presentation/themes/core/theme_composer.dart';
import 'package:nai_launcher/presentation/themes/core/theme_modules.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/pocket_palette.dart';

void main() {
  test('缺少容器色阶的暗色配色仍能形成画布、区块和控件三级色面', () {
    const colors = _legacyDarkScheme;
    final section = sectionSurfaceColor(colors);
    final control = controlSurfaceColor(colors);
    final overlay = overlaySurfaceColor(colors);

    expect(section, isNot(colors.surface));
    expect(control, isNot(colors.surface));
    expect(overlay, isNot(colors.surface));
    expect(control, isNot(section));
    expect(
      section.computeLuminance(),
      greaterThan(colors.surface.computeLuminance()),
    );
    expect(control.computeLuminance(), greaterThan(section.computeLuminance()));
    expect(overlay.computeLuminance(), greaterThan(section.computeLuminance()));
    expect(section.r, section.g);
    expect(section.g, section.b);
  });

  test('补全缺失的中性色面阶梯', () {
    const source = _legacyDarkScheme;
    final colors = resolveLayeredSurfaceColors(source);

    expect(colors.surfaceContainerLow, isNot(colors.surface));
    expect(colors.surfaceContainer, isNot(colors.surfaceContainerLow));
    expect(colors.surfaceContainerHigh, isNot(colors.surfaceContainer));
    expect(colors.surfaceContainerHighest, isNot(colors.surfaceContainerHigh));
    expect(colors.surfaceContainerLow.r, colors.surfaceContainerLow.g);
    expect(colors.surfaceContainerLow.g, colors.surfaceContainerLow.b);
  });

  test('最终主题在 Android 和桌面使用同一套中性色面', () {
    final theme = const ThemeComposer(
      color: _LegacyPalette(),
      typography: _TestTypography(),
      shape: _TestShape(),
      motion: _TestMotion(),
    ).buildTheme(Brightness.dark);
    final colors = theme.colorScheme;

    expect(theme.cardTheme.color, colors.surfaceContainerLow);
    expect(colors.surfaceContainerLow, isNot(colors.surface));
    expect(colors.surfaceContainerLow.r, colors.surfaceContainerLow.g);
    expect(colors.surfaceContainerLow.g, colors.surfaceContainerLow.b);

    final androidTheme = theme.copyWith(platform: TargetPlatform.android);
    final windowsTheme = theme.copyWith(platform: TargetPlatform.windows);
    expect(
      androidTheme.colorScheme.surfaceContainerLow,
      windowsTheme.colorScheme.surfaceContainerLow,
    );
    expect(androidTheme.cardTheme.color, windowsTheme.cardTheme.color);
  });

  test('Pocket 配色显式声明的容器色阶保持单调且与画布可辨', () {
    for (final colors in [
      const PocketPalette().lightScheme,
      const PocketPalette().darkScheme,
    ]) {
      final resolved = resolveLayeredSurfaceColors(colors);
      expect(resolved.surfaceContainerLow, colors.surfaceContainerLow);
      expect(resolved.surfaceContainer, colors.surfaceContainer);
      expect(resolved.surfaceContainerHigh, colors.surfaceContainerHigh);
      expect(resolved.surfaceContainerHighest, colors.surfaceContainerHighest);
      for (final layer in [
        resolved.surfaceContainerLow,
        resolved.surfaceContainer,
        resolved.surfaceContainerHigh,
        resolved.surfaceContainerHighest,
      ]) {
        expect(layer, isNot(colors.surface));
        // 暖中性：三通道差不超过 16/255，只带轻微暖调，不出现明显色相。
        final channels = [layer.r, layer.g, layer.b];
        final spread =
            channels.reduce((a, b) => a > b ? a : b) -
            channels.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThanOrEqualTo(16 / 255));
      }
      if (colors.brightness == Brightness.dark) {
        final ladder = [
          colors.surface,
          resolved.surfaceContainerLow,
          resolved.surfaceContainer,
          resolved.surfaceContainerHigh,
          resolved.surfaceContainerHighest,
        ].map((color) => color.computeLuminance()).toList();
        for (var i = 1; i < ladder.length; i++) {
          expect(ladder[i], greaterThan(ladder[i - 1]));
        }
      } else {
        // 浅色：分组与浮层浮于画布之上，控件压暗于画布。
        expect(
          resolved.surfaceContainerLow.computeLuminance(),
          greaterThan(colors.surface.computeLuminance()),
        );
        expect(
          resolved.surfaceContainer.computeLuminance(),
          lessThan(colors.surface.computeLuminance()),
        );
        expect(
          resolved.surfaceContainerHighest.computeLuminance(),
          lessThan(resolved.surfaceContainer.computeLuminance()),
        );
      }
    }
  });

  test('已经声明容器色的主题保持原有语义颜色', () {
    final colors = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    expect(sectionSurfaceColor(colors), colors.surfaceContainerLow);
    expect(controlSurfaceColor(colors), colors.surfaceContainer);
    expect(overlaySurfaceColor(colors), colors.surfaceContainerHigh);
  });
}

/// 只声明画布与前景、未声明 Material 3 容器色阶的配色，验证补全路径。
const _legacyDarkScheme = ColorScheme.dark(
  primary: Color(0xFFF0EAD6),
  onPrimary: Color(0xFF1A1A1A),
  secondary: Color(0xFFDC143C),
  surface: Color(0xFF1A1A1A),
  onSurface: Color(0xFFF0EAD6),
  error: Color(0xFFDC143C),
);

class _LegacyPalette implements ColorSchemeModule {
  const _LegacyPalette();

  @override
  ColorScheme get darkScheme => _legacyDarkScheme;

  @override
  ColorScheme get lightScheme => _legacyDarkScheme;

  @override
  bool get supportsDarkMode => true;
}

class _TestTypography implements TypographyModule {
  const _TestTypography();

  @override
  String get bodyFontFamily => 'Test';

  @override
  String get displayFontFamily => 'Test';

  @override
  TextTheme get textTheme => const TextTheme();
}

class _TestShape implements ShapeModule {
  const _TestShape();

  @override
  ShapeBorder get buttonShape => const RoundedRectangleBorder();

  @override
  ShapeBorder get cardShape => const RoundedRectangleBorder();

  @override
  ShapeBorder get inputShape => const RoundedRectangleBorder();

  @override
  double get largeRadius => 8;

  @override
  double get mediumRadius => 6;

  @override
  double get menuRadius => 4;

  @override
  ShapeBorder get menuShape => const RoundedRectangleBorder();

  @override
  double get smallRadius => 4;
}

class _TestMotion implements MotionModule {
  const _TestMotion();

  @override
  Curve get enterCurve => Curves.easeOut;

  @override
  Curve get exitCurve => Curves.easeIn;

  @override
  Duration get fastDuration => const Duration(milliseconds: 100);

  @override
  Duration get normalDuration => const Duration(milliseconds: 200);

  @override
  Duration get slowDuration => const Duration(milliseconds: 300);

  @override
  Curve get standardCurve => Curves.easeInOut;
}
