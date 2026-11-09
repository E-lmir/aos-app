import 'dart:convert';

import 'package:http/http.dart' as http;

export 'api_exception.dart';

import 'api_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'json_types.dart';
import 'offline_database.dart';

export 'json_types.dart' show JsonMap;

class ApiClient {
  static const _apiAvailabilityTimeout = Duration(seconds: 3);
  static final Map<String, Future<Object?>> _memoryCache = {};

  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    OfflineDatabaseStore? offlineStore,
  })
      : _httpClient = httpClient ?? http.Client(),
        _offlineStore = offlineStore ?? OfflineDatabaseStore(),
        _baseUri = Uri.parse(
          baseUrl ??
              const String.fromEnvironment(
                'API_BASE_URL',
                defaultValue: 'https://46.17.47.141',
              ),
        );

  final http.Client _httpClient;
  final OfflineDatabaseStore _offlineStore;
  final Uri _baseUri;
  Future<bool>? _apiAvailability;
  Object? _apiAvailabilityError;
  StackTrace? _apiAvailabilityStackTrace;
  JsonMap? _healthResponse;

  static void clearMemoryCache() => _memoryCache.clear();

  Future<bool> checkApiAvailability() =>
      _apiAvailability ??= _probeApiAvailability();

  Future<bool> _probeApiAvailability() async {
    try {
      final response = await _httpClient
          .get(_uri('/api/v1/health'))
          .timeout(_apiAvailabilityTimeout);
      final health = _decodeResponse(response);
      if (health['status'] != 'ok') {
        throw const ApiException('API health check failed.');
      }
      _healthResponse = health;
      return true;
    } on Exception catch (error, stackTrace) {
      _apiAvailabilityError = error;
      _apiAvailabilityStackTrace = stackTrace;
      return false;
    }
  }

  String get _basePath {
    final path = _baseUri.path;
    if (path.isEmpty || path == '/') return '';
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }

  Future<JsonMap> health() async {
    if (await checkApiAvailability()) return _healthResponse!;
    return {'status': 'offline'};
  }

  Future<JsonMap> metadata() => _withOffline(
        _uri('/api/v1/meta').toString(),
        () => _getJson('/api/v1/meta'),
        (repository) {
          final data = repository.database['data'] as Map<String, dynamic>;
          return {
            'data_version': repository.metadata['data_version'],
            'dataset_count': data.length,
            'datasets': {
              for (final entry in data.entries)
                entry.key: (entry.value as List).length,
            },
          };
        },
      );

  Future<List<JsonMap>> builderAlliances() => _withOffline(
        _uri('/api/v1/builder/alliances').toString(),
        () => _getList('/api/v1/builder/alliances', 'items'),
        (repository) => repository.alliances(),
      );

  Future<JsonMap> builderFactions(String allianceId) => _withOffline(
        _uri(
          '/api/v1/builder/alliances/${Uri.encodeComponent(allianceId)}/factions',
        ).toString(),
        () => _getJson(
          '/api/v1/builder/alliances/${Uri.encodeComponent(allianceId)}/factions',
        ),
        (repository) => repository.factions(allianceId),
      );

  Future<List<JsonMap>> builderHeroes(
    String factionId, {
    String search = '',
    bool showLegends = false,
  }) async {
    final uri = _uri(
      '/api/v1/builder/factions/${Uri.encodeComponent(factionId)}/heroes',
      queryParameters: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (showLegends) 'show_legends': 'true',
      },
    );
    return _withOffline(
      uri.toString(),
      () async => _decodeList(await _httpClient.get(uri), 'items'),
      (repository) => repository.heroes(
        factionId,
        search: search,
        showLegends: showLegends,
      ),
    );
  }

  Future<JsonMap> builderRegimentUnits({
    required String heroId,
    required String factionId,
    bool showLegends = false,
  }) {
    final path = '/api/v1/builder/heroes/${Uri.encodeComponent(heroId)}/units';
    final queryParameters = {
      'faction_id': factionId,
      if (showLegends) 'show_legends': 'true',
    };
    final uri = _uri(path, queryParameters: queryParameters);
    return _withOffline(
      uri.toString(),
      () => _getJson(
        path,
        queryParameters: queryParameters,
      ),
      (repository) => repository.regimentUnits(
        heroId: heroId,
        factionId: factionId,
        showLegends: showLegends,
      ),
    );
  }

  Future<JsonMap> builderConfiguration(String factionId) => _withOffline(
        _uri(
          '/api/v1/builder/factions/${Uri.encodeComponent(factionId)}/configuration',
        ).toString(),
        () => _getJson(
          '/api/v1/builder/factions/${Uri.encodeComponent(factionId)}/configuration',
        ),
        (repository) => repository.configuration(factionId),
      );

  Future<JsonMap> builderWarscrollDetails(String warscrollId) => _withOffline(
        _uri(
          '/api/v1/builder/warscrolls/${Uri.encodeComponent(warscrollId)}',
        ).toString(),
        () => _getJson(
          '/api/v1/builder/warscrolls/${Uri.encodeComponent(warscrollId)}',
        ),
        (repository) => repository.warscrollDetails(warscrollId),
      );

  Future<List<JsonMap>> builderAuxiliaryUnits(
    String factionId, {
    bool showLegends = false,
  }) async {
    final uri = _uri(
      '/api/v1/builder/factions/${Uri.encodeComponent(factionId)}/auxiliary-units',
      queryParameters: {if (showLegends) 'show_legends': 'true'},
    );
    return _withOffline(
      uri.toString(),
      () async => _decodeList(await _httpClient.get(uri), 'items'),
      (repository) => repository.auxiliaryUnits(
        factionId,
        showLegends: showLegends,
      ),
    );
  }

  Future<List<JsonMap>> builderTactics() => _withOffline(
        _uri('/api/v1/builder/tactics').toString(),
        () => _getList('/api/v1/builder/tactics', 'items'),
        (repository) => repository.tactics(),
      );

  Future<JsonMap> rulesCatalog() => _withOffline(
        _uri('/api/v1/rules/catalog').toString(),
        () => _getJson('/api/v1/rules/catalog'),
        (repository) => repository.rulesCatalog(),
      );

  Future<List<JsonMap>> rulesFactionWarscrolls(String factionId) {
    final path =
        '/api/v1/rules/factions/${Uri.encodeComponent(factionId)}/warscrolls';
    return _withOffline(
      _uri(path).toString(),
      () => _getList(path, 'items'),
      (repository) => repository.rulesFactionWarscrolls(factionId),
    );
  }

  Future<JsonMap> rulesSection(String sectionId) {
    final path = '/api/v1/rules/sections/${Uri.encodeComponent(sectionId)}';
    return _withOffline(
      _uri(path).toString(),
      () => _getJson(path),
      (repository) => repository.rulesSection(sectionId),
    );
  }

  Future<List<JsonMap>> factions({String search = ''}) async {
    final uri = _uri(
      '/api/v1/datasets/faction_keyword',
      queryParameters: {
        'limit': '100',
        if (search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return _withOffline(
      uri.toString(),
      () async => _decodeList(await _httpClient.get(uri), 'items'),
      (repository) => repository.dataset('faction_keyword', search: search),
    );
  }

  Future<JsonMap> downloadDatabase() => _getJson('/api/v1/database');

  Future<List<JsonMap>> getSyncedArmies() async {
    final response = await _httpClient.get(
      _uri('/api/v1/sync/armies'),
      headers: {'x-device-id': await _deviceId()},
    );
    return _decodeList(response, 'items');
  }

  Future<void> putSyncedArmies(
    List<JsonMap> armies, {
    List<String> deletedIds = const [],
  }) async {
    final response = await _httpClient.put(
      _uri('/api/v1/sync/armies'),
      headers: {
        'content-type': 'application/json',
        'x-device-id': await _deviceId(),
      },
      body: jsonEncode({'items': armies, 'deleted_ids': deletedIds}),
    );
    _decodeResponse(response);
  }

  Future<String> _deviceId() async {
    const key = 'army_sync_device_id';
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(key);
    if (existing != null && _isUuid(existing)) return existing;
    final generated = const Uuid().v4();
    await preferences.setString(key, generated);
    return generated;
  }

  bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  Future<T> _withOffline<T>(
    String cacheKey,
    Future<T> Function() online,
    T Function(OfflineDatabaseRepository) offline,
  ) async {
    final cached = _memoryCache[cacheKey];
    if (cached != null) return await cached as T;

    final request = _loadWithOffline(online, offline);
    _memoryCache[cacheKey] = request;
    var succeeded = false;
    try {
      final result = await request;
      succeeded = true;
      return result;
    } finally {
      if (!succeeded && identical(_memoryCache[cacheKey], request)) {
        _memoryCache.remove(cacheKey);
      }
    }
  }

  Future<T> _loadWithOffline<T>(
    Future<T> Function() online,
    T Function(OfflineDatabaseRepository) offline,
  ) async {
    try {
      if (!await checkApiAvailability()) {
        final error = _apiAvailabilityError;
        final stackTrace = _apiAvailabilityStackTrace;
        if (error != null && stackTrace != null) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        throw const ApiException('API is unavailable.');
      }
      return await online();
    } on Exception {
      final database = await _offlineStore.readIfEnabled();
      if (database == null) rethrow;
      return offline(OfflineDatabaseRepository(database));
    }
  }

  Future<List<JsonMap>> _getList(String path, String key) async {
    return _decodeList(await _httpClient.get(_uri(path)), key);
  }

  List<JsonMap> _decodeList(
    http.Response response,
    String key,
  ) {
    final result = _decodeResponse(response);
    final items = result[key];
    if (items is! List) {
      throw const ApiException('API returned an invalid list.');
    }
    return items.whereType<JsonMap>().toList(growable: false);
  }

  Future<JsonMap> _getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    return _decodeResponse(
      await _httpClient.get(_uri(path, queryParameters: queryParameters)),
    );
  }

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    return _baseUri.replace(
      path: '$_basePath$path',
      queryParameters: queryParameters,
    );
  }

  JsonMap _decodeResponse(http.Response response) {
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const ApiException('API returned invalid JSON.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          decoded is Map<String, dynamic> ? decoded['error']?.toString() : null;
      throw ApiException(
          message ?? 'API request failed (${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('API returned an invalid response.');
    }
    return decoded;
  }

  void close() => _httpClient.close();
}
