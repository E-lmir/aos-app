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
    final factions = <JsonMap>[];
    final armiesOfRenown = <JsonMap>[];
    final rows = _rows('faction_keyword');
    final allianceName = rows
        .where((row) => row['id'] == allianceId)
        .map((row) => row['name']?.toString() ?? '')
        .firstOrNull;
    final directFactions = rows
        .where((row) => row['parentFactionKeywordId'] == allianceId)
        .toList();

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
    _sortByName(factions);
    _sortByName(armiesOfRenown);
    return {'factions': factions, 'armies_of_renown': armiesOfRenown};
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
  }) {
    final factionUnits = _warscrollIds(factionId)
      ..addAll(_specialHeroIds(factionId));
    final required = _rows('warscroll')
        .where((unit) =>
            unit['requiredPrimaryHeroWarscrollId'] == heroId &&
            unit['isSpearhead'] != true &&
            (showLegends || unit['isLegends'] != true))
        .toList();
    final requiredIds = required.map((unit) => unit['id']?.toString()).toSet();
    final scourgeIds = showLegends ? <String>{} : _scourgeWarscrollIds();
    final options = _rows('warscroll_regiment_option').where((option) {
      return option['warscrollId'] == heroId &&
          (option['requiredRosterFactionKeywordId'] == null ||
              option['requiredRosterFactionKeywordId'] == factionId);
    }).toList();
    final results = <JsonMap>[];

    for (final unit in _rows('warscroll')) {
      final unitId = unit['id']?.toString();
      if (unitId == null ||
          !factionUnits.contains(unitId) ||
          requiredIds.contains(unitId) ||
          scourgeIds.contains(unitId) ||
          unit['isSpearhead'] == true ||
          (!showLegends && unit['isLegends'] == true) ||
          _hasReferenceKeyword(unit, 'Faction Terrain') ||
          _hasReferenceKeyword(unit, 'Manifestation') ||
          _isExcludedCityAuxiliary(factionId, unitId)) {
        continue;
      }
      for (final option in options) {
        final quantity = option['childQuantity'];
        if (!const ['any', 'one', 'zeroToOne'].contains(quantity)) continue;
        final requiredFactionId = option['requiredFactionKeywordId'];
        if (requiredFactionId != null &&
            requiredFactionId != factionId &&
            !_hasReferenceKeywordById(unit, requiredFactionId.toString())) {
          continue;
        }
        final requiredWarscrollId = option['requiredWarscrollId'];
        if (requiredWarscrollId != null && requiredWarscrollId != unitId) {
          continue;
        }
        final optionId = option['id']?.toString();
        if (optionId == null || !_matchesOptionKeywords(unitId, optionId)) {
          continue;
        }
        results.add({
          'unit': unit,
          'only_one': quantity != 'any',
          'option_id': quantity == 'any' ? null : optionId,
        });
        break;
      }
    }
    results.sort((left, right) {
      final leftName = (left['unit'] as JsonMap)['name']?.toString() ?? '';
      final rightName = (right['unit'] as JsonMap)['name']?.toString() ?? '';
      return leftName.toLowerCase().compareTo(rightName.toLowerCase());
    });
    return {'required_units': required, 'items': results};
  }

  JsonMap warscrollDetails(String warscrollId) {
    final unit =
        _rows('warscroll').where((row) => row['id'] == warscrollId).firstOrNull;
    if (unit == null) throw StateError('Warscroll was not found.');

    final abilities = _rows('warscroll_ability')
        .where((ability) => ability['warscrollId'] == warscrollId)
        .map((ability) => {
              ...ability,
              'keywords': _rows('warscroll_ability_keyword')
                  .where((link) => link['warscrollAbilityId'] == ability['id'])
                  .map((link) => _keyword(link['keywordId']))
                  .whereType<JsonMap>()
                  .toList(),
            })
        .toList();
    final weapons = _rows('warscroll_weapon')
        .where((weapon) => weapon['warscrollId'] == warscrollId)
        .map((weapon) => {
              ...weapon,
              'abilities': _deduplicateWeaponAbilities(
                _rows('warscroll_weapon_weapon_ability')
                    .where(
                        (link) => link['warscrollWeaponId'] == weapon['id'])
                    .expand(
                      (link) => _weaponAbilityIds(link['weaponAbilityId']),
                    )
                    .map((abilityId) => _rows('weapon_ability')
                        .where((ability) => ability['id'] == abilityId)
                        .firstOrNull)
                    .whereType<JsonMap>(),
              ),
            })
        .toList();
    weapons.sort((left, right) {
      int typeOrder(JsonMap weapon) => switch (weapon['type']?.toString()) {
            'ranged' => 0,
            'melee' => 1,
            _ => 2,
          };

      final type = typeOrder(left).compareTo(typeOrder(right));
      if (type != 0) return type;
      return (left['name']?.toString() ?? '')
          .compareTo(right['name']?.toString() ?? '');
    });
    final additionalCharacteristics =
        _rows('warscroll_additional_characteristic')
            .where((item) => item['warscrollId'] == warscrollId)
            .toList();
    final options = _rows('warscroll_regiment_option')
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

    return {
      'unit': unit,
      'abilities': abilities,
      'weapons': weapons,
      'additional_characteristics': additionalCharacteristics,
      'regiment_options': options,
    };
  }

  JsonMap configuration(String factionId) {
    final excludedPublications = _scourgePublicationIds();
    final factionLores = _rows('lore').where((lore) =>
        lore['factionId'] == factionId &&
        !_isScourge(lore, excludedPublications));
    final spells = <JsonMap>[];
    final prayers = <JsonMap>[];
    final manifestations = _rows('lore')
        .where((lore) => lore['factionId'] == null)
        .map((lore) => _loreWithAbilities(lore, includeWarscrolls: true))
        .toList();

    for (final lore in factionLores) {
      final name = lore['name']?.toString() ?? '';
      if (_containsAny(name, const ['Lore of', 'Spell Lore', 'Arcane']) &&
          !_containsAny(name, const [
            'Lore of the Abyss',
            'Lore of Virulence',
            'Lore of the Spirit-Song',
            'Lore of the Everwinter',
            "Brodd's Bellows",
          ])) {
        spells.add(_loreWithAbilities(lore));
      } else if (_containsAny(name, const [
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
      ])) {
        prayers.add(_loreWithAbilities(lore));
      } else {
        manifestations.insert(
          0,
          _loreWithAbilities(lore, includeWarscrolls: true),
        );
      }
    }

    final excludedGroups = _scourgeAbilityGroupIds(excludedPublications);
    final battleTraits = _rows('ability_group')
        .where((group) =>
            group['factionId'] == factionId &&
            group['abilityGroupType'] == 'battleTraits' &&
            group['isLegends'] != true &&
            !excludedGroups.contains(group['id']))
        .map((group) => {
              ...group,
              'abilities': _rows('ability')
                  .where((ability) => ability['abilityGroupId'] == group['id'])
                  .map(_abilityWithKeywords)
                  .toList(),
            })
        .toList();
    if (battleTraits.length > 1) {
      battleTraits.removeWhere((group) => group['restrictionText'] == null);
    }
    final groups = _rows('ability_group').where((group) =>
        group['factionId'] == factionId &&
        !excludedGroups.contains(group['id']));
    final artefacts = <JsonMap>[];
    final traits = <JsonMap>[];
    final other = <JsonMap>[];
    for (final group in groups) {
      final groupAbilities = _rows('ability')
          .where((ability) => ability['abilityGroupId'] == group['id'])
          .map(_abilityWithKeywords)
          .toList();
      switch (group['abilityGroupType']) {
        case 'artefactsOfPower':
          artefacts.addAll(groupAbilities);
          break;
        case 'heroicTraits':
          traits.addAll(groupAbilities);
          break;
        case 'otherEnhancements':
          other.add({
            ...group,
            'abilities': groupAbilities,
            'required_keywords': _abilityGroupKeywordNames(
              'ability_group_required_keyword',
              group['id']?.toString(),
            ),
            'excluded_keywords': _abilityGroupKeywordNames(
              'ability_group_excluded_keyword',
              group['id']?.toString(),
            ),
            'required_warscroll_ids': _rows(
              'ability_group_required_warscroll',
            )
                .where((link) => link['abilityGroupId'] == group['id'])
                .map((link) => link['warscrollId']?.toString())
                .whereType<String>()
                .toList(),
          });
          break;
      }
    }
    final linkedWarscrolls = _warscrollIds(factionId);
    final terrain = _rows('warscroll')
        .where((unit) =>
            linkedWarscrolls.contains(unit['id']) &&
            unit['isSpearhead'] != true &&
            unit['isLegends'] != true &&
            (unit['referenceKeywords']?.toString().contains('Terrain') ??
                false))
        .toList();
    final formations = _rows('battle_formation')
        .where((formation) =>
            formation['factionId'] == factionId &&
            !_isScourge(formation, excludedPublications))
        .map((formation) => {
              ..._withPublicationBackgroundImage(formation),
              'abilities': _rows('battle_formation_rule')
                  .where((rule) => rule['battleFormationId'] == formation['id'])
                  .toList(),
            })
        .toList();
    final permittedRegimentIds = _rows(
      'ability_group_regiment_of_renown_permitted_faction_keyword',
    )
        .where((link) => link['factionKeywordId'] == factionId)
        .map((link) => link['abilityGroupId'])
        .toSet();
    final regimentsOfRenown = _rows('ability_group')
        .where((group) =>
            group['abilityGroupType'] == 'regimentOfRenown' &&
            group['isLegends'] != true &&
            permittedRegimentIds.contains(group['id']))
        .map((group) => {
              ...group,
              'abilities': _abilityGroupAbilities(group['id']),
              'units':
                  _rows('ability_group_regiment_of_renown_linked_warscroll')
                      .where((link) => link['abilityGroupId'] == group['id'])
                      .map((link) {
                final warscroll = _rows('warscroll')
                    .where((unit) => unit['id'] == link['warscrollId'])
                    .firstOrNull;
                return {
                  ...link,
                  if (warscroll != null) 'warscroll': warscroll,
                };
              }).toList(),
            })
        .toList();
    for (final rows in [
      spells,
      prayers,
      manifestations,
      terrain,
      formations,
      regimentsOfRenown,
      battleTraits,
      artefacts,
      traits,
      other,
    ]) {
      _sortByName(rows);
    }
    return {
      'battle_traits': battleTraits,
      'battle_formations': formations,
      'spell_lores': spells,
      'prayer_lores': prayers,
      'manifestation_lores': manifestations,
      'regiments_of_renown': regimentsOfRenown,
      'terrain': terrain,
      'enhancements': {
        'artefacts': artefacts,
        'heroic_traits': traits,
        'other': other,
      },
    };
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
    List<JsonMap> project(String table, List<String> fields) {
      return _rows(table)
          .map((row) => {
                for (final field in fields)
                  if (row.containsKey(field)) field: row[field],
              })
          .toList();
    }

    final publications = project('publication', [
      'id',
      'name',
      'backgroundImage',
      'factionKeywordId',
      'hiddenFromSearch',
    ]);
    final publicationGroups = project('publication_group', [
      'id',
      'name',
      'displayOrder',
      'parentPublicationGroupId',
    ]);
    final publicationGroupLinks = _rows('publication_publication_group');
    final factions = project('faction_keyword', [
      'id',
      'name',
      'parentFactionKeywordId',
      'armyOfRenown',
      'isLegends',
      'factionHeaderImage',
    ]);
    final sections = project('rule_section', [
      'id',
      'name',
      'displayOrder',
      'publicationId',
      'parentId',
    ]);
    final regiments = _rows('ability_group')
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
    final regimentIds = regiments.map((group) => group['id']).toSet();
    final regimentLinks = project(
      'ability_group_regiment_of_renown_linked_warscroll',
      ['abilityGroupId', 'warscrollId', 'minCount', 'maxCount'],
    ).where((link) => regimentIds.contains(link['abilityGroupId'])).toList();
    final manifestationLores = project('lore', [
      'id',
      'name',
      'publicationId',
      'factionId',
      'points',
    ])
        .where((lore) => lore['publicationId'] == _manifestationsPublicationId)
        .toList();
    final loreIds = manifestationLores.map((lore) => lore['id']).toSet();
    final manifestationAbilities = project('lore_ability', [
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
    final abilityIds =
        manifestationAbilities.map((ability) => ability['id']).toSet();
    final manifestationLinks = project(
      'lore_ability_linked_warscroll',
      ['loreAbilityId', 'warscrollId'],
    ).where((link) => abilityIds.contains(link['loreAbilityId'])).toList();
    final warscrollIds = {
      ...regimentLinks.map((link) => link['warscrollId']),
      ...manifestationLinks.map((link) => link['warscrollId']),
    };
    final warscrolls = _rows('warscroll')
        .where((warscroll) =>
            warscroll['isLegends'] == true ||
            warscrollIds.contains(warscroll['id']))
        .map((warscroll) => {
              for (final field in [
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
            })
        .toList();
    return {
      'publications': publications,
      'publicationGroups': publicationGroups,
      'publicationGroupLinks': publicationGroupLinks,
      'factions': factions,
      'sections': sections,
      'regimentsOfRenown': regiments,
      'regimentLinks': regimentLinks,
      'manifestationLores': manifestationLores,
      'manifestationAbilities': manifestationAbilities,
      'manifestationLinks': manifestationLinks,
      'warscrolls': warscrolls,
    };
  }

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
    final faction = _rows('faction_keyword')
        .where((row) => row['id'] == factionId)
        .firstOrNull;
    if (faction == null) {
      throw StateError('Faction was not found.');
    }
    final warscrollIds = _warscrollIds(factionId);
    final scourgeIds =
        faction['isLegends'] == true ? <String>{} : _scourgeWarscrollIds();
    final warscrolls = _rows('warscroll')
        .where((warscroll) {
          final id = warscroll['id']?.toString();
          return id != null &&
              warscrollIds.contains(id) &&
              warscroll['isSpearhead'] != true &&
              (faction['isLegends'] == true ||
                  warscroll['isLegends'] != true) &&
              !scourgeIds.contains(id);
        })
        .map((warscroll) => {
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
            })
        .toList();
    _sortByName(warscrolls);
    return warscrolls;
  }

  JsonMap _loreWithAbilities(
    JsonMap lore, {
    bool includeWarscrolls = false,
  }) {
    final abilities = _rows('lore_ability')
        .where((item) => item['loreId'] == lore['id'])
        .map(_loreAbilityWithKeywords)
        .toList();
    if (!includeWarscrolls) {
      return {
        ..._withPublicationBackgroundImage(lore),
        'abilities': abilities,
      };
    }
    final abilityIds = abilities.map((item) => item['id']).toSet();
    final warscrolls = _rows('lore_ability_linked_warscroll')
        .where((link) => abilityIds.contains(link['loreAbilityId']))
        .map((link) {
          final summonAbility = abilities
              .where((ability) => ability['id'] == link['loreAbilityId'])
              .firstOrNull;
          final warscroll = _rows('warscroll')
              .where((unit) => unit['id'] == link['warscrollId'])
              .firstOrNull;
          if (summonAbility == null || warscroll == null) return null;
          return {...warscroll, 'summonAbility': summonAbility};
        })
        .whereType<JsonMap>()
        .toList();
    return {
      ...lore,
      'abilities': warscrolls,
    };
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
