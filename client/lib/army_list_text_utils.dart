import 'api_client.dart';
import 'models/community_export.dart';
import 'models/community_unit.dart';

JsonMap? asJsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

List<JsonMap> asJsonMaps(Object? value) {
  if (value is! List) return [];
  return value.whereType<Map<String, dynamic>>().toList();
}

String? armyItemName(Object? item) {
  final map = asJsonMap(item);
  return map?['name']?.toString() ?? map?['title']?.toString();
}

int? parseArmyInteger(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.replaceAll(',', ''));
  return null;
}

int armyItemPoints(JsonMap item) => parseArmyInteger(item['points']) ?? 0;

String normalizeArmyText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

bool sameArmyName(Object? first, String second) =>
    normalizeArmyText(first?.toString() ?? '') == normalizeArmyText(second);

JsonMap? findArmyItemOrNull(
  List<JsonMap> items,
  String name, {
  String Function(JsonMap)? nameFor,
}) {
  final normalized = normalizeArmyText(name);
  for (final item in items) {
    final itemName = nameFor?.call(item) ?? item['name']?.toString() ?? '';
    if (normalizeArmyText(itemName) == normalized) return item;
  }
  return null;
}

JsonMap findArmyItem(
  List<JsonMap> items,
  String name,
  String kind, {
  String Function(JsonMap)? nameFor,
}) {
  final item = findArmyItemOrNull(items, name, nameFor: nameFor);
  if (item == null) {
    throw FormatException('Could not match $kind “$name” with app data.');
  }
  return item;
}

String armyTacticName(JsonMap tactic) {
  final title = tactic['title']?.toString() ?? '';
  final separator = title.indexOf(' - ');
  return separator < 0 ? title : title.substring(separator + 3);
}

String stripPointsSuffix(String value) => value
    .replaceFirst(
      RegExp(r'\s*\([\d,]+\s*(?:pts?|points?)\)\s*$', caseSensitive: false),
      '',
    )
    .trim();

bool isCommunityUnitReinforced(JsonMap unit, CommunityUnit entry) {
  if (entry.reinforcedSuffix) return true;
  if (entry.count == null) return false;
  final modelCount = parseArmyInteger(unit['modelCount']);
  if (modelCount == null || modelCount <= 0) {
    throw FormatException(
      'Could not determine unit size for “${entry.name}”.',
    );
  }
  if (entry.count == modelCount) return false;
  if (entry.count == modelCount * 2) return true;
  throw FormatException(
    'The pasted model count for “${entry.name}” does not match the app data.',
  );
}

String? communityHeaderValue(CommunityExport draft, String key) {
  final value = draft.headers[key]?.trim();
  if (value == null || value.isEmpty || normalizeArmyText(value) == 'none') {
    return null;
  }
  return value;
}
