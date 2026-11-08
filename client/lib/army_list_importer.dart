import 'api_client.dart';
import 'army_list_enhancement_resolver.dart';
import 'army_list_parser.dart';
import 'army_list_text_utils.dart';
import 'models/army_list_import_data.dart';
import 'models/community_export.dart';
import 'models/community_regiment.dart';
import 'models/community_unit.dart';

class ArmyListImporter {
  ArmyListImporter(this._api);

  final ApiClient _api;
  final ArmyListEnhancementResolver _enhancementResolver =
      ArmyListEnhancementResolver();

  Future<JsonMap> importText(String text) async {
    final draft = CommunityArmyTextParser().parse(text);
    final data = await _loadData(draft);
    final regiments = await _importRegiments(draft, data);
    final auxiliaryUnits = _importAuxiliaryUnits(draft, data);
    return _buildArmy(draft, data, regiments, auxiliaryUnits);
  }

  Future<ArmyListImportData> _loadData(CommunityExport draft) async {
    final alliances = await _api.builderAlliances();
    final alliance =
        findArmyItem(alliances, draft.allianceName, 'grand alliance');
    final factionData = await _api.builderFactions(alliance['id'].toString());
    final factions = [
      ...asJsonMaps(factionData['factions']),
      ...asJsonMaps(factionData['armies_of_renown']),
    ];
    final faction = findArmyItem(factions, draft.factionName, 'faction');
    final factionId = faction['id'].toString();
    final results = await Future.wait([
      _api.builderConfiguration(factionId),
      _api.builderHeroes(factionId),
      _api.builderAuxiliaryUnits(factionId),
      _api.builderTactics(),
    ]);
    return ArmyListImportData(
      alliance: alliance,
      faction: faction,
      configuration: results[0] as JsonMap,
      heroes: results[1] as List<JsonMap>,
      auxiliaryChoices: results[2] as List<JsonMap>,
      tactics: results[3] as List<JsonMap>,
    );
  }

  Future<List<JsonMap>> _importRegiments(
    CommunityExport draft,
    ArmyListImportData data,
  ) async {
    final regiments = <JsonMap>[];
    for (final regiment in draft.regiments) {
      regiments.add(await _importRegiment(regiment, data));
    }
    return regiments;
  }

  Future<JsonMap> _importRegiment(
    CommunityRegiment draft,
    ArmyListImportData data,
  ) async {
    final heroEntry = _heroEntry(draft);
    final hero = _findHero(data.heroes, heroEntry);
    final unitData = await _regimentUnitData(hero, data);
    return _buildRegiment(draft, heroEntry, hero, unitData, data);
  }

  CommunityUnit _heroEntry(CommunityRegiment draft) {
    if (draft.units.isEmpty) {
      throw const FormatException('A regiment has no listed units.');
    }
    return draft.units.first;
  }

  JsonMap _findHero(List<JsonMap> heroes, CommunityUnit entry) {
    final hero = findArmyItemOrNull(heroes, entry.name);
    if (hero == null) {
      throw const FormatException(
        'The first unit in a regiment must be a hero available to lead it.',
      );
    }
    return hero;
  }

  Future<JsonMap> _regimentUnitData(
    JsonMap hero,
    ArmyListImportData data,
  ) =>
      _api.builderRegimentUnits(
        heroId: hero['id'].toString(),
        factionId: data.faction['id'].toString(),
      );

  JsonMap _buildRegiment(
    CommunityRegiment draft,
    CommunityUnit heroEntry,
    JsonMap hero,
    JsonMap unitData,
    ArmyListImportData data,
  ) {
    final enhancementData = asJsonMap(data.configuration['enhancements']) ?? {};
    final savedUnits = _buildSavedUnits(
      draft.units,
      heroEntry,
      hero['name'],
      asJsonMaps(unitData['required_units']),
      asJsonMaps(unitData['items']),
      enhancementData,
    );
    final enhancements = _enhancementResolver.resolveRegimentEnhancements(
      draft.enhancements,
      enhancementData,
    );
    return _regimentRecord(
      heroEntry,
      hero,
      savedUnits,
      enhancements,
      enhancementData,
    );
  }

