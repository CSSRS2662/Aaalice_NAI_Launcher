import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_storage_service.dart';
import '../themes/pocket_accent.dart';

/// 强调色偏好：预设或自定义颜色，随可同步设置一起备份。
class AccentColorNotifier extends Notifier<PocketAccent> {
  @override
  PocketAccent build() {
    final storage = ref.read(localStorageServiceProvider);
    return PocketAccent.fromStorage(storage.getAccentColor());
  }

  Future<void> select(PocketAccent accent) async {
    if (accent == state) return;
    state = accent;
    await ref
        .read(localStorageServiceProvider)
        .setAccentColor(accent.storageValue);
  }
}

final accentColorProvider = NotifierProvider<AccentColorNotifier, PocketAccent>(
  AccentColorNotifier.new,
);
