import 'package:flutter/material.dart';

/// Pocket 主题的强调色：一个预设或用户自定义的颜色，浅色与深色各取一档。
///
/// 强调色只决定 primary 系角色；画布、分组、控件等中性色面不随它变化。
@immutable
class PocketAccent {
  const PocketAccent._(this.id, this.light, this.dark, {Color? seed})
    : seed = seed ?? light;

  /// 自定义颜色。浅色直接采用所选颜色（对白色画布对比度不足时压暗），
  /// 深色取同色相、更亮的一档，保证在深色画布上清晰可读。
  factory PocketAccent.custom(Color color) {
    final opaque = color.withAlpha(0xFF);
    return PocketAccent._(
      customId,
      _ensureContrast(opaque, against: Colors.white, minimum: 3),
      _ensureContrast(
        ColorScheme.fromSeed(
          seedColor: opaque,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).primary,
        against: _darkCanvas,
        minimum: 4.5,
      ),
      seed: opaque,
    );
  }

  static const customId = 'custom';
  static const _darkCanvas = Color(0xFF18181A);

  static const ember = PocketAccent._(
    'ember',
    Color(0xFFC4502A),
    Color(0xFFEF8558),
  );
  static const blue = PocketAccent._(
    'blue',
    Color(0xFF1967D2),
    Color(0xFF8AB4F8),
  );
  static const indigo = PocketAccent._(
    'indigo',
    Color(0xFF4F5BD5),
    Color(0xFFA5ACFF),
  );
  static const violet = PocketAccent._(
    'violet',
    Color(0xFF7A4FD0),
    Color(0xFFC4A8FF),
  );
  static const rose = PocketAccent._(
    'rose',
    Color(0xFFC8305F),
    Color(0xFFFF8EB0),
  );
  static const teal = PocketAccent._(
    'teal',
    Color(0xFF00796B),
    Color(0xFF5ED3C3),
  );
  static const green = PocketAccent._(
    'green',
    Color(0xFF2E7D32),
    Color(0xFF7FD591),
  );
  static const graphite = PocketAccent._(
    'graphite',
    Color(0xFF2B2B30),
    Color(0xFFE6E6EA),
  );

  /// 设置页展示顺序；第一项为默认强调色。
  static const presets = [
    ember,
    blue,
    indigo,
    violet,
    rose,
    teal,
    green,
    graphite,
  ];

  static const fallback = ember;

  /// 预设标识，自定义颜色为 [customId]。
  final String id;

  /// 浅色主题的 primary。
  final Color light;

  /// 深色主题的 primary。
  final Color dark;

  /// 用户选择的原色；预设与浅色一档相同。
  final Color seed;

  bool get isCustom => id == customId;

  /// 持久化值：预设存标识，自定义存 `custom:#RRGGBB`（用户选择的原色）。
  String get storageValue => isCustom ? '$customId:${hexOf(seed)}' : id;

  /// 解析持久化值；未知或损坏时回到默认强调色。
  static PocketAccent fromStorage(String? value) {
    if (value == null || value.isEmpty) return fallback;
    for (final preset in presets) {
      if (preset.id == value) return preset;
    }
    const prefix = '$customId:';
    if (value.startsWith(prefix)) {
      final color = _parseHex(value.substring(prefix.length));
      if (color != null) return PocketAccent.custom(color);
    }
    return fallback;
  }

  /// 该明暗下的 primary 系角色：主色、主色上的前景、容器与容器前景。
  ColorScheme applyTo(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final primary = isDark ? dark : light;
    final tonal = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: scheme.brightness,
    );
    return scheme.copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      primaryContainer: tonal.primaryContainer,
      onPrimaryContainer: tonal.onPrimaryContainer,
      inversePrimary: isDark ? light : dark,
      surfaceTint: primary,
    );
  }

  static Color _onColor(Color color) =>
      _contrast(Colors.white, color) >= _contrast(Colors.black, color)
      ? Colors.white
      : Colors.black;

  static double _contrast(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    final lighter = first > second ? first : second;
    final darker = first > second ? second : first;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// 沿明度方向逐步调整，直到与 [against] 的对比度达到 [minimum]。
  static Color _ensureContrast(
    Color color, {
    required Color against,
    required double minimum,
  }) {
    if (_contrast(color, against) >= minimum) return color;
    final darken = against.computeLuminance() > 0.5;
    var hsl = HSLColor.fromColor(color);
    for (var i = 0; i < 40 && _contrast(hsl.toColor(), against) < minimum; i++) {
      hsl = hsl.withLightness(
        (hsl.lightness + (darken ? -0.025 : 0.025)).clamp(0.0, 1.0),
      );
    }
    return hsl.toColor();
  }

  /// `#RRGGBB`，供持久化与自定义颜色输入框共用。
  static String hexOf(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color? _parseHex(String value) {
    final digits = value.startsWith('#') ? value.substring(1) : value;
    if (digits.length != 6) return null;
    final parsed = int.tryParse(digits, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  @override
  bool operator ==(Object other) =>
      other is PocketAccent &&
      other.id == id &&
      other.seed == seed &&
      other.light == light &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(id, seed, light, dark);
}
