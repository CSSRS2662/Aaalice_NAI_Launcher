import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_cache_database.dart';
import 'package:nai_launcher/core/autocomplete/danbooru_completion_source.dart';
import 'package:nai_launcher/core/network/dio_client.dart';
import 'package:nai_launcher/core/network/network_client_factory.dart';
import 'package:nai_launcher/core/network/network_client_provider.dart';
import 'package:nai_launcher/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_launcher/data/models/danbooru/danbooru_user.dart';
import 'package:nai_launcher/data/services/danbooru_auth_service.dart';
import 'package:nai_launcher/presentation/providers/online_gallery_dependencies.dart';

void main() {
  test(
    'NAI, galleries, Danbooru auth and completion share transport, not credentials',
    () async {
      final factory = _RecordingFactory();
      final container = ProviderContainer(
        overrides: [
          networkClientFactoryProvider.overrideWithValue(factory),
          danbooruAuthProvider.overrideWith(_TestDanbooruAuth.new),
        ],
      );
      addTearDown(container.dispose);

      for (final dio in [
        container.read(imageGenerationDioClientProvider),
        container.read(dioClientProvider),
      ]) {
        await dio.get(
          'https://image.novelai.net/transport-test',
          options: Options(headers: {'Authorization': 'Bearer test-nai-token'}),
        );
      }
      await container
          .read(onlineGalleryHttpClientProvider)
          .get('https://danbooru.donmai.us/posts.json');
      await container.read(danbooruApiServiceProvider).autocomplete('blue');
      final result = await container
          .read(danbooruCredentialVerifierProvider)
          .verify(
            const DanbooruCredentials(
              username: 'tester',
              apiKey: 'test-danbooru-key',
            ),
          );
      expect(result.$1?.name, 'tester');
      expect(result.$2, isFalse);

      final source = DanbooruCompletionSource(
        clientFactory: factory,
        cache: _MemoryCache(),
      );
      addTearDown(source.dispose);
      await source.relatedTags('blue_eyes');

      expect(factory.clients, hasLength(6));
      expect(factory.clients.toSet(), hasLength(6));
      final requests = factory.adapters
          .expand((adapter) => adapter.requests)
          .toList();
      expect(requests, hasLength(6));
      final nai = requests.where((r) => r.uri.host == 'image.novelai.net');
      expect(
        nai.every((r) => r.headers['Authorization'] == 'Bearer test-nai-token'),
        isTrue,
      );
      final danbooru = requests.where(
        (r) => r.uri.host == 'danbooru.donmai.us',
      );
      expect(
        danbooru.every(
          (r) => !'${r.headers['Authorization']}'.contains('Bearer'),
        ),
        isTrue,
      );
      expect(
        danbooru
            .where((r) => r.uri.path == '/posts.json')
            .single
            .headers['Authorization'],
        isNull,
      );
      expect(
        danbooru
            .where((r) => r.uri.path == '/profile.json')
            .single
            .headers['Authorization'],
        startsWith('Basic '),
      );
      expect(
        factory.adapters[4].closed,
        isTrue,
        reason: 'Verifier must release its temporary client',
      );
      expect(
        factory.clients.last.options.connectTimeout,
        const Duration(seconds: 15),
      );
      expect(
        factory.clients.last.options.receiveTimeout,
        const Duration(seconds: 15),
      );
      source.dispose();
      expect(factory.adapters.last.closed, isTrue);
    },
  );
}

class _TestDanbooruAuth extends DanbooruAuth {
  @override
  DanbooruAuthState build() => const DanbooruAuthState();
}

class _MemoryCache extends AutocompleteCacheDatabase {
  @override
  Future<CachedAutocompletePayload?> getRemote(String key) async => null;

  @override
  Future<void> putRemote(
    String key,
    List<Map<String, dynamic>> payload,
  ) async {}
}

class _RecordingFactory extends NetworkClientFactory {
  final clients = <Dio>[];
  final adapters = <_RecordingAdapter>[];

  @override
  Dio createDio([BaseOptions? options]) {
    final adapter = _RecordingAdapter();
    final dio = super.createDio(options)..httpClientAdapter = adapter;
    clients.add(dio);
    adapters.add(adapter);
    return dio;
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        options.uri.path == '/profile.json' ? {'id': 42, 'name': 'tester'} : [],
      ),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) => closed = true;
}
