import 'json_types.dart';

bool isUniqueUnit(JsonMap unit) {
  return unit['referenceKeywords']
          ?.toString()
          .split(',')
          .map((keyword) => keyword.trim())
          .contains('Unique') ??
      false;
}

List<JsonMap> availableUniqueUnits(
  Iterable<JsonMap> candidates,
  Iterable<JsonMap> selectedUnits, {
  JsonMap? except,
}) {
  final selectedUniqueIds = <String>{};
  for (final unit in selectedUnits) {
    if (identical(unit, except) || !isUniqueUnit(unit)) continue;
    final id = unit['id']?.toString();
    if (id != null) selectedUniqueIds.add(id);
  }
  return candidates
      .where((unit) =>
          !isUniqueUnit(unit) ||
          !selectedUniqueIds.contains(unit['id']?.toString()))
      .toList();
}

List<JsonMap> duplicateUniqueUnits(Iterable<JsonMap> units) {
  final seenIds = <String>{};
  final duplicates = <JsonMap>[];
  for (final unit in units) {
    if (!isUniqueUnit(unit)) continue;
    final id = unit['id']?.toString();
    if (id != null && !seenIds.add(id)) duplicates.add(unit);
  }
  return duplicates;
}

List<JsonMap> availableUniqueRegimentsOfRenown(
  Iterable<JsonMap> candidates,
  Iterable<JsonMap> selectedUnits,
) {
  return candidates.where((regiment) {
    final regimentUnits = <JsonMap>[
      for (final link in regiment['units'] is List
          ? (regiment['units'] as List).whereType<JsonMap>()
          : <JsonMap>[])
        if (link['warscroll'] is JsonMap) link['warscroll'] as JsonMap,
    ];
    return duplicateUniqueUnits([...selectedUnits, ...regimentUnits]).isEmpty;
  }).toList();
}

bool enhancementCanBeGivenTo(JsonMap enhancementGroup, JsonMap unit) {
  final keywords = (unit['referenceKeywords']?.toString() ?? '')
      .split(',')
      .map((keyword) => keyword.trim().toLowerCase())
      .where((keyword) => keyword.isNotEmpty)
      .toSet();
  final requiredKeywords = _enhancementNames(
    enhancementGroup['required_keywords'],
  );
  final excludedKeywords = _enhancementNames(
    enhancementGroup['excluded_keywords'],
  );
  final requiredWarscrollIds = _enhancementNames(
    enhancementGroup['required_warscroll_ids'],
  );
  final unitId = unit['id']?.toString().toLowerCase();

  if (requiredWarscrollIds.isNotEmpty &&
      (unitId == null || !requiredWarscrollIds.contains(unitId))) {
    return false;
  }
  if (requiredKeywords.isNotEmpty && !requiredKeywords.any(keywords.contains)) {
    return false;
  }
  return !excludedKeywords.any(keywords.contains);
}

List<JsonMap> availableEnhancementChoices(
  JsonMap enhancementGroup,
  Iterable<JsonMap> choices,
  Iterable<JsonMap> selectedAbilities,
) {
  if (!enhancementChoicesAreUnique(enhancementGroup)) {
    return choices.toList();
  }
  final selectedIds = selectedAbilities
      .map((ability) => ability['id']?.toString())
      .whereType<String>()
      .toSet();
  return choices.where((ability) {
    final id = ability['id']?.toString();
    return id != null && !selectedIds.contains(id);
  }).toList();
}

bool enhancementChoicesAreUnique(JsonMap enhancementGroup) {
  return enhancementGroup['uniqueAbilitySelections'] == true ||
      enhancementGroup['name']?.toString().trim().toLowerCase() ==
          'first circle titles';
}

Set<String> _enhancementNames(Object? value) {
  if (value is! List) return {};
  return value
      .map((item) {
        if (item is String) return item;
        if (item is JsonMap) return item['name']?.toString() ?? '';
        return '';
      })
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
}
