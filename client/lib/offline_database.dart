import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'json_types.dart';

List<String> _weaponAbilityIds(Object? value) {
  if (value == null) return const [];
  if (value is String) return [value];
  if (value is List) {
    return value.map((id) {
      if (id is! String) {
        throw StateError('Weapon ability ID must be a string.');
      }
      return id;
    }).toList();
  }
  throw StateError('Weapon ability ID must be a string or a list.');
}

List<JsonMap> _deduplicateWeaponAbilities(Iterable<JsonMap> abilities) {
  final indexesByName = <String, int>{};
  final distinct = <JsonMap>[];
  for (final ability in abilities) {
    final name = ability['name'];
    final key = name is String
        ? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
        : '';
    if (key.isEmpty) {
      distinct.add(ability);
      continue;
    }

    final existingIndex = indexesByName[key];
    if (existingIndex == null) {
      indexesByName[key] = distinct.length;
      distinct.add(ability);
    } else if (_hasWeaponAbilityRules(ability) &&
        !_hasWeaponAbilityRules(distinct[existingIndex])) {
      distinct[existingIndex] = ability;
    }
  }
  return distinct;
}

bool _hasWeaponAbilityRules(JsonMap ability) {
  final rules = ability['rules'];
  return rules is String && rules.trim().isNotEmpty;
}

class OfflineDatabaseStore {
  static const _enabledKey = 'offline_database_enabled';
  static const _fileName = 'aos_database.json';
  static JsonMap? _cachedDatabase;

  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  Future<File> _databaseFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<void> cacheAndEnable(JsonMap database) async {
    _validateDatabase(database);
    final file = await _databaseFile();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(database), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(_enabledKey, true);
    if (!saved) throw StateError('Could not enable offline database storage.');
    _cachedDatabase = database;
  }

  Future<void> disableAndRemove() async {
    final preferences = await SharedPreferences.getInstance();
    final file = await _databaseFile();
    final saved = await preferences.setBool(_enabledKey, false);
    if (!saved) throw StateError('Could not disable offline database storage.');
    _cachedDatabase = null;
    if (await file.exists()) await file.delete();
  }

  Future<JsonMap?> readIfEnabled() async {
    if (!await isEnabled()) {
      _cachedDatabase = null;
      return null;
    }
    final cached = _cachedDatabase;
    if (cached != null) return cached;
    final file = await _databaseFile();
    if (!await file.exists()) {
      throw const FormatException('Offline database is enabled but missing.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Offline database has an invalid format.');
    }
    _validateDatabase(decoded);
    _cachedDatabase = decoded;
    return decoded;
  }

  Future<int?> cachedDataVersion() async {
    final database = await readIfEnabled();
    return (database?['metadata'] as Map<String, dynamic>?)?['data_version']
        as int?;
  }

  void _validateDatabase(JsonMap database) {
    final metadata = database['metadata'];
    final data = database['data'];
    if (metadata is! Map<String, dynamic> ||
        metadata['data_version'] is! int ||
        data is! Map<String, dynamic> ||
        data.values.any((rows) => rows is! List)) {
      throw const FormatException('Downloaded database has an invalid format.');
    }
  }
}

class OfflineDatabaseRepository {
  OfflineDatabaseRepository(this.database);

  static const _manifestationsPublicationId =
      '38c85d13-0436-48ac-adb3-1c9319b16d13';

  final JsonMap database;

  JsonMap get metadata =>
      Map<String, dynamic>.from(database['metadata'] as Map);

  List<JsonMap> dataset(String name, {String search = ''}) {
    return _rows(name).where((row) {
      return search.trim().isEmpty ||
          jsonEncode(row).toLowerCase().contains(search.trim().toLowerCase());
    }).toList();
  }

  List<JsonMap> alliances() {
    final items = _rows('faction_keyword')
        .where((row) => row['parentFactionKeywordId'] == null)
        .map((row) {
      final item = Map<String, dynamic>.from(row);
      final name = item['name']?.toString() ?? '';
      if (name.startsWith('Grand Alliance ')) {
        item['name'] = name.substring('Grand Alliance '.length);
      }
      return item;
    }).toList();
    _sortByName(items);
    return items;
  }

  JsonMap factions(String allianceId) {
    final rows = _rows('faction_keyword');
    final allianceName = rows
        .where((row) => row['id'] == allianceId)
        .map((row) => row['name']?.toString() ?? '')
        .firstOrNull;
    final directFactions = rows
        .where((row) => row['parentFactionKeywordId'] == allianceId)
        .toList();
    final grouped = _factionChildren(rows, directFactions, allianceName);
    _sortByName(grouped.factions);
    _sortByName(grouped.armiesOfRenown);
    return {
      'factions': grouped.factions,
      'armies_of_renown': grouped.armiesOfRenown,
    };
  }

  ({
    List<JsonMap> factions,
    List<JsonMap> armiesOfRenown,
  }) _factionChildren(
    List<JsonMap> rows,
    List<JsonMap> directFactions,
    String? allianceName,
  ) {
    final factions = <JsonMap>[];
    final armiesOfRenown = <JsonMap>[];
    for (final faction in directFactions) {
      factions.add(faction);
      for (final child in rows.where(
        (row) => row['parentFactionKeywordId'] == faction['id'],
      )) {
        if (child['armyOfRenown'] == true) {
          armiesOfRenown.add({
            ...child,
            'parentFactionName': faction['name'],
          });
        } else if (allianceName == 'Grand Alliance Destruction' &&
            faction['name'] == 'Orruk Warclans') {
          factions.add(child);
        }
      }
    }
    return (factions: factions, armiesOfRenown: armiesOfRenown);
  }

