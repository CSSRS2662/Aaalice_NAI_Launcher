import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/services/display_refresh_rate_service.dart';
import '../../core/storage/local_storage_service.dart';

/// Whether this device runs at the panel's fastest refresh rate. On by
/// default; a device setting, so it is not cloud-synced.
class HighRefreshRateNotifier extends Notifier<bool> {
  @override
  bool build() {
    final enabled =
        ref
            .read(localStorageServiceProvider)
            .getSetting<bool>(
              StorageKeys.displayHighRefreshRate,
              defaultValue: true,
            ) ??
        true;
    // The activity already asked for the fastest mode at launch.
    if (!enabled) {
      unawaited(
        ref.read(displayRefreshRateServiceProvider).setHighRefreshRate(false),
      );
    }
    return enabled;
  }

  Future<void> set(bool enabled) async {
    if (enabled == state) return;
    state = enabled;
    await ref
        .read(localStorageServiceProvider)
        .setSetting(StorageKeys.displayHighRefreshRate, enabled);
    await ref
        .read(displayRefreshRateServiceProvider)
        .setHighRefreshRate(enabled);
  }
}

final highRefreshRateProvider = NotifierProvider<HighRefreshRateNotifier, bool>(
  HighRefreshRateNotifier.new,
);
