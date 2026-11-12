import 'api_client.dart';

export 'models/builder_unit_type_group.dart';

import 'models/builder_unit_type_group.dart';

List<BuilderUnitTypeGroup> groupBuilderUnitsByType(List<JsonMap> items) {
  const categories = <(String, String, bool)>[
    ('Hero', 'Hero', true),
    ('Infantry', 'Infantry', false),
    ('Cavalry', 'Cavalry', false),
    ('Beast', 'Beast', false),
    ('Monster', 'Monster', false),
    ('War Machine', 'War Machine', false),
    ('Manifestation', 'Manifestation', true),
    ('Faction Terrain', 'Faction Terrain', true),
  ];
  final unmatched = Set<JsonMap>.from(items);
  final groups = <BuilderUnitTypeGroup>[];

  for (final (title, keyword, includeHeroes) in categories) {
    final matches = _matchingUnits(items, keyword, includeHeroes);
    if (matches.isEmpty) continue;
    groups.add(BuilderUnitTypeGroup(title, matches));
    unmatched.removeAll(matches);
  }

  if (unmatched.isNotEmpty) groups.add(_otherUnits(unmatched));
  return groups;
}

List<JsonMap> _matchingUnits(
  List<JsonMap> items,
  String keyword,
  bool includeHeroes,
) {
  final matches = items
      .where((item) => _matchesCategory(item, keyword, includeHeroes))
      .toList(growable: false);
  return _sortByName(matches);
}

bool _matchesCategory(JsonMap choice, String keyword, bool includeHeroes) {
  final referenceKeywords = _unitFromChoice(choice)['referenceKeywords'];
  if (referenceKeywords is! String) return false;
  final keywords =
      referenceKeywords.split(',').map((value) => value.trim()).toSet();
  if (keyword == 'Manifestation') return keywords.contains(keyword);
  if (keywords.contains('Manifestation')) return false;
  if (!includeHeroes && keywords.contains('Hero')) return false;
  return keywords.contains(keyword);
}

BuilderUnitTypeGroup _otherUnits(Set<JsonMap> unmatched) =>
    BuilderUnitTypeGroup('Other', _sortByName(unmatched.toList()));

List<JsonMap> _sortByName(List<JsonMap> items) =>
    items..sort((left, right) => _unitName(left).compareTo(_unitName(right)));

JsonMap _unitFromChoice(JsonMap choice) {
  final unit = choice['unit'];
  return unit is Map<String, dynamic> ? unit : choice;
}

String _unitName(JsonMap choice) =>
    (_unitFromChoice(choice)['name']?.toString() ?? '').toLowerCase();