  List<JsonMap> heroes(
    String factionId, {
    String search = '',
    bool showLegends = false,
  }) {
    final linkedIds = _warscrollIds(factionId)
      ..addAll(_specialHeroIds(factionId));
    final scourgeIds = showLegends ? <String>{} : _scourgeWarscrollIds();
    final items = _rows('warscroll').where((unit) {
      final id = unit['id']?.toString();
      return id != null &&
          linkedIds.contains(id) &&
          !scourgeIds.contains(id) &&
          unit['isSpearhead'] != true &&
          (showLegends || unit['isLegends'] != true) &&
          unit['requiredPrimaryHeroWarscrollId'] == null &&
          _hasReferenceKeyword(unit, 'Hero') &&
          !_hasReferenceKeyword(unit, 'Faction Terrain') &&
          !_hasReferenceKeyword(unit, 'Manifestation') &&
          (search.trim().isEmpty ||
              (unit['name']?.toString().toLowerCase() ?? '')
                  .contains(search.trim().toLowerCase()));
    }).toList();
    _sortByName(items);
    return items;
  }

  JsonMap regimentUnits({
    required String heroId,
    required String factionId,
    bool showLegends = false,
  }) =>
      _buildRegimentChoices(heroId, factionId, showLegends);

  JsonMap _buildRegimentChoices(
    String heroId,
    String factionId,
    bool showLegends,
  ) {
    final factionUnits = _warscrollIds(factionId)
      ..addAll(_specialHeroIds(factionId));
    final required = _requiredRegimentUnits(heroId, showLegends);
    final requiredIds = required.map((unit) => unit['id']?.toString()).toSet();
    final scourgeIds = showLegends ? <String>{} : _scourgeWarscrollIds();
    final options = _regimentOptions(heroId, factionId);
    final items = _availableRegimentChoices(
      factionId,
      factionUnits,
      requiredIds,
      scourgeIds,
      options,
      showLegends,
    );
    return {'required_units': required, 'items': items};
  }

  List<JsonMap> _requiredRegimentUnits(String heroId, bool showLegends) =>
      _rows('warscroll')
          .where((unit) =>
              unit['requiredPrimaryHeroWarscrollId'] == heroId &&
              unit['isSpearhead'] != true &&
              (showLegends || unit['isLegends'] != true))
          .toList();

  List<JsonMap> _regimentOptions(String heroId, String factionId) =>
      _rows('warscroll_regiment_option').where((option) {
        return option['warscrollId'] == heroId &&
            (option['requiredRosterFactionKeywordId'] == null ||
                option['requiredRosterFactionKeywordId'] == factionId);
      }).toList();

  List<JsonMap> _availableRegimentChoices(
    String factionId,
    Set<String> factionUnits,
    Set<String?> requiredIds,
    Set<String> scourgeIds,
    List<JsonMap> options,
    bool showLegends,
  ) {
    final results = <JsonMap>[];
    for (final unit in _rows('warscroll')) {
      final unitId = unit['id']?.toString();
      if (unitId == null ||
          !_isAvailableRegimentUnit(
            unit,
            unitId,
            factionId,
            factionUnits,
            requiredIds,
            scourgeIds,
            showLegends,
          )) {
        continue;
      }
      final choice = _regimentChoice(unit, unitId, factionId, options);
      if (choice != null) results.add(choice);
    }
    return _sortRegimentChoices(results);
  }

  bool _isAvailableRegimentUnit(
    JsonMap unit,
    String unitId,
    String factionId,
    Set<String> factionUnits,
    Set<String?> requiredIds,
    Set<String> scourgeIds,
    bool showLegends,
  ) =>
      factionUnits.contains(unitId) &&
      !requiredIds.contains(unitId) &&
      !scourgeIds.contains(unitId) &&
      unit['isSpearhead'] != true &&
      (showLegends || unit['isLegends'] != true) &&
      !_hasReferenceKeyword(unit, 'Faction Terrain') &&
      !_hasReferenceKeyword(unit, 'Manifestation') &&
      !_isExcludedCityAuxiliary(factionId, unitId);

  JsonMap? _regimentChoice(
    JsonMap unit,
    String unitId,
    String factionId,
    List<JsonMap> options,
  ) {
    for (final option in options) {
      if (!_optionAllowsUnit(option, unit, unitId, factionId)) continue;
      final quantity = option['childQuantity'];
      final optionId = option['id']?.toString();
      return {
        'unit': unit,
        'only_one': quantity != 'any',
        'option_id': quantity == 'any' ? null : optionId,
      };
    }
    return null;
  }

  bool _optionAllowsUnit(
    JsonMap option,
    JsonMap unit,
    String unitId,
    String factionId,
  ) {
    if (!const ['any', 'one', 'zeroToOne'].contains(option['childQuantity'])) {
      return false;
    }
    final requiredFactionId = option['requiredFactionKeywordId'];
    if (requiredFactionId != null &&
        requiredFactionId != factionId &&
        !_hasReferenceKeywordById(unit, requiredFactionId.toString())) {
      return false;
    }
    final requiredWarscrollId = option['requiredWarscrollId'];
    if (requiredWarscrollId != null && requiredWarscrollId != unitId) {
      return false;
    }
    final optionId = option['id']?.toString();
    return optionId != null && _matchesOptionKeywords(unitId, optionId);
  }

