import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../platform/platform_capabilities.dart';

/// Shared, abortable transport for NovelAI and online-gallery traffic.
///
/// This layer has no service credentials, headers or retry interceptors.
/// Each service owns a separate Dio and adds only its own API policy.
class NetworkClientFactory {
  NetworkClientFactory({
    PlatformCapabilities? capabilities,
    String? Function()? desktopProxyAddress,
  }) : _capabilities = capabilities ?? PlatformCapabilities.operatingSystem,
       _desktopProxyAddress = desktopProxyAddress;

  final PlatformCapabilities _capabilities;
  final String? Function()? _desktopProxyAddress;

  HttpClient createHttpClient() {
    // Preserve Dio's default idle lifetime used by the generation transport.
    final client = HttpClient()..idleTimeout = const Duration(seconds: 3);
    if (!_capabilities.supportsAppProxy) {
      // DIRECT means no application-level HTTP proxy, NOT bypassing a VPN.
      // DNS, sockets and VPN routing remain under Android/iOS control. Ignore
      // desktop settings/overrides imported from another installation.
      client.findProxy = (_) => 'DIRECT';
    } else if (_desktopProxyAddress != null) {
      client.findProxy = (_) {
        final address = _desktopProxyAddress()?.trim();
        return address == null || address.isEmpty ? 'DIRECT' : 'PROXY $address';
      };
    }
    // Standalone desktop consumers retain the startup HttpOverrides policy.
    // Keep normal TLS validation and system DNS; never pin IPs or accept bad
    // certificates to work around a VPN/network failure.
    return client;
  }

  Dio createDio([BaseOptions? options]) {
    return Dio(options)
      ..httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: createHttpClient,
      );
  }
}
