import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aos_client/saved_army_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final store = SavedArmyStore();

  test('saves, updates, and deletes an army from an empty store', () async {
    final first = await store.save(name: 'First list', army: {'points': 1000});
    expect(first['id'], isNotNull);

    await store.save(
      id: first['id'] as String,
      name: 'Updated list',
      army: {'points': 1500},
    );
    final saved = await store.load();
    expect(saved, hasLength(1));
    expect(saved.single['name'], 'Updated list');
    expect(saved.single['army']['points'], 1500);

    await store.delete(first['id'] as String);
    expect(await store.load(), isEmpty);
  });
}