  JsonMap _regimentRecord(
    CommunityUnit heroEntry,
    JsonMap hero,
    List<JsonMap> savedUnits,
    JsonMap enhancements,
    JsonMap enhancementData,
  ) {
    return {
      'hero': hero,
      'units': savedUnits,
      'artefact': enhancements['artefact'],
      'heroic_trait': enhancements['heroic_trait'],
      'other_enhancements': _heroEnhancements(
        enhancements,
        heroEntry,
        hero,
        enhancementData,
      ),
    };
  }

  List<JsonMap> _buildSavedUnits(
    List<CommunityUnit> requested,
    CommunityUnit heroEntry,
    Object? heroName,
    List<JsonMap> requiredUnits,
    List<JsonMap> choices,
    JsonMap enhancementData,
  ) {
    final savedUnits = [
      for (final unit in requiredUnits) _savedUnit(unit, required: true),
    ];
    final matchedRequired = <int>{};
    for (final entry in requested) {
      if (identical(entry, heroEntry)) continue;
      final index = _requiredUnitIndex(requiredUnits, entry, matchedRequired);
      if (index >= 0) {
        savedUnits[index] = _buildRequiredUnit(
          requiredUnits[index],
          entry,
          enhancementData,
        );
        matchedRequired.add(index);
        continue;
      }
      final choice = _findUnitChoice(choices, entry, heroName);
      savedUnits.add(_buildChoiceUnit(choice, entry, enhancementData));
    }
    return savedUnits;
  }

  int _requiredUnitIndex(
    List<JsonMap> requiredUnits,
    CommunityUnit entry,
    Set<int> matched,
  ) {
    for (var index = 0; index < requiredUnits.length; index++) {
      if (!matched.contains(index) &&
          sameArmyName(requiredUnits[index]['name'], entry.name)) {
        return index;
      }
    }
    return -1;
  }

  JsonMap _buildRequiredUnit(
    JsonMap unit,
    CommunityUnit entry,
    JsonMap enhancementData,
  ) {
    final saved = _savedUnit(
      unit,
      required: true,
      reinforced: isCommunityUnitReinforced(unit, entry),
    );
    saved['other_enhancements'] = _enhancementResolver.resolveUnitEnhancements(
      entry.enhancements,
      unit,
      enhancementData,
    );
    return saved;
  }

  JsonMap _findUnitChoice(
    List<JsonMap> choices,
    CommunityUnit entry,
    Object? heroName,
  ) {
    for (final candidate in choices) {
      final unit = asJsonMap(candidate['unit']);
      if (unit != null && sameArmyName(unit['name'], entry.name)) {
        return candidate;
      }
    }
    throw FormatException(
      '“${entry.name}” is not available in the regiment of $heroName.',
    );
  }

  JsonMap _buildChoiceUnit(
    JsonMap choice,
    CommunityUnit entry,
    JsonMap enhancementData,
  ) {
    final unit = asJsonMap(choice['unit'])!;
    return {
      ..._savedUnit(
        unit,
        reinforced: isCommunityUnitReinforced(unit, entry),
        onlyOne: choice['only_one'] == true,
        optionId: choice['option_id']?.toString(),
      ),
      'other_enhancements': _enhancementResolver.resolveUnitEnhancements(
        entry.enhancements,
        unit,
        enhancementData,
      ),
    };
  }

  List<JsonMap> _heroEnhancements(
    JsonMap enhancements,
    CommunityUnit heroEntry,
    JsonMap hero,
    JsonMap enhancementData,
  ) =>
      [
        ...asJsonMaps(enhancements['other_enhancements']),
        ..._enhancementResolver.resolveUnitEnhancements(
          heroEntry.enhancements,
          hero,
          enhancementData,
        ),
      ];

