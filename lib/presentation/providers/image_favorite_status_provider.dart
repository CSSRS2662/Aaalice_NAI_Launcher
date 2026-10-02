import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/gallery/gallery_path_utils.dart';

/// Favorite state of saved images, keyed by [galleryFilePathKey].
///
/// Surfaces that show images outside the loaded gallery page (generation
/// preview, history, detail viewer) read it, so a heart filled in one place is
/// filled everywhere. `LocalGalleryNotifier` is the only writer: it records
/// every toggle and loads an image's state on first use.
final imageFavoriteStatusProvider =
    NotifierProvider<ImageFavoriteStatusNotifier, Map<String, bool>>(
      ImageFavoriteStatusNotifier.new,
    );

class ImageFavoriteStatusNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};

  void record(String filePath, bool favorite) {
    final key = galleryFilePathKey(filePath);
    if (state[key] == favorite) return;
    state = {...state, key: favorite};
  }
}