  List<JsonMap> _sortRegimentChoices(List<JsonMap> choices) {
    choices.sort((left, right) {
      final leftName = (left['unit'] as JsonMap)['name']?.toString() ?? '';
      final rightName = (right['unit'] as JsonMap)['name']?.toString() ?? '';
      return leftName.toLowerCase().compareTo(rightName.toLowerCase());
    });
    return choices;
  }

  JsonMap warscrollDetails(String warscrollId) {
    final unit =
        _rows('warscroll').where((row) => row['id'] == warscrollId).firstOrNull;
    if (unit == null) throw StateError('Warscroll was not found.');

    return {
      'unit': unit,
      'abilities': _warscrollAbilities(warscrollId),
      'weapons': _warscrollWeapons(warscrollId),
      'additional_characteristics': _additionalCharacteristics(warscrollId),
      'regiment_options': _warscrollRegimentOptions(warscrollId),
    };
  }

  List<JsonMap> _warscrollAbilities(String warscrollId) =>
      _rows('warscroll_ability')
          .where((ability) => ability['warscrollId'] == warscrollId)
          .map((ability) => {
                ...ability,
                'keywords': _rows('warscroll_ability_keyword')
                    .where(
                        (link) => link['warscrollAbilityId'] == ability['id'])
                    .map((link) => _keyword(link['keywordId']))
                    .whereType<JsonMap>()
                    .toList(),
              })
          .toList();

  List<JsonMap> _warscrollWeapons(String warscrollId) {
    final weapons = _rows('warscroll_weapon')
        .where((weapon) => weapon['warscrollId'] == warscrollId)
        .map((weapon) => {
              ...weapon,
              'abilities': _weaponAbilities(weapon['id']),
            })
        .toList();
    weapons.sort(_compareWeapons);
    return weapons;
  }

  List<JsonMap> _weaponAbilities(Object? weaponId) {
    final links = _rows('warscroll_weapon_weapon_ability')
        .where((link) => link['warscrollWeaponId'] == weaponId);
    final ids =
        links.expand((link) => _weaponAbilityIds(link['weaponAbilityId']));
    final abilities = ids
        .map((id) => _rows('weapon_ability')
            .where((ability) => ability['id'] == id)
            .firstOrNull)
        .whereType<JsonMap>();
    return _deduplicateWeaponAbilities(abilities);
  }

  int _compareWeapons(JsonMap left, JsonMap right) {
    int typeOrder(JsonMap weapon) => switch (weapon['type']?.toString()) {
          'ranged' => 0,
          'melee' => 1,
          _ => 2,
        };
    final type = typeOrder(left).compareTo(typeOrder(right));
    if (type != 0) return type;
    return (left['name']?.toString() ?? '')
        .compareTo(right['name']?.toString() ?? '');
  }

  List<JsonMap> _additionalCharacteristics(String warscrollId) =>
      _rows('warscroll_additional_characteristic')
          .where((item) => item['warscrollId'] == warscrollId)
          .toList();

  List<JsonMap> _warscrollRegimentOptions(String warscrollId) =>
      _rows('warscroll_regiment_option')
          .where((item) =>
              item['warscrollId'] == warscrollId &&
              item['hiddenFromReference'] != true)
          .map((option) => {
                ...option,
                'required_keywords': _optionKeywords(
                  'warscroll_regiment_option_required_keyword',
                  option['id'],
                ),
                'excluded_keywords': _optionKeywords(
                  'warscroll_regiment_option_excluded_keyword',
                  option['id'],
                ),
              })
          .toList()
        ..sort((left, right) => ((left['displayOrder'] as num?)?.toInt() ?? 0)
            .compareTo((right['displayOrder'] as num?)?.toInt() ?? 0));

  JsonMap configuration(String factionId) {
    final excludedPublications = _scourgePublicationIds();
    final lores = _configurationLores(factionId, excludedPublications);
    final excludedGroups = _scourgeAbilityGroupIds(excludedPublications);
    final battleTraits = _battleTraits(factionId, excludedGroups);
    final enhancements = _enhancementCollections(factionId, excludedGroups);
    final terrain = _factionTerrain(factionId);
    final formations = _battleFormations(factionId, excludedPublications);
    final regimentsOfRenown = _regimentsOfRenown(factionId);
    _sortFactionConfigurationRows(
      lores,
      terrain,
      formations,
      regimentsOfRenown,
      battleTraits,
      enhancements,
    );
    return _configurationResult(
      lores,
      battleTraits,
      enhancements,
      terrain,
      formations,
      regimentsOfRenown,
    );
  }

  void _sortFactionConfigurationRows(
    ({
      List<JsonMap> spells,
      List<JsonMap> prayers,
      List<JsonMap> manifestations,
    }) lores,
    List<JsonMap> terrain,
    List<JsonMap> formations,
    List<JsonMap> regimentsOfRenown,
    List<JsonMap> battleTraits,
    ({
      List<JsonMap> artefacts,
      List<JsonMap> traits,
      List<JsonMap> other,
    }) enhancements,
  ) {
    _sortConfigurationRows([
      lores.spells,
      lores.prayers,
      lores.manifestations,
      terrain,
      formations,
      regimentsOfRenown,
      battleTraits,
      enhancements.artefacts,
      enhancements.traits,
      enhancements.other,
    ]);
  }

