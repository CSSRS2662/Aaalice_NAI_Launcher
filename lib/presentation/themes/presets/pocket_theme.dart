/// Pocket Theme - 应用唯一的浅色与深色主题
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/core/theme_composer.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/pocket_palette.dart';
import 'package:nai_launcher/presentation/themes/modules/motion/presets/pocket_motion.dart';
import 'package:nai_launcher/presentation/themes/modules/shape/presets/pocket_shapes.dart';
import 'package:nai_launcher/presentation/themes/modules/typography/presets/pocket_typography.dart';

class PocketTheme {
  const PocketTheme._();

  static const composer = ThemeComposer(
    color: PocketPalette(),
    typography: PocketTypography(),
    shape: PocketShapes(),
    motion: PocketMotion(),
  );

  static ThemeData get light => composer.buildTheme(Brightness.light);
  static ThemeData get dark => composer.buildTheme(Brightness.dark);
}
