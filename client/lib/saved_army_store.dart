import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';

part 'models/saved_army_state.dart';

class SavedArmyStore {
  static const _stateKey = 'saved_armies_state';
  static const _uuid = Uuid();

  Future<_SavedArmyState> _readState() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_stateKey);
    if (value == null) return _SavedArmyState(<JsonMap>[], <String>[]);
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['items'] is! List ||
        decoded['deleted_ids'] is! List) {
      throw const FormatException('Saved armies have an invalid format.');
    }
    final items = decoded['items'] as List;
    final deletedIds = decoded['deleted_ids'] as List;
    if (items.any((item) => item is! Map<String, dynamic>) ||
        deletedIds.any((id) => id is! String)) {
      throw const FormatException('Saved armies have an invalid format.');
    }
    return _SavedArmyState(
      items
          .cast<Map<String, dynamic>>()
          .map((army) => Map<String, dynamic>.from(army))
          .toList(),
      deletedIds.cast<String>().toList(),
    );
  }

  Future<List<JsonMap>> load() async => (await _readState()).armies;

  Future<JsonMap> save({
    required String name,
    required JsonMap army,
    String? id,
  }) async {
    final state = await _readState();
    final armies = state.armies;
    final now = DateTime.now().millisecondsSinceEpoch;
    final record = <String, dynamic>{
      'id': id ?? _uuid.v4(),
      'name': name.trim(),
      'updated_at': now,
      'army': army,
    };
    armies.removeWhere((item) => item['id'] == record['id']);
    armies.add(record);
    if (id != null) {
      state.deletedIds.remove(id);
    }
    await _writeState(armies, state.deletedIds);
    return record;
  }

  Future<void> delete(String id) async {
    final state = await _readState();
    state.armies.removeWhere((army) => army['id'] == id);
    if (!state.deletedIds.contains(id)) {
      state.deletedIds.add(id);
    }
    await _writeState(state.armies, state.deletedIds);
  }

  Future<int> sync(ApiClient api) async {
    final state = await _readState();
    final local = state.armies;
    final deletedIds = state.deletedIds;
    final remote = await api.getSyncedArmies();
    final merged = <String, JsonMap>{};
    for (final army in [...remote, ...local]) {
      final id = army['id']?.toString();
      if (id == null || deletedIds.contains(id)) continue;
      final current = merged[id];
      final updatedAt = (army['updated_at'] as num?)?.toInt() ?? 0;
      final currentUpdatedAt = (current?['updated_at'] as num?)?.toInt() ?? -1;
      if (current == null || updatedAt >= currentUpdatedAt) {
        merged[id] = army;
      }
    }
    final result = merged.values.toList()
      ..sort((left, right) =>
          (right['updated_at'] as num).compareTo(left['updated_at'] as num));
    await api.putSyncedArmies(result, deletedIds: deletedIds);
    await _writeState(result, []);
    return result.length;
  }

  Future<void> _writeState(
    List<JsonMap> armies,
    List<String> deletedIds,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _stateKey,
      jsonEncode({'items': armies, 'deleted_ids': deletedIds}),
    );
    if (!saved) throw StateError('Could not save armies on this device.');
  }
}
