part of '../saved_army_store.dart';

class _SavedArmyState {
  _SavedArmyState(this.armies, this.deletedIds);

  final List<JsonMap> armies;
  final List<String> deletedIds;
}
