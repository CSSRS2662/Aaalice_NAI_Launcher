/// Pocket Palette - 暖中性底色 + 余烬强调色
///
/// 浅色：暖白画布上浮起纯净分组卡片，控件轻微压暗。
/// 深色：暖炭画布，容器逐级提亮。
/// 强调色只用于主操作、选择、焦点与关键进度。
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/modules/color/color_module.dart';

class PocketPalette extends BaseColorModule {
  const PocketPalette();

  @override
  ColorScheme get lightScheme => const ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFC4502A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF7E4DA),
    onPrimaryContainer: Color(0xFF7A2E14),
    secondary: Color(0xFF5F5850),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEFEBE5),
    onSecondaryContainer: Color(0xFF1E1B18),
    tertiary: Color(0xFF3F6FB5),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE3EBFA),
    onTertiaryContainer: Color(0xFF1D3F78),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBE4E1),
    onErrorContainer: Color(0xFF7A1A14),
    surface: Color(0xFFF5F3EF),
    onSurface: Color(0xFF1E1B18),
    onSurfaceVariant: Color(0xFF5F5850),
    surfaceContainerLowest: Color(0xFFFFFEFC),
    surfaceContainerLow: Color(0xFFFDFCFA),
    surfaceContainer: Color(0xFFEFEBE5),
    surfaceContainerHigh: Color(0xFFFEFDFB),
    surfaceContainerHighest: Color(0xFFE4DFD7),
    outline: Color(0xFF8F867C),
    outlineVariant: Color(0xFFE2DDD5),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2A2623),
    onInverseSurface: Color(0xFFF5F1EA),
    inversePrimary: Color(0xFFF5A27F),
  );

  @override
  ColorScheme get darkScheme => const ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFEF8558),
    onPrimary: Color(0xFF2A1208),
    primaryContainer: Color(0xFF5A2A17),
    onPrimaryContainer: Color(0xFFFFDBCB),
    secondary: Color(0xFFB5ACA2),
    onSecondary: Color(0xFF1A1816),
    secondaryContainer: Color(0xFF3B3632),
    onSecondaryContainer: Color(0xFFF3EFE9),
    tertiary: Color(0xFF8FB5FF),
    onTertiary: Color(0xFF0E2250),
    tertiaryContainer: Color(0xFF26375A),
    onTertiaryContainer: Color(0xFFD8E4FF),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3B0A06),
    errorContainer: Color(0xFF5C1A16),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF1A1816),
    onSurface: Color(0xFFF3EFE9),
    onSurfaceVariant: Color(0xFFB5ACA2),
    surfaceContainerLowest: Color(0xFF141312),
    surfaceContainerLow: Color(0xFF23201D),
    surfaceContainer: Color(0xFF2D2926),
    surfaceContainerHigh: Color(0xFF332F2B),
    surfaceContainerHighest: Color(0xFF3B3632),
    outline: Color(0xFF857D74),
    outlineVariant: Color(0xFF3B3632),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFEDE8E1),
    onInverseSurface: Color(0xFF2A2623),
    inversePrimary: Color(0xFFA3401E),
  );

  @override
  bool get supportsDarkMode => true;
}
