/// Pocket Theme - 应用唯一的浅色与深色主题
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/core/theme_composer.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/pocket_palette.dart';
import 'package:nai_launcher/presentation/themes/modules/motion/presets/pocket_motion.dart';
import 'package:nai_launcher/presentation/themes/modules/shape/presets/pocket_shapes.dart';
import 'package:nai_launcher/presentation/themes/modules/typography/presets/pocket_typography.dart';
import 'package:nai_launcher/presentation/themes/pocket_accent.dart';

class PocketTheme {
  const PocketTheme._();

  static ThemeComposer composer([PocketAccent accent = PocketAccent.fallback]) =>
      ThemeComposer(
        color: PocketPalette(accent: accent),
        typography: const PocketTypography(),
        shape: const PocketShapes(),
        motion: const PocketMotion(),
      );

  static ThemeData build(
    Brightness brightness, [
    PocketAccent accent = PocketAccent.fallback,
  ]) => composer(accent).buildTheme(brightness);

  static ThemeData get light => build(Brightness.light);
  static ThemeData get dark => build(Brightness.dark);
}
