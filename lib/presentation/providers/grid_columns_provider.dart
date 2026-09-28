import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../widgets/common/grid_column_count.dart';

/// Screens whose title grids remember their own column count.
///
/// Column density depends on the device's screen, so the values stay local and
/// are not registered with cloud sync.
enum GridColumnsSurface {
  fixedTags(StorageKeys.fixedTagsGridColumns),
  tagLibrary(StorageKeys.tagLibraryGridColumns);

  const GridColumnsSurface(this.storageKey);

  final String storageKey;
}

final gridColumnsProvider =
    NotifierProvider.family<GridColumnsNotifier, int, GridColumnsSurface>(
      GridColumnsNotifier.new,
    );

class GridColumnsNotifier extends FamilyNotifier<int, GridColumnsSurface> {
  @override
  int build(GridColumnsSurface surface) {
    final stored = ref
        .watch(localStorageServiceProvider)
        .getSetting<Object>(surface.storageKey);
    return GridColumnCount.clamp(
      stored is int ? stored : GridColumnCount.fallback,
    );
  }

  void cycle() => set(GridColumnCount.next(state));

  void set(int columns) {
    final next = GridColumnCount.clamp(columns);
    if (next == state) return;
    state = next;
    // Losing the preference only resets the layout on the next launch.
    unawaited(
      ref
          .read(localStorageServiceProvider)
          .setSetting(arg.storageKey, next)
          .catchError(
            (Object error) => AppLogger.w(
              'Failed to save ${arg.storageKey}: $error',
              'GridColumns',
            ),
          ),
    );
  }
}
