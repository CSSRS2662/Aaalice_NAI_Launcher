import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_capabilities.dart';
import '../utils/app_logger.dart';

final displayRefreshRateServiceProvider = Provider(
  (ref) => DisplayRefreshRateService(),
);

/// Asks Android for the panel's fastest refresh mode, or hands the choice back
/// to the system. The activity requests the fastest mode at launch; this only
/// changes it later.
class DisplayRefreshRateService {
  DisplayRefreshRateService({
    bool? supported,
    MethodChannel channel = const MethodChannel(
      'com.aaalice.nai_launcher/display',
    ),
  }) : _supported =
           supported ??
           PlatformCapabilities.current.supportsDisplayRefreshRateControl,
       _channel = channel;

  final bool _supported;
  final MethodChannel _channel;

  Future<void> setHighRefreshRate(bool enabled) async {
    if (!_supported) return;
    try {
      final rate = await _channel.invokeMethod<double>('setHighRefreshRate', {
        'enabled': enabled,
      });
      AppLogger.i(
        'High refresh rate ${enabled ? 'on' : 'off'}, display at $rate Hz',
        'DisplayRefreshRate',
      );
    } on PlatformException catch (error) {
      AppLogger.w('Refresh rate request failed: $error', 'DisplayRefreshRate');
    } on MissingPluginException {
      // Older native builds have no channel; nothing to change.
    }
  }
}
