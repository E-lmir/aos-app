import 'api_client.dart';

class BuilderUnitTypeGroup {
  const BuilderUnitTypeGroup(this.title, this.items);

  final String title;
  final List<JsonMap> items;
}

List<BuilderUnitTypeGroup> groupBuilderUnitsByType(List<JsonMap> items) {
  const categories = [
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
    final matches = items.where((item) {
      final unit = _unitFromChoice(item);
      final referenceKeywords = unit['referenceKeywords'];
      if (referenceKeywords is! String) return false;
      final keywords =
          referenceKeywords.split(',').map((value) => value.trim()).toSet();
      if (keyword == 'Manifestation') return keywords.contains(keyword);
      if (keywords.contains('Manifestation')) return false;
      if (!includeHeroes && keywords.contains('Hero')) return false;
      return keywords.contains(keyword);
    }).toList(growable: false);

    if (matches.isNotEmpty) {
      matches
          .sort((left, right) => _unitName(left).compareTo(_unitName(right)));
      groups.add(BuilderUnitTypeGroup(title, matches));
      unmatched.removeAll(matches);
    }
  }

  if (unmatched.isNotEmpty) {
    final others = unmatched.toList()
      ..sort((left, right) => _unitName(left).compareTo(_unitName(right)));
    groups.add(BuilderUnitTypeGroup('Other', others));
  }
  return groups;
}

JsonMap _unitFromChoice(JsonMap choice) {
  final unit = choice['unit'];
  return unit is Map<String, dynamic> ? unit : choice;
}

String _unitName(JsonMap choice) =>
    (_unitFromChoice(choice)['name']?.toString() ?? '').toLowerCase();