  JsonMap _configurationResult(
    ({
      List<JsonMap> spells,
      List<JsonMap> prayers,
      List<JsonMap> manifestations,
    }) lores,
    List<JsonMap> battleTraits,
    ({
      List<JsonMap> artefacts,
      List<JsonMap> traits,
      List<JsonMap> other,
    }) enhancements,
    List<JsonMap> terrain,
    List<JsonMap> formations,
    List<JsonMap> regimentsOfRenown,
  ) =>
      {
        'battle_traits': battleTraits,
        'battle_formations': formations,
        'spell_lores': lores.spells,
        'prayer_lores': lores.prayers,
        'manifestation_lores': lores.manifestations,
        'regiments_of_renown': regimentsOfRenown,
        'terrain': terrain,
        'enhancements': {
          'artefacts': enhancements.artefacts,
          'heroic_traits': enhancements.traits,
          'other': enhancements.other,
        },
      };

  ({
    List<JsonMap> spells,
    List<JsonMap> prayers,
    List<JsonMap> manifestations,
  }) _configurationLores(
    String factionId,
    Set<String> excludedPublications,
  ) {
    final spells = <JsonMap>[];
    final prayers = <JsonMap>[];
    final manifestations = _rows('lore')
        .where((lore) => lore['factionId'] == null)
        .map((lore) => _loreWithAbilities(lore, includeWarscrolls: true))
        .toList();
    final factionLores = _rows('lore').where((lore) =>
        lore['factionId'] == factionId &&
        !_isScourge(lore, excludedPublications));
    for (final lore in factionLores) {
      _appendFactionLore(lore, spells, prayers, manifestations);
    }
    return (
      spells: spells,
      prayers: prayers,
      manifestations: manifestations,
    );
  }

  void _appendFactionLore(
    JsonMap lore,
    List<JsonMap> spells,
    List<JsonMap> prayers,
    List<JsonMap> manifestations,
  ) {
    final name = lore['name']?.toString() ?? '';
    if (_isSpellLore(name)) {
      spells.add(_loreWithAbilities(lore));
    } else if (_isPrayerLore(name)) {
      prayers.add(_loreWithAbilities(lore));
    } else {
      manifestations.insert(
        0,
        _loreWithAbilities(lore, includeWarscrolls: true),
      );
    }
  }

  bool _isSpellLore(String name) =>
      _containsAny(name, const ['Lore of', 'Spell Lore', 'Arcane']) &&
      !_containsAny(name, const [
        'Lore of the Abyss',
        'Lore of Virulence',
        'Lore of the Spirit-Song',
        'Lore of the Everwinter',
        "Brodd's Bellows",
      ]);

  bool _isPrayerLore(String name) => _containsAny(name, const [
        'Prayer',
        'Bless',
        'Rites',
        'Warbeats',
        'Scriptures',
        'Benedictions',
        'Gifts',
        'Lore of Virulence',
        'Lore of the Spirit-Song',
        'Proclamations',
        'Lore of the Everwinter',
        "Brodd's Bellows",
      ]);

  List<JsonMap> _battleTraits(String factionId, Set<String> excludedGroups) {
    final battleTraits = _rows('ability_group')
        .where((group) =>
            group['factionId'] == factionId &&
            group['abilityGroupType'] == 'battleTraits' &&
            group['isLegends'] != true &&
            !excludedGroups.contains(group['id']))
        .map((group) => {
              ..._withPublicationBackgroundImage(group),
              'abilities': _rows('ability')
                  .where((ability) => ability['abilityGroupId'] == group['id'])
                  .map(_abilityWithKeywords)
                  .map(_withPublicationBackgroundImage)
                  .toList(),
            })
        .toList();
    if (battleTraits.length > 1) {
      battleTraits.removeWhere((group) => group['restrictionText'] == null);
    }
    return battleTraits;
  }

  ({
    List<JsonMap> artefacts,
    List<JsonMap> traits,
    List<JsonMap> other,
  }) _enhancementCollections(String factionId, Set<String> excludedGroups) {
    final groups = _rows('ability_group').where((group) =>
        group['factionId'] == factionId &&
        !excludedGroups.contains(group['id']));
    final artefacts = <JsonMap>[];
    final traits = <JsonMap>[];
    final other = <JsonMap>[];
    for (final group in groups) {
      _appendEnhancementGroup(group, artefacts, traits, other);
    }
    return (artefacts: artefacts, traits: traits, other: other);
  }

  void _appendEnhancementGroup(
    JsonMap group,
    List<JsonMap> artefacts,
    List<JsonMap> traits,
    List<JsonMap> other,
  ) {
    final abilities = _groupAbilitiesWithKeywords(group['id']);
    switch (group['abilityGroupType']) {
      case 'artefactsOfPower':
        artefacts.addAll(abilities);
        break;
      case 'heroicTraits':
        traits.addAll(abilities);
        break;
      case 'otherEnhancements':
        other.add(_otherEnhancementGroup(group, abilities));
        break;
    }
  }

  List<JsonMap> _groupAbilitiesWithKeywords(Object? groupId) => _rows('ability')
      .where((ability) => ability['abilityGroupId'] == groupId)
      .map(_abilityWithKeywords)
      .toList();

  JsonMap _otherEnhancementGroup(
    JsonMap group,
    List<JsonMap> abilities,
  ) =>
      {
        ...group,
        'abilities': abilities,
        'required_keywords': _abilityGroupKeywordNames(
          'ability_group_required_keyword',
          group['id']?.toString(),
        ),
        'excluded_keywords': _abilityGroupKeywordNames(
          'ability_group_excluded_keyword',
          group['id']?.toString(),
        ),
        'required_warscroll_ids': _requiredEnhancementWarscrollIds(group['id']),
      };

