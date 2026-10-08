import 'dart:convert';

import 'package:aos_client/api_client.dart';
import 'package:aos_client/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  tearDown(ApiClient.clearMemoryCache);

  test('reuses API responses across clients for the app session', () async {
    final firstHttpClient = _CountingHttpClient();
    final secondHttpClient = _CountingHttpClient();
    final firstApi = ApiClient(
      httpClient: firstHttpClient,
      baseUrl: 'http://localhost:3000',
    );
    final secondApi = ApiClient(
      httpClient: secondHttpClient,
      baseUrl: 'http://localhost:3000',
    );

    final results = await Future.wait([
      firstApi.builderAlliances(),
      secondApi.builderAlliances(),
    ]);

    expect(firstHttpClient.requestCount, 2);
    expect(secondHttpClient.requestCount, 0);
    expect(results[0], results[1]);
    expect(results.first.single['name'], 'Order');

    ApiClient.clearMemoryCache();
    await secondApi.builderAlliances();
    expect(secondHttpClient.requestCount, 2);

    firstApi.close();
    secondApi.close();
  });

  test('keeps API responses for different query parameters separate', () async {
    final httpClient = _CountingHttpClient();
    final api = ApiClient(
      httpClient: httpClient,
      baseUrl: 'http://localhost:3000',
    );

    await api.factions(search: 'Order');
    await api.factions(search: 'Chaos');
    await api.factions(search: 'Order');

    expect(httpClient.requestCount, 3);
    api.close();
  });

  test('uses offline data after one failed startup availability check',
      () async {
    final httpClient = _UnavailableHttpClient();
    final api = ApiClient(
      httpClient: httpClient,
      baseUrl: 'http://localhost:3000',
      offlineStore: _MemoryOfflineDatabaseStore({
        'metadata': {'data_version': 1},
        'data': {
          'faction_keyword': [
            {
              'id': 'alliance',
              'name': 'Grand Alliance Order',
              'parentFactionKeywordId': null,
            },
            {
              'id': 'order',
              'name': 'Order',
              'parentFactionKeywordId': 'alliance',
            },
          ],
        },
      }),
    );

    expect((await api.builderAlliances()).single['name'], 'Order');
    expect((await api.builderFactions('alliance'))['factions'], isNotEmpty);
    expect(httpClient.requestCount, 1);
    api.close();
  });
}

class _CountingHttpClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    final body = request.url.path.endsWith('/api/v1/health')
        ? {'status': 'ok'}
        : {
            'items': [
              {'id': 'order', 'name': 'Order'},
            ],
          };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
    );
  }
}

class _UnavailableHttpClient extends http.BaseClient {
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    throw http.ClientException('API unavailable');
  }
}

class _MemoryOfflineDatabaseStore extends OfflineDatabaseStore {
  _MemoryOfflineDatabaseStore(this.database);

  final JsonMap database;

  @override
  Future<JsonMap?> readIfEnabled() async => database;
}
