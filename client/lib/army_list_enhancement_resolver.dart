import 'api_client.dart';
import 'army_builder_rules.dart';
import 'army_list_text_utils.dart';

class ArmyListEnhancementResolver {
  JsonMap resolveRegimentEnhancements(
    Map<String, String> requested,
    JsonMap enhancementData,
  ) {
    final selections =
        _resolveRequestedEnhancements(requested, enhancementData);
    return {
      'artefact': selections.artefact,
      'heroic_trait': selections.heroicTrait,
      'other_enhancements': selections.other,
    };
  }

  ({
    JsonMap? artefact,
    JsonMap? heroicTrait,
    List<JsonMap> other,
  }) _resolveRequestedEnhancements(
    Map<String, String> requested,
    JsonMap enhancementData,
  ) {
    JsonMap? artefact;
    JsonMap? heroicTrait;
    final other = <JsonMap>[];
    final artefacts = asJsonMaps(enhancementData['artefacts']);
    final traits = asJsonMaps(enhancementData['heroic_traits']);
    final groups = asJsonMaps(enhancementData['other']);
    for (final entry in requested.entries) {
      switch (normalizeArmyText(entry.key)) {
        case 'artefact':
          artefact = findArmyItem(artefacts, entry.value, 'artefact');
          break;
        case 'heroic trait':
          heroicTrait = findArmyItem(traits, entry.value, 'heroic trait');
          break;
        case 'enhancement':
          other.add(_resolveUniqueEnhancement(groups, entry.value));
          break;
        default:
          other.add(_resolveGroupedEnhancement(groups, entry.key, entry.value));
          break;
      }
    }
    return (artefact: artefact, heroicTrait: heroicTrait, other: other);
  }

  List<JsonMap> resolveUnitEnhancements(
    List<String> requested,
    JsonMap unit,
    JsonMap enhancementData,
  ) {
    final groups = asJsonMaps(enhancementData['other']);
    return [
      for (final name in requested) _resolveUnitEnhancement(groups, unit, name),
    ];
  }

  JsonMap _resolveUniqueEnhancement(List<JsonMap> groups, String name) {
    final matches = _matchingAbilities(groups, name);
    if (matches.length != 1) {
      throw FormatException(
        'Could not uniquely match enhancement “$name”.',
      );
    }
    final (group, ability) = matches.single;
    return {'group_id': group['id'], 'ability': ability};
  }

  JsonMap _resolveGroupedEnhancement(
    List<JsonMap> groups,
    String groupName,
    String abilityName,
  ) {
    final group = findArmyItemOrNull(groups, groupName);
    if (group == null) {
      throw FormatException('Unknown enhancement category “$groupName”.');
    }
    final ability = findArmyItem(
      asJsonMaps(group['abilities']),
      abilityName,
      groupName,
    );
    return {'group_id': group['id'], 'ability': ability};
  }

  JsonMap _resolveUnitEnhancement(
    List<JsonMap> groups,
    JsonMap unit,
    String name,
  ) {
    final matches = _matchingAbilities(groups, name, unit: unit);
    if (matches.length != 1) {
      throw FormatException(
        matches.isEmpty
            ? 'Enhancement “$name” is not available for ${unit['name']}.'
            : 'Could not uniquely match enhancement “$name”.',
      );
    }
    final (group, ability) = matches.single;
    return {'group_id': group['id'], 'ability': ability};
  }

  List<(JsonMap, JsonMap)> _matchingAbilities(
    List<JsonMap> groups,
    String name, {
    JsonMap? unit,
  }) {
    final matches = <(JsonMap, JsonMap)>[];
    for (final group in groups) {
      if (unit != null && !enhancementCanBeGivenTo(group, unit)) continue;
      for (final ability in asJsonMaps(group['abilities'])) {
        if (sameArmyName(ability['name'], name)) {
          matches.add((group, ability));
        }
      }
    }
    return matches;
  }
}
