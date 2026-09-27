/// Pocket Palette - 中性底色 + 可自定义强调色
///
/// 浅色：纯白画布，分组与控件逐级压暗，浮层保持近白并依靠阴影浮起。
/// 深色：中性炭黑画布，容器逐级提亮。
/// 中性色面不带色相；强调色只用于主操作、选择、焦点与关键进度，
/// 由 [PocketAccent] 决定。
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/modules/color/color_module.dart';
import 'package:nai_launcher/presentation/themes/pocket_accent.dart';

class PocketPalette extends BaseColorModule {
  const PocketPalette({this.accent = PocketAccent.fallback});

  final PocketAccent accent;

  @override
  ColorScheme get lightScheme => accent.applyTo(_neutralLight);

  @override
  ColorScheme get darkScheme => accent.applyTo(_neutralDark);

  @override
  bool get supportsDarkMode => true;

  static const _neutralLight = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFC4502A),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF5C5C63),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEFEFF2),
    onSecondaryContainer: Color(0xFF1B1B1F),
    tertiary: Color(0xFF3F6FB5),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE3EBFA),
    onTertiaryContainer: Color(0xFF1D3F78),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBE4E1),
    onErrorContainer: Color(0xFF7A1A14),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1B1B1F),
    onSurfaceVariant: Color(0xFF5C5C63),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF6F6F8),
    surfaceContainer: Color(0xFFEFEFF2),
    surfaceContainerHigh: Color(0xFFFCFCFD),
    surfaceContainerHighest: Color(0xFFE5E5EA),
    outline: Color(0xFF8B8B93),
    outlineVariant: Color(0xFFE3E3E8),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2B2B30),
    onInverseSurface: Color(0xFFF2F2F5),
  );

  static const _neutralDark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFEF8558),
    onPrimary: Color(0xFF2A1208),
    secondary: Color(0xFFA9A9B1),
    onSecondary: Color(0xFF18181A),
    secondaryContainer: Color(0xFF36363B),
    onSecondaryContainer: Color(0xFFEDEDF0),
    tertiary: Color(0xFF8FB5FF),
    onTertiary: Color(0xFF0E2250),
    tertiaryContainer: Color(0xFF26375A),
    onTertiaryContainer: Color(0xFFD8E4FF),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3B0A06),
    errorContainer: Color(0xFF5C1A16),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF18181A),
    onSurface: Color(0xFFEDEDF0),
    onSurfaceVariant: Color(0xFFA9A9B1),
    surfaceContainerLowest: Color(0xFF121214),
    surfaceContainerLow: Color(0xFF202023),
    surfaceContainer: Color(0xFF28282C),
    surfaceContainerHigh: Color(0xFF2E2E33),
    surfaceContainerHighest: Color(0xFF36363B),
    outline: Color(0xFF7E7E87),
    outlineVariant: Color(0xFF36363B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEDEDF0),
    onInverseSurface: Color(0xFF2B2B30),
  );
}