  List<String> _requiredEnhancementWarscrollIds(Object? groupId) =>
      _rows('ability_group_required_warscroll')
          .where((link) => link['abilityGroupId'] == groupId)
          .map((link) => link['warscrollId']?.toString())
          .whereType<String>()
          .toList();

  List<JsonMap> _factionTerrain(String factionId) {
    final linkedWarscrolls = _warscrollIds(factionId);
    return _rows('warscroll')
        .where((unit) =>
            linkedWarscrolls.contains(unit['id']) &&
            unit['isSpearhead'] != true &&
            unit['isLegends'] != true &&
            (unit['referenceKeywords']?.toString().contains('Terrain') ??
                false))
        .toList();
  }

  List<JsonMap> _battleFormations(
    String factionId,
    Set<String> excludedPublications,
  ) =>
      _rows('battle_formation')
          .where((formation) =>
              formation['factionId'] == factionId &&
              !_isScourge(formation, excludedPublications))
          .map((formation) => {
                ..._withPublicationBackgroundImage(formation),
                'abilities': _rows('battle_formation_rule')
                    .where(
                        (rule) => rule['battleFormationId'] == formation['id'])
                    .toList(),
              })
          .toList();

  List<JsonMap> _regimentsOfRenown(String factionId) {
    final permittedRegimentIds = _permittedRegimentIds(factionId);
    return _rows('ability_group')
        .where((group) =>
            group['abilityGroupType'] == 'regimentOfRenown' &&
            group['isLegends'] != true &&
            permittedRegimentIds.contains(group['id']))
        .map(_regimentOfRenownDetails)
        .toList();
  }

  Set<Object?> _permittedRegimentIds(String factionId) => _rows(
        'ability_group_regiment_of_renown_permitted_faction_keyword',
      )
          .where((link) => link['factionKeywordId'] == factionId)
          .map((link) => link['abilityGroupId'])
          .toSet();

  JsonMap _regimentOfRenownDetails(JsonMap group) => {
        ...group,
        'abilities': _abilityGroupAbilities(group['id']),
        'units': _linkedRegimentWarscrolls(group['id']),
      };

  List<JsonMap> _linkedRegimentWarscrolls(Object? groupId) =>
      _rows('ability_group_regiment_of_renown_linked_warscroll')
          .where((link) => link['abilityGroupId'] == groupId)
          .map(_regimentWarscrollLink)
          .toList();

  JsonMap _regimentWarscrollLink(JsonMap link) {
    final warscroll = _rows('warscroll')
        .where((unit) => unit['id'] == link['warscrollId'])
        .firstOrNull;
    return {...link, if (warscroll != null) 'warscroll': warscroll};
  }

  void _sortConfigurationRows(List<List<JsonMap>> collections) {
    for (final rows in collections) {
      _sortByName(rows);
    }
  }

  List<JsonMap> auxiliaryUnits(String factionId, {bool showLegends = false}) {
    final linkedIds = _warscrollIds(factionId);
    final items = _rows('warscroll').where((unit) {
      final id = unit['id']?.toString();
      return id != null &&
          linkedIds.contains(id) &&
          unit['isSpearhead'] != true &&
          (showLegends || unit['isLegends'] != true) &&
          ((unit['points'] as num?)?.toInt() ?? 0) > 0;
    }).toList();
    _sortByName(items);
    return items;
  }

  List<JsonMap> tactics() {
    final items = _rows('rule_container')
        .where((item) =>
            item['ruleSectionId'] == '03e7448e-15e4-498c-b5c8-971ec5224757' &&
            (item['title']?.toString().contains('Battle Tactics Card') ??
                false))
        .map((item) => {
              ...item,
              'components': _ruleComponents(item['id']),
            })
        .toList();
    items.sort((left, right) => (left['title']?.toString() ?? '')
        .compareTo(right['title']?.toString() ?? ''));
    return items;
  }

  JsonMap rulesCatalog() {
    final catalog = _rulesCatalogBase();
    final regiments = _ruleCatalogRegiments();
    final regimentLinks = _ruleCatalogRegimentLinks(regiments);
    final manifestationLores = _manifestationLores();
    final manifestationAbilities = _manifestationAbilities(manifestationLores);
    final manifestationLinks = _manifestationLinks(manifestationAbilities);
    return {
      ...catalog,
      'regimentsOfRenown': regiments,
      'regimentLinks': regimentLinks,
      'manifestationLores': manifestationLores,
      'manifestationAbilities': manifestationAbilities,
      'manifestationLinks': manifestationLinks,
      'warscrolls': _ruleCatalogWarscrolls(regimentLinks, manifestationLinks),
    };
  }

  JsonMap _rulesCatalogBase() {
    return {
      'publications': _catalogPublications(),
      'publicationGroups': _catalogPublicationGroups(),
      'publicationGroupLinks': _rows('publication_publication_group'),
      'factions': _catalogFactions(),
      'sections': _catalogSections(),
    };
  }

  List<JsonMap> _catalogPublications() => _projectRows('publication', [
        'id',
        'name',
        'backgroundImage',
        'factionKeywordId',
        'hiddenFromSearch',
      ]);

