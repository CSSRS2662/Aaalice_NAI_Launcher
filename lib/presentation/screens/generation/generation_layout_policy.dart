import 'package:flutter/widgets.dart';

import '../../../core/platform/platform_capabilities.dart';
import '../../adaptive/window_size_class.dart';

/// Shortest pane, in logical pixels, for which a touch device gets the
/// desktop generation workspaces.
const double minimumTouchDesktopGenerationHeight = 600;

/// Whether the generation page uses a desktop workspace (classic or
/// web-style) for a pane of [size].
///
/// Wide panes normally do. On a touch device ([touchDevice], by default a
/// mobile platform) a pane shorter than [minimumTouchDesktopGenerationHeight]
/// keeps the mobile workbench, which has its own landscape split: a phone held
/// sideways is as wide as a small desktop window but lacks the height the
/// desktop columns need. The observed input modality is not used because it is
/// unknown until the first touch, which would flip the layout after launch.
bool usesDesktopGenerationLayout(Size size, {bool? touchDevice}) =>
    WindowSizeClass.fromWidth(size.width).isExpandedOrWider &&
    !((touchDevice ?? PlatformCapabilities.current.isMobile) &&
        size.height < minimumTouchDesktopGenerationHeight);
