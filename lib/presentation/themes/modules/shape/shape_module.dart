/// Shape Module - Base Implementation
library;

import 'package:flutter/material.dart';
import 'package:nai_launcher/presentation/themes/core/theme_modules.dart';

export 'presets/pocket_shapes.dart';

/// Base implementation of [ShapeModule].
abstract class BaseShapeModule implements ShapeModule {
  const BaseShapeModule();

  /// Helper to create RoundedRectangleBorder.
  static ShapeBorder roundedShape(double radius) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  }
}
