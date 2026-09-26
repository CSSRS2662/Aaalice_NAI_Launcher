/// Pocket Typography - Manrope
///
/// 标题靠字重与略收的字距建立层级；正文与标签不额外加字距，
/// 中文字形回退到系统字体，保持中西文混排的节奏一致。
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/presentation/themes/core/theme_modules.dart';

class PocketTypography implements TypographyModule {
  const PocketTypography();

  @override
  String get displayFontFamily => 'Manrope';

  @override
  String get bodyFontFamily => 'Manrope';

  @override
  TextTheme get textTheme {
    final base = GoogleFonts.getFont(bodyFontFamily);
    TextStyle style(double size, FontWeight weight, [double spacing = 0]) =>
        base.copyWith(
          fontSize: size,
          fontWeight: weight,
          letterSpacing: spacing,
        );

    return TextTheme(
      displayLarge: style(57, FontWeight.w600, -1),
      displayMedium: style(45, FontWeight.w600, -0.6),
      displaySmall: style(36, FontWeight.w700, -0.4),
      headlineLarge: style(32, FontWeight.w700, -0.4),
      headlineMedium: style(28, FontWeight.w800, -0.3),
      headlineSmall: style(24, FontWeight.w700, -0.2),
      titleLarge: style(20, FontWeight.w700, -0.1),
      titleMedium: style(16, FontWeight.w700),
      titleSmall: style(14, FontWeight.w700),
      bodyLarge: style(16, FontWeight.w500),
      bodyMedium: style(14, FontWeight.w500),
      bodySmall: style(12, FontWeight.w500),
      labelLarge: style(14, FontWeight.w700),
      labelMedium: style(12, FontWeight.w600),
      labelSmall: style(11, FontWeight.w600, 0.1),
    );
  }
}
