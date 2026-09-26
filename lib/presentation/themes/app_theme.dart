import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/font_provider.dart';
import 'presets/pocket_theme.dart';

/// 主题明暗偏好：浅色、深色或跟随系统。
enum AppThemeMode {
  system,
  light,
  dark;

  ThemeMode get themeMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// 持久化值；未知或缺失时回到跟随系统。
  static AppThemeMode fromStorage(String? value) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return AppThemeMode.system;
  }
}

/// 应用主题管理器：只保留一套浅色与深色配色。
class AppTheme {
  AppTheme._();

  static final ThemeData _light = PocketTheme.light;
  static final ThemeData _dark = PocketTheme.dark;

  /// 获取指定明暗的主题
  ///
  /// [fontConfig] 为 null 或系统默认时，保留主题原生字体；
  /// 有值时用用户选择覆盖主题字体。
  static ThemeData getTheme(Brightness brightness, {FontConfig? fontConfig}) {
    final baseTheme = brightness == Brightness.light ? _light : _dark;

    // 使用主题原生字体
    if (fontConfig == null || fontConfig.fontFamily.isEmpty) {
      return baseTheme.copyWith(
        tooltipTheme: _buildTooltipTheme(baseTheme, null),
      );
    }

    // 应用用户选择的字体
    return _applyFontConfig(baseTheme, fontConfig);
  }

  /// 应用字体配置到主题
  static ThemeData _applyFontConfig(
    ThemeData baseTheme,
    FontConfig fontConfig,
  ) {
    final result = switch (fontConfig.source) {
      FontSource.google => _buildGoogleFontTheme(
        baseTheme,
        fontConfig.fontFamily,
      ),
      FontSource.system => (
        baseTheme.textTheme.apply(fontFamily: fontConfig.fontFamily),
        baseTheme.primaryTextTheme.apply(fontFamily: fontConfig.fontFamily),
        fontConfig.fontFamily,
      ),
    };

    if (result == null) {
      return baseTheme.copyWith(
        tooltipTheme: _buildTooltipTheme(baseTheme, null),
      );
    }

    final (textTheme, primaryTextTheme, tooltipFontFamily) = result;

    return baseTheme.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      tooltipTheme: _buildTooltipTheme(baseTheme, tooltipFontFamily),
      chipTheme: _applyFontToChipTheme(baseTheme.chipTheme, textTheme),
    );
  }

  /// 把用户字体同步到 Chip 的标签样式。
  ///
  /// Chip 对 `labelStyle` / `secondaryLabelStyle` 是"有则取之"而非合并：
  /// 主题一旦设了这两项，就不会再回退到 `textTheme.labelLarge`，
  /// 因此仅更新 textTheme 不足以让 Chip 跟随用户选择的字体。
  static ChipThemeData _applyFontToChipTheme(
    ChipThemeData chipTheme,
    TextTheme textTheme,
  ) {
    final fontFamily = textTheme.labelLarge?.fontFamily;
    if (fontFamily == null) return chipTheme;
    return chipTheme.copyWith(
      labelStyle: chipTheme.labelStyle?.copyWith(fontFamily: fontFamily),
      secondaryLabelStyle: chipTheme.secondaryLabelStyle?.copyWith(
        fontFamily: fontFamily,
      ),
    );
  }

  /// 构建 Google Font 主题，返回 null 如果字体无效
  static (TextTheme textTheme, TextTheme primaryTextTheme, String? fontFamily)?
  _buildGoogleFontTheme(ThemeData baseTheme, String fontName) {
    try {
      final fontFamily = GoogleFonts.getFont(fontName).fontFamily;
      return (
        _applyGoogleFont(baseTheme.textTheme, fontName),
        _applyGoogleFont(baseTheme.primaryTextTheme, fontName),
        fontFamily,
      );
    } catch (e) {
      return null;
    }
  }

  /// 使用 Google Font 应用到 TextTheme
  static TextTheme _applyGoogleFont(TextTheme base, String fontName) {
    final fontFamily = GoogleFonts.getFont(fontName).fontFamily;

    TextStyle? applyFont(TextStyle? style) =>
        style?.copyWith(fontFamily: fontFamily);

    return base.copyWith(
      displayLarge: applyFont(base.displayLarge),
      displayMedium: applyFont(base.displayMedium),
      displaySmall: applyFont(base.displaySmall),
      headlineLarge: applyFont(base.headlineLarge),
      headlineMedium: applyFont(base.headlineMedium),
      headlineSmall: applyFont(base.headlineSmall),
      titleLarge: applyFont(base.titleLarge),
      titleMedium: applyFont(base.titleMedium),
      titleSmall: applyFont(base.titleSmall),
      bodyLarge: applyFont(base.bodyLarge),
      bodyMedium: applyFont(base.bodyMedium),
      bodySmall: applyFont(base.bodySmall),
      labelLarge: applyFont(base.labelLarge),
      labelMedium: applyFont(base.labelMedium),
      labelSmall: applyFont(base.labelSmall),
    );
  }

  /// 保留主题预设的浮层样式，仅同步用户字体。
  static TooltipThemeData _buildTooltipTheme(
    ThemeData baseTheme,
    String? fontFamily,
  ) {
    final tooltipTheme = baseTheme.tooltipTheme;
    return tooltipTheme.copyWith(
      textStyle: (tooltipTheme.textStyle ?? baseTheme.textTheme.bodySmall)
          ?.copyWith(fontFamily: fontFamily),
      padding:
          tooltipTheme.padding ??
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration:
          tooltipTheme.waitDuration ?? const Duration(milliseconds: 500),
    );
  }
}
