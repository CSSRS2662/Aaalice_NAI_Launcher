import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/localization_extension.dart';
import '../providers/image_generation_provider.dart';
import '../widgets/common/app_toast.dart';

/// Writes an image's seed into the generation parameters and leaves the rest
/// alone. Galleries and other pages away from the generation workspace use
/// it, so it confirms with the seed.
void reuseImageSeed(BuildContext context, WidgetRef ref, int? seed) {
  if (seed == null || seed < 0) {
    AppToast.warning(context, context.l10n.toast_imageHasNoMetadata);
    return;
  }
  ref.read(generationParamsNotifierProvider.notifier).updateSeed(seed);
  AppToast.success(context, context.l10n.toast_seedReused('$seed'));
}