  List<JsonMap> _catalogPublicationGroups() => _projectRows(
        'publication_group',
        ['id', 'name', 'displayOrder', 'parentPublicationGroupId'],
      );

  List<JsonMap> _catalogFactions() => _projectRows('faction_keyword', [
        'id',
        'name',
        'parentFactionKeywordId',
        'armyOfRenown',
        'isLegends',
        'factionHeaderImage',
      ]);

  List<JsonMap> _catalogSections() => _projectRows(
        'rule_section',
        ['id', 'name', 'displayOrder', 'publicationId', 'parentId'],
      );

  List<JsonMap> _projectRows(String table, List<String> fields) => _rows(table)
      .map((row) => {
            for (final field in fields)
              if (row.containsKey(field)) field: row[field],
          })
      .toList();

  List<JsonMap> _ruleCatalogRegiments() => _rows('ability_group')
      .where((group) =>
          group['abilityGroupType'] == 'regimentOfRenown' &&
          group['isLegends'] != true)
      .map((group) => {
            for (final field in [
              'id',
              'name',
              'image',
              'regimentOfRenownPointsCost',
              'regimentOfRenownRowImageWarscrollId',
              'subsectionLore',
              'subsectionRulesText',
            ])
              if (group.containsKey(field)) field: group[field],
            'abilities': _abilityGroupAbilities(group['id']),
          })
      .toList();

  List<JsonMap> _ruleCatalogRegimentLinks(List<JsonMap> regiments) {
    final regimentIds = regiments.map((group) => group['id']).toSet();
    return _projectRows(
      'ability_group_regiment_of_renown_linked_warscroll',
      ['abilityGroupId', 'warscrollId', 'minCount', 'maxCount'],
    ).where((link) => regimentIds.contains(link['abilityGroupId'])).toList();
  }

  List<JsonMap> _manifestationLores() => _projectRows('lore', [
        'id',
        'name',
        'publicationId',
        'factionId',
        'points',
      ])
          .where(
              (lore) => lore['publicationId'] == _manifestationsPublicationId)
          .toList();

  List<JsonMap> _manifestationAbilities(List<JsonMap> lores) {
    final loreIds = lores.map((lore) => lore['id']).toSet();
    return _projectRows('lore_ability', [
      'id',
      'loreId',
      'name',
      'castingValue',
      'cost',
      'phaseDetails',
      'declare',
      'usedBy',
      'effect',
      'altText',
      'additionalRulesText',
      'rules',
    ]).where((ability) => loreIds.contains(ability['loreId'])).toList();
  }

  List<JsonMap> _manifestationLinks(List<JsonMap> abilities) {
    final abilityIds = abilities.map((ability) => ability['id']).toSet();
    return _projectRows(
      'lore_ability_linked_warscroll',
      ['loreAbilityId', 'warscrollId'],
    ).where((link) => abilityIds.contains(link['loreAbilityId'])).toList();
  }

  List<JsonMap> _ruleCatalogWarscrolls(
    List<JsonMap> regimentLinks,
    List<JsonMap> manifestationLinks,
  ) {
    final warscrollIds = {
      ...regimentLinks.map((link) => link['warscrollId']),
      ...manifestationLinks.map((link) => link['warscrollId']),
    };
    return _rows('warscroll')
        .where((warscroll) =>
            warscroll['isLegends'] == true ||
            warscrollIds.contains(warscroll['id']))
        .map(_projectRuleCatalogWarscroll)
        .toList();
  }

  JsonMap _projectRuleCatalogWarscroll(JsonMap warscroll) => {
        for (final field in const [
          'id',
          'name',
          'points',
          'rowImage',
          'bannerImage',
          'referenceKeywords',
          'isLegends',
          'modelCount',
          'baseSize',
          'subsectionLore',
          'subsectionRulesText',
          'lore',
          'regimentOfRenownPointsCost',
        ])
          if (warscroll.containsKey(field)) field: warscroll[field],
      };

  JsonMap rulesSection(String sectionId) {
    final rules = _rows('rule_container')
        .where((rule) => rule['ruleSectionId'] == sectionId)
        .map((rule) => {
              ...rule,
              'components': _ruleComponents(rule['id']),
            })
        .toList()
      ..sort((left, right) => ((left['displayOrder'] as num?)?.toInt() ?? 0)
          .compareTo((right['displayOrder'] as num?)?.toInt() ?? 0));
    return {'rules': rules};
  }

  List<JsonMap> rulesFactionWarscrolls(String factionId) {
    final faction = _findFaction(factionId);
    final warscrolls = _eligibleFactionWarscrolls(faction, factionId);
    _sortByName(warscrolls);
    return warscrolls;
  }

  JsonMap _findFaction(String factionId) {
    final faction = _rows('faction_keyword')
        .where((row) => row['id'] == factionId)
        .firstOrNull;
    if (faction == null) {
      throw StateError('Faction was not found.');
    }
    return faction;
  }

  List<JsonMap> _eligibleFactionWarscrolls(
    JsonMap faction,
    String factionId,
  ) {
    final warscrollIds = _warscrollIds(factionId);
    final scourgeIds =
        faction['isLegends'] == true ? <String>{} : _scourgeWarscrollIds();
    return _rows('warscroll')
        .where((warscroll) =>
            _isFactionWarscroll(warscroll, faction, warscrollIds, scourgeIds))
        .map(_projectFactionWarscroll)
        .toList();
  }

