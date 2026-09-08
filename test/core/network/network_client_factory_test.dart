import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/network/network_client_factory.dart';
import 'package:nai_launcher/core/platform/platform_capabilities.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform ignores desktop proxies without changing TLS or DNS', () {
      final client = _RecordingClient();
      HttpOverrides.runZoned(() {
        final factory = NetworkClientFactory(
          capabilities: PlatformCapabilities.forPlatform(platform),
          desktopProxyAddress: () => throw StateError('Desktop proxy read'),
        );
        final dio = factory.createDio();
        expect(dio.httpClientAdapter, isA<IOHttpClientAdapter>());
        final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
        expect(adapter.createHttpClient!(), same(client));
        expect(
          client.route!(Uri.parse('https://danbooru.donmai.us')),
          'DIRECT',
        );
        expect(client.changedCertificateValidation, isFalse);
        expect(client.changedConnectionFactory, isFalse);
        expect(client.idleTimeout, const Duration(seconds: 3));
        expect(dio.interceptors.whereType<LogInterceptor>(), isEmpty);
        dio.close();
      }, createHttpClient: (_) => client);
    });
  }

  test('desktop explicitly applies and disables the configured proxy', () {
    String? address = ' 127.0.0.1:7890 ';
    final client = _RecordingClient();
    HttpOverrides.runZoned(() {
      NetworkClientFactory(
        capabilities: PlatformCapabilities.forPlatform(TargetPlatform.windows),
        desktopProxyAddress: () => address,
      ).createHttpClient();
      final uri = Uri.parse('https://danbooru.donmai.us');
      expect(client.route!(uri), 'PROXY 127.0.0.1:7890');
      address = null;
      expect(client.route!(uri), 'DIRECT');
      expect(client.changedCertificateValidation, isFalse);
    }, createHttpClient: (_) => client);
  });

  test('standalone desktop clients retain the startup proxy override', () {
    final client = _RecordingClient()..route = (_) => 'PROXY localhost:8888';
    HttpOverrides.runZoned(() {
      NetworkClientFactory(
        capabilities: PlatformCapabilities.forPlatform(TargetPlatform.windows),
      ).createHttpClient();
      expect(
        client.route!(Uri.parse('https://example.test')),
        'PROXY localhost:8888',
      );
    }, createHttpClient: (_) => client);
  });

  test(
    'cancelling before response headers does not poison the next request',
    () async {
      final arrived = Completer<void>();
      final release = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await server.close(force: true);
      });
      server.listen((request) async {
        if (request.uri.path == '/slow') {
          arrived.complete();
          await release.future;
        }
        try {
          request.response.write('ok');
          await request.response.close();
        } on Object {
          // The cancelled request may have already closed its socket.
        }
      });
      final dio = NetworkClientFactory(
        capabilities: PlatformCapabilities.forPlatform(TargetPlatform.android),
        desktopProxyAddress: () => '127.0.0.1:1',
      ).createDio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
      addTearDown(() => dio.close(force: true));
      final base = 'http://${server.address.host}:${server.port}';
      final token = CancelToken();
      final cancelled = expectLater(
        dio.get('$base/slow', cancelToken: token),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      await arrived.future.timeout(const Duration(seconds: 2));
      token.cancel('test');
      await cancelled.timeout(const Duration(seconds: 2));
      expect((await dio.get<String>('$base/next')).data, 'ok');
      release.complete();
    },
  );
}

class _RecordingClient extends Fake implements HttpClient {
  @override
  Duration idleTimeout = Duration.zero;

  String Function(Uri)? route;
  bool changedCertificateValidation = false;
  bool changedConnectionFactory = false;

  @override
  set findProxy(String Function(Uri)? value) => route = value;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? callback,
  ) {
    changedCertificateValidation = true;
  }

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? factory,
  ) {
    changedConnectionFactory = true;
  }

  @override
  void close({bool force = false}) {}
}
