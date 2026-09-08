import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/providers/proxy_settings_provider.dart';
import 'network_client_factory.dart';

/// Rebuild service clients when the desktop proxy configuration changes.
/// Mobile currentProxyAddress is always null; the OS owns VPN routing.
final networkClientFactoryProvider = Provider<NetworkClientFactory>((ref) {
  final proxyAddress = ref.watch(currentProxyAddressProvider);
  return NetworkClientFactory(desktopProxyAddress: () => proxyAddress);
});
