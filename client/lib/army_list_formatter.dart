import 'api_client.dart';
import 'army_list_text_utils.dart';

class ArmyListFormatter {
  static String formatSavedArmy(JsonMap record) {
    final army = asJsonMap(record['army']);
    final alliance = asJsonMap(army?['alliance']);
    final faction = asJsonMap(army?['faction']);
    if (army == null || alliance == null || faction == null) {
      throw const FormatException('Saved army data is invalid.');
    }

    final buffer = StringBuffer();
    _writeHeader(buffer, alliance, faction, army);
    _writeRegimentOfRenown(buffer, army);
    _writeRegiments(buffer, army);
    _writeAuxiliaryUnits(buffer, army);
    return buffer.toString();
  }

  static void _writeHeader(
    StringBuffer buffer,
    JsonMap alliance,
    JsonMap faction,
    JsonMap army,
  ) {
    final options = asJsonMap(army['selected_options']) ?? const {};
    final pointsLimit = parseArmyInteger(army['points_limit']) ?? 2000;
    buffer
      ..writeln('Grand Alliance: ${alliance['name'] ?? ''}')
      ..writeln('Faction: ${faction['name'] ?? ''}')
      ..writeln('Points: ${parseArmyInteger(army['total_points']) ?? 0}/$pointsLimit')
      ..writeln(
        'Battle Formation: ${armyItemName(options['battle_formation']) ?? 'None'}',
      )
      ..writeln('Spell Lore: ${armyItemName(options['spell_lore']) ?? 'None'}')
      ..writeln('Prayer Lore: ${armyItemName(options['prayer_lore']) ?? 'None'}')
      ..writeln(
        'Manifestation Lore: '
        '${armyItemName(options['manifestation_lore']) ?? 'None'}',
      )
      ..writeln('Faction Terrain: ${armyItemName(options['terrain']) ?? 'None'}')
      ..writeln(
        'Battle Tactics: '
        '${asJsonMaps(options['tactics']).map(armyTacticName).join(', ')}',
      )
      ..writeln();
  }

  static void _writeRegimentOfRenown(StringBuffer buffer, JsonMap army) {
    final options = asJsonMap(army['selected_options']) ?? const {};
    final regiment = asJsonMap(options['regiment_of_renown']);
    if (regiment == null) return;
    final cost = parseArmyInteger(regiment['regimentOfRenownPointsCost']) ?? 0;
    buffer
      ..writeln(
        'Regiment of Renown: ${armyItemName(regiment) ?? 'Unnamed'} '
        '($cost points)',
      )
      ..writeln();
  }

  static void _writeRegiments(StringBuffer buffer, JsonMap army) {
    final regiments = asJsonMaps(army['regiments']);
    final generalIndex = parseArmyInteger(army['general_index']);
    for (var index = 0; index < regiments.length; index++) {
      _writeRegiment(buffer, regiments[index], index, generalIndex);
    }
  }

  static void _writeRegiment(
    StringBuffer buffer,
    JsonMap regiment,
    int index,
    int? generalIndex,
  ) {
    buffer.writeln('Regiment ${index + 1}');
    if (generalIndex == index) buffer.writeln("General's regiment");
    _writeHero(buffer, asJsonMap(regiment['hero']));
    _writeEnhancement(buffer, 'Artefact', regiment['artefact']);
    _writeEnhancement(buffer, 'Heroic Trait', regiment['heroic_trait']);
    _writeEnhancements(
      buffer,
      regiment['other_enhancements'],
      'Enhancement',
    );
    for (final selected in asJsonMaps(regiment['units'])) {
      _writeSelectedUnit(buffer, selected);
    }
    buffer.writeln();
  }

  static void _writeHero(StringBuffer buffer, JsonMap? hero) {
    if (hero == null) return;
    buffer.writeln('${armyItemName(hero) ?? 'Hero'} (${armyItemPoints(hero)} points)');
  }

  static void _writeEnhancement(
    StringBuffer buffer,
    String label,
    Object? value,
  ) {
    final name = armyItemName(value);
    if (name != null) buffer.writeln('$label: $name');
  }

  static void _writeEnhancements(
    StringBuffer buffer,
    Object? values,
    String label,
  ) {
    for (final enhancement in asJsonMaps(values)) {
      final ability = asJsonMap(enhancement['ability']);
      if (ability != null) {
        buffer.writeln('$label: ${armyItemName(ability) ?? 'Unknown'}');
      }
    }
  }

  static void _writeSelectedUnit(StringBuffer buffer, JsonMap selected) {
    final unit = asJsonMap(selected['warscroll']);
    if (unit == null) return;
    final modelCount = parseArmyInteger(unit['modelCount']);
    final reinforced = selected['reinforced'] == true;
    final count = modelCount == null ? null : modelCount * (reinforced ? 2 : 1);
    final pointCost = armyItemPoints(unit) * (reinforced ? 2 : 1);
    buffer.writeln(
      '${count == null ? '' : '$count x '}${armyItemName(unit) ?? 'Unit'}'
      '${reinforced ? ' (Reinforced)' : ''} ($pointCost points)',
    );
    _writeEnhancements(
      buffer,
      selected['other_enhancements'],
      'Unit Enhancement',
    );
  }

  static void _writeAuxiliaryUnits(StringBuffer buffer, JsonMap army) {
    final units = asJsonMaps(army['auxiliary_units']);
    if (units.isEmpty) return;
    buffer.writeln('Auxiliary Units');
    for (final selected in units) {
      _writeAuxiliaryUnit(buffer, selected);
    }
  }

  static void _writeAuxiliaryUnit(StringBuffer buffer, JsonMap selected) {
    final unit = asJsonMap(selected['warscroll']);
    if (unit == null) return;
    buffer.writeln('${armyItemName(unit) ?? 'Unit'} (${armyItemPoints(unit)} points)');
    _writeEnhancements(
      buffer,
      selected['other_enhancements'],
      'Unit Enhancement',
    );
  }
}
