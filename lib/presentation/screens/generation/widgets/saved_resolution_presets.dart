import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/nai_resolution_adapter.dart';
import '../../../../data/models/image/resolution_preset.dart';

/// The user's saved sizes that are still valid generation resolutions, in
/// saved order without duplicates. Shared by the parameter panel, which also
/// saves and deletes them, and the workbench header, which only selects.
List<CustomResolutionPreset> loadSavedResolutionPresets(
  LocalStorageService storage,
) {
  final presets = <CustomResolutionPreset>{};
  for (final value in storage.getCustomResolutionPresets()) {
    final preset = CustomResolutionPreset.fromStorageValue(value);
    if (preset != null &&
        NaiResolutionAdapter.validateGenerationResolution(
              preset.width,
              preset.height,
            ) ==
            null) {
      presets.add(preset);
    }
  }
  return presets.toList(growable: false);
}