  List<JsonMap> _importAuxiliaryUnits(
    CommunityExport draft,
    ArmyListImportData data,
  ) {
    final enhancementData = asJsonMap(data.configuration['enhancements']) ?? {};
    return [
      for (final entry in draft.auxiliaryUnits)
        _buildAuxiliaryUnit(entry, data, enhancementData),
    ];
  }

  JsonMap _buildAuxiliaryUnit(
    CommunityUnit entry,
    ArmyListImportData data,
    JsonMap enhancementData,
  ) {
    final unit = findArmyItem(
      data.auxiliaryChoices,
      entry.name,
      'auxiliary unit',
    );
    return {
      'warscroll': unit,
      'reinforced': isCommunityUnitReinforced(unit, entry),
      'other_enhancements': _enhancementResolver.resolveUnitEnhancements(
        entry.enhancements,
        unit,
        enhancementData,
      ),
    };
  }

  JsonMap _buildArmy(
    CommunityExport draft,
    ArmyListImportData data,
    List<JsonMap> regiments,
    List<JsonMap> auxiliaryUnits,
  ) =>
      {
        'alliance': data.alliance,
        'faction': data.faction,
        'faction_name': data.faction['name']?.toString(),
        'total_points': draft.totalPoints,
        'points_limit': draft.pointsLimit,
        'general_index': _generalIndex(draft.regiments),
        'regiments': regiments,
        'auxiliary_units': auxiliaryUnits,
        'selected_options': _selectedOptions(draft, data),
      };

  int? _generalIndex(List<CommunityRegiment> regiments) {
    final markedIndex = regiments.indexWhere((regiment) => regiment.isGeneral);
    if (markedIndex >= 0) return markedIndex;
    return regiments.isEmpty ? null : 0;
  }

  JsonMap _selectedOptions(CommunityExport draft, ArmyListImportData data) {
    final configuration = data.configuration;
    return {
      'battle_formation': _resolveOption(
          draft, configuration, 'battle formation', 'battle_formations'),
      'spell_lore':
          _resolveOption(draft, configuration, 'spell lore', 'spell_lores'),
      'prayer_lore':
          _resolveOption(draft, configuration, 'prayer lore', 'prayer_lores'),
      'manifestation_lore': _resolveOption(
          draft, configuration, 'manifestation lore', 'manifestation_lores'),
      'terrain':
          _resolveOption(draft, configuration, 'faction terrain', 'terrain'),
      'regiment_of_renown': _resolveOption(
          draft, configuration, 'regiment of renown', 'regiments_of_renown'),
      'tactics': _resolveTactics(
        draft.headers['battle tactics cards'] ??
            draft.headers['battle tactics'],
        data.tactics,
      ),
    };
  }

  JsonMap? _resolveOption(
    CommunityExport draft,
    JsonMap configuration,
    String header,
    String key,
  ) {
    final value = communityHeaderValue(draft, header);
    if (value == null) return null;
    return findArmyItem(asJsonMaps(configuration[key]), value, header);
  }

  List<JsonMap> _resolveTactics(String? value, List<JsonMap> options) {
    if (value == null || value.isEmpty || normalizeArmyText(value) == 'none') {
      return [];
    }
    final names = value
        .split(RegExp(r'\s*(?:,|\band\b)\s*', caseSensitive: false))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);
    return [
      for (final name in names)
        findArmyItem(
          options,
          name,
          'battle tactic',
          nameFor: armyTacticName,
        ),
    ];
  }

  JsonMap _savedUnit(
    JsonMap unit, {
    bool required = false,
    bool reinforced = false,
    bool onlyOne = false,
    String? optionId,
  }) =>
      {
        'warscroll': unit,
        'only_one': onlyOne,
        'option_id': optionId,
        'is_required': required,
        'reinforced': reinforced,
      };
}