  bool _isFactionWarscroll(
    JsonMap warscroll,
    JsonMap faction,
    Set<String> warscrollIds,
    Set<String> scourgeIds,
  ) {
    final id = warscroll['id']?.toString();
    return id != null &&
        warscrollIds.contains(id) &&
        warscroll['isSpearhead'] != true &&
        (faction['isLegends'] == true || warscroll['isLegends'] != true) &&
        !scourgeIds.contains(id);
  }

  JsonMap _projectFactionWarscroll(JsonMap warscroll) => {
        for (final field in const [
          'id',
          'name',
          'points',
          'rowImage',
          'bannerImage',
          'referenceKeywords',
          'isLegends',
          'modelCount',
          'baseSize',
        ])
          if (warscroll.containsKey(field)) field: warscroll[field],
      };

  JsonMap _loreWithAbilities(
    JsonMap lore, {
    bool includeWarscrolls = false,
  }) {
    final abilities = _loreAbilities(lore);
    if (!includeWarscrolls) {
      return {
        ..._withPublicationBackgroundImage(lore),
        'abilities': abilities,
      };
    }
    return {
      ...lore,
      'abilities': _summonedWarscrolls(abilities),
    };
  }

  List<JsonMap> _loreAbilities(JsonMap lore) => _rows('lore_ability')
      .where((item) => item['loreId'] == lore['id'])
      .map(_loreAbilityWithKeywords)
      .toList();

  List<JsonMap> _summonedWarscrolls(List<JsonMap> abilities) {
    final abilityIds = abilities.map((item) => item['id']).toSet();
    return _rows('lore_ability_linked_warscroll')
        .where((link) => abilityIds.contains(link['loreAbilityId']))
        .map((link) => _summonedWarscroll(link, abilities))
        .whereType<JsonMap>()
        .toList();
  }

  JsonMap? _summonedWarscroll(
    JsonMap link,
    List<JsonMap> abilities,
  ) {
    final summonAbility = abilities
        .where((ability) => ability['id'] == link['loreAbilityId'])
        .firstOrNull;
    final warscroll = _rows('warscroll')
        .where((unit) => unit['id'] == link['warscrollId'])
        .firstOrNull;
    if (summonAbility == null || warscroll == null) return null;
    return {...warscroll, 'summonAbility': summonAbility};
  }

  JsonMap _withPublicationBackgroundImage(JsonMap item) {
    final publicationId = item['publicationId'];
    if (publicationId == null) return item;
    final publication = _rows('publication')
        .where((row) => row['id'] == publicationId)
        .firstOrNull;
    final image = publication?['backgroundImage'];
    if (image is! String || image.trim().isEmpty) return item;
    return {...item, 'backgroundImage': image};
  }

  List<JsonMap> _rows(String table) {
    final data = database['data'];
    if (data is! Map<String, dynamic>) return [];
    final rows = data[table];
    if (rows is! List) return [];
    return rows.whereType<JsonMap>().toList(growable: false);
  }

  List<String> _abilityGroupKeywordNames(String table, String? groupId) {
    if (groupId == null) return [];
    final keywordNames = {
      for (final keyword in _rows('keyword'))
        if (keyword['id'] is String && keyword['name'] is String)
          keyword['id'] as String: keyword['name'] as String,
    };
    return _rows(table)
        .where((link) => link['abilityGroupId'] == groupId)
        .map((link) => keywordNames[link['keywordId']])
        .whereType<String>()
        .toList();
  }

  Set<String> _warscrollIds(String factionId) {
    return _rows('warscroll_faction_keyword')
        .where((row) => row['factionKeywordId'] == factionId)
        .map((row) => row['warscrollId']?.toString())
        .whereType<String>()
        .toSet();
  }

  Set<String> _scourgePublicationIds() {
    return _rows('publication_publication_group')
        .where((row) =>
            row['publicationGroupId'] == '292d6e8e-a50d-4a5c-bd5f-70f85110c7f0')
        .map((row) => row['publicationId']?.toString())
        .whereType<String>()
        .toSet();
  }

  Set<String> _scourgeWarscrollIds() {
    final publicationIds = _scourgePublicationIds();
    final warscrollPublicationIds = _rows('warscroll_publication')
        .where((row) => publicationIds.contains(row['publicationId']))
        .map((row) => row['warscrollId']?.toString())
        .whereType<String>()
        .toSet();
    return warscrollPublicationIds;
  }

  Set<String> _scourgeAbilityGroupIds(Set<String> publicationIds) {
    return _rows('ability_group_publication')
        .where((row) => publicationIds.contains(row['publicationId']))
        .map((row) => row['abilityGroupId']?.toString())
        .whereType<String>()
        .toSet();
  }

  bool _isScourge(JsonMap row, Set<String> publicationIds) {
    return publicationIds.contains(row['publicationId']);
  }

  bool _matchesOptionKeywords(String unitId, String optionId) {
    final requiredIds = _rows('warscroll_regiment_option_required_keyword')
        .where((row) => row['warscrollRegimentOptionId'] == optionId)
        .map((row) => row['keywordId'])
        .toList();
    final excludedIds = _rows('warscroll_regiment_option_excluded_keyword')
        .where((row) => row['warscrollRegimentOptionId'] == optionId)
        .map((row) => row['keywordId'])
        .toList();
    final unitKeywords = _rows('warscroll_keyword')
        .where((row) => row['warscrollId'] == unitId)
        .map((row) => row['keywordId'])
        .toSet();
    final unit =
        _rows('warscroll').where((row) => row['id'] == unitId).firstOrNull;
    return unit != null &&
        requiredIds.every((keywordId) =>
            unitKeywords.contains(keywordId) ||
            _canJoinRegimentAsKeyword(unit, keywordId)) &&
        !excludedIds.any(unitKeywords.contains);
  }

  bool _canJoinRegimentAsKeyword(JsonMap unit, Object? keywordId) {
    final keywordName = _keyword(keywordId)?['name'];
    final notes = unit['notes'];
    if (keywordName is! String || notes is! String) return false;
    final requiredNote = _normalizeRuleText(
      'can join an eligible regiment as a $keywordName',
    );
    return _normalizeRuleText(notes).contains(requiredNote);
  }

  String _normalizeRuleText(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  JsonMap? _keyword(Object? keywordId) {
    return _rows('keyword')
        .where((keyword) => keyword['id'] == keywordId)
        .firstOrNull;
  }

  List<JsonMap> _optionKeywords(String table, Object? optionId) {
    return _rows(table)
        .where((link) => link['warscrollRegimentOptionId'] == optionId)
        .map((link) => _keyword(link['keywordId']))
        .whereType<JsonMap>()
        .toList();
  }

  List<JsonMap> _ruleComponents(Object? ruleContainerId) {
    final components = _rows('rule_container_component')
        .where((component) => component['ruleContainerId'] == ruleContainerId)
        .map((component) {
      final ability = _rows('ability')
          .where((item) => item['id'] == component['abilityId'])
          .firstOrNull;
      final tactic = _rows('battle_tactic')
          .where((item) => item['id'] == component['battleTacticId'])
          .firstOrNull;
      final bullets = _rows('bullet_point')
          .where(
              (bullet) => bullet['ruleContainerComponentId'] == component['id'])
          .toList()
        ..sort((left, right) => ((left['displayOrder'] as num?)?.toInt() ?? 0)
            .compareTo((right['displayOrder'] as num?)?.toInt() ?? 0));
      return {
        ...component,
        if (ability != null) 'ability': _abilityWithKeywords(ability),
        if (tactic != null) 'battleTactic': tactic,
        if (component['contentType'] == 'bullets') 'bullets': bullets,
      };
    }).toList();
    components.sort((left, right) =>
        ((left['displayOrder'] as num?)?.toInt() ?? 0)
            .compareTo((right['displayOrder'] as num?)?.toInt() ?? 0));
    return components;
  }

  JsonMap _abilityWithKeywords(JsonMap ability) {
    return {
      ...ability,
      'keywords': _rows('ability_keyword')
          .where((link) => link['abilityId'] == ability['id'])
          .map((link) => _keyword(link['keywordId']))
          .whereType<JsonMap>()
          .toList(),
    };
  }

  List<JsonMap> _abilityGroupAbilities(Object? groupId) {
    final abilities = _rows('ability')
        .asMap()
        .entries
        .where((entry) => entry.value['abilityGroupId'] == groupId)
        .toList();
    abilities.sort((left, right) {
      final order = ((left.value['displayOrder'] as num?)?.toInt() ?? 0)
          .compareTo((right.value['displayOrder'] as num?)?.toInt() ?? 0);
      return order != 0 ? order : left.key.compareTo(right.key);
    });
    return abilities.map((entry) => _abilityWithKeywords(entry.value)).toList();
  }

  JsonMap _loreAbilityWithKeywords(JsonMap ability) {
    return {
      ...ability,
      'keywords': _rows('lore_ability_keyword')
          .where((link) => link['loreAbilityId'] == ability['id'])
          .map((link) => _keyword(link['keywordId']))
          .whereType<JsonMap>()
          .toList(),
    };
  }

  bool _hasReferenceKeyword(JsonMap unit, String keyword) {
    return (unit['referenceKeywords']?.toString() ?? '')
        .split(',')
        .map((item) => item.trim())
        .contains(keyword);
  }

  bool _hasReferenceKeywordById(JsonMap unit, String keywordId) {
    final name = _rows('faction_keyword')
        .where((row) => row['id'] == keywordId)
        .map((row) => row['name']?.toString())
        .firstOrNull;
    return name != null && _hasReferenceKeyword(unit, name);
  }

  bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);

  bool _isExcludedCityAuxiliary(String factionId, String unitId) {
    return const {
          '62f9bb14-f04f-4ec2-895f-abcaec9b0507',
          'f919dae8-4f22-4fb8-86db-8953a8462d47',
        }.contains(factionId) &&
        const {
          '50e64cc9-99c4-4380-b9ef-60a948f9fae9',
          '5aa56cc8-cac2-4a90-8d11-6cb759a07fd8',
        }.contains(unitId);
  }

  Set<String> _specialHeroIds(String factionId) {
    return switch (factionId) {
      '09e28194-8a37-4c3b-aaa5-8aa38bcfd9ac' => {
          '816d2c52-aacc-4f1d-bf50-320665911b97'
        },
      '6f6c097c-91af-4684-a487-2e7402fdb990' => {
          'b6fbb49e-b0c7-417a-8a80-bb95dc344e4f',
          '5bedefb3-4a40-4b3a-9c9d-4e86d97d9c6f',
        },
      _ => <String>{},
    };
  }

  void _sortByName(List<JsonMap> items) {
    items.sort((left, right) => (left['name']?.toString() ?? '')
        .toLowerCase()
        .compareTo((right['name']?.toString() ?? '').toLowerCase()));
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
