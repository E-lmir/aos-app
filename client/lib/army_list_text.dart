import 'api_client.dart';
import 'army_builder_rules.dart';

class ArmyListText {
  static String formatSavedArmy(JsonMap record) {
    final army = _asMap(record['army']);
    final alliance = _asMap(army?['alliance']);
    final faction = _asMap(army?['faction']);
    if (army == null || alliance == null || faction == null) {
      throw const FormatException('Saved army data is invalid.');
    }
    final options = _asMap(army['selected_options']) ?? const {};
    final pointsLimit = _integer(army['points_limit']) ?? 2000;
    final buffer = StringBuffer()
      ..writeln('Grand Alliance: ${alliance['name'] ?? ''}')
      ..writeln('Faction: ${faction['name'] ?? ''}')
      ..writeln('Points: ${_integer(army['total_points']) ?? 0}/$pointsLimit')
      ..writeln(
        'Battle Formation: ${_name(options['battle_formation']) ?? 'None'}',
      )
      ..writeln('Spell Lore: ${_name(options['spell_lore']) ?? 'None'}')
      ..writeln('Prayer Lore: ${_name(options['prayer_lore']) ?? 'None'}')
      ..writeln(
        'Manifestation Lore: '
        '${_name(options['manifestation_lore']) ?? 'None'}',
      )
      ..writeln('Faction Terrain: ${_name(options['terrain']) ?? 'None'}')
      ..writeln(
        'Battle Tactics: '
        '${_asMaps(options['tactics']).map(_tacticName).join(', ')}',
      )
      ..writeln();

    final regimentOfRenown = _asMap(options['regiment_of_renown']);
    if (regimentOfRenown != null) {
      final cost =
          _integer(regimentOfRenown['regimentOfRenownPointsCost']) ?? 0;
      buffer
        ..writeln(
          'Regiment of Renown: ${_name(regimentOfRenown) ?? 'Unnamed'} '
          '($cost points)',
        )
        ..writeln();
    }

    final regiments = _asMaps(army['regiments']);
    final generalIndex = _integer(army['general_index']);
    for (var index = 0; index < regiments.length; index++) {
      final regiment = regiments[index];
      buffer.writeln('Regiment ${index + 1}');
      if (generalIndex == index) buffer.writeln("General's regiment");
      final hero = _asMap(regiment['hero']);
      if (hero != null) {
        buffer.writeln('${_name(hero) ?? 'Hero'} (${_points(hero)} points)');
      }
      final artefact = _asMap(regiment['artefact']);
      if (artefact != null) {
        buffer.writeln('Artefact: ${_name(artefact) ?? 'Unknown'}');
      }
      final heroicTrait = _asMap(regiment['heroic_trait']);
      if (heroicTrait != null) {
        buffer.writeln('Heroic Trait: ${_name(heroicTrait) ?? 'Unknown'}');
      }
      for (final enhancement in _asMaps(regiment['other_enhancements'])) {
        final ability = _asMap(enhancement['ability']);
        if (ability != null) {
          buffer.writeln('Enhancement: ${_name(ability) ?? 'Unknown'}');
        }
      }
      for (final selected in _asMaps(regiment['units'])) {
        final unit = _asMap(selected['warscroll']);
        if (unit == null) continue;
        final modelCount = _integer(unit['modelCount']);
        final reinforced = selected['reinforced'] == true;
        final count =
            modelCount == null ? null : modelCount * (reinforced ? 2 : 1);
        final pointCost = _points(unit) * (reinforced ? 2 : 1);
        buffer.writeln(
          '${count == null ? '' : '$count x '}${_name(unit) ?? 'Unit'}'
          '${reinforced ? ' (Reinforced)' : ''} ($pointCost points)',
        );
        for (final enhancement in _asMaps(selected['other_enhancements'])) {
          final ability = _asMap(enhancement['ability']);
          if (ability != null) {
            buffer.writeln('Unit Enhancement: ${_name(ability) ?? 'Unknown'}');
          }
        }
      }
      buffer.writeln();
    }

    final auxiliaryUnits = _asMaps(army['auxiliary_units']);
    if (auxiliaryUnits.isNotEmpty) {
      buffer.writeln('Auxiliary Units');
      for (final selected in auxiliaryUnits) {
        final unit = _asMap(selected['warscroll']);
        if (unit == null) continue;
        buffer.writeln(
          '${_name(unit) ?? 'Unit'} (${_points(unit)} points)',
        );
        for (final enhancement in _asMaps(selected['other_enhancements'])) {
          final ability = _asMap(enhancement['ability']);
          if (ability != null) {
            buffer.writeln('Unit Enhancement: ${_name(ability) ?? 'Unknown'}');
          }
        }
      }
    }
    return buffer.toString();
  }

  static Future<JsonMap> importText(
    String text,
    ApiClient api,
  ) async {
    final draft = _parseTextList(text);
    final alliances = await api.builderAlliances();
    final alliance =
        _findNamed(alliances, draft.allianceName, 'grand alliance');
    final factionData = await api.builderFactions(alliance['id'].toString());
    final factions = [
      ..._asMaps(factionData['factions']),
      ..._asMaps(factionData['armies_of_renown']),
    ];
    final faction = _findNamed(factions, draft.factionName, 'faction');
    final factionId = faction['id'].toString();
    final results = await Future.wait([
      api.builderConfiguration(factionId),
      api.builderHeroes(factionId),
      api.builderAuxiliaryUnits(factionId),
      api.builderTactics(),
    ]);
    final configuration = results[0] as JsonMap;
    final heroes = results[1] as List<JsonMap>;
    final auxiliaryChoices = results[2] as List<JsonMap>;
    final tactics = results[3] as List<JsonMap>;
    final regiments = <JsonMap>[];
    var generalIndex =
        draft.regiments.indexWhere((regiment) => regiment.isGeneral);
    if (generalIndex < 0 && draft.regiments.isNotEmpty) generalIndex = 0;

    for (final regimentDraft in draft.regiments) {
      if (regimentDraft.units.isEmpty) {
        throw const FormatException('A regiment has no listed units.');
      }
      final heroEntry = regimentDraft.units.first;
      final hero = _findNamedOrNull(heroes, heroEntry.name);
      if (hero == null) {
        throw const FormatException(
          'The first unit in a regiment must be a hero available to lead it.',
        );
      }

      final unitData = await api.builderRegimentUnits(
        heroId: hero['id'].toString(),
        factionId: factionId,
      );
      final requiredUnits = _asMaps(unitData['required_units']);
      final choices = _asMaps(unitData['items']);
      final savedUnits = <JsonMap>[
        for (final required in requiredUnits)
          _savedUnit(required, required: true),
      ];
      final matchedRequired = <int>{};
      for (final entry in regimentDraft.units) {
        if (identical(entry, heroEntry)) continue;
        final requiredIndex = requiredUnits.indexWhere(
          (unit) => _sameName(unit['name'], entry.name),
        );
        if (requiredIndex >= 0 && !matchedRequired.contains(requiredIndex)) {
          final required = requiredUnits[requiredIndex];
          savedUnits[requiredIndex] = _savedUnit(
            required,
            required: true,
            reinforced: _isReinforced(required, entry),
          )..['other_enhancements'] = _resolveUnitEnhancements(
              entry.enhancements,
              required,
              _asMap(configuration['enhancements']) ?? const {},
            );
          matchedRequired.add(requiredIndex);
          continue;
        }

        JsonMap? choice;
        for (final candidate in choices) {
          final unit = _asMap(candidate['unit']);
          if (unit != null && _sameName(unit['name'], entry.name)) {
            choice = candidate;
            break;
          }
        }
        if (choice == null) {
          throw FormatException(
            '“${entry.name}” is not available in the regiment of ${hero['name']}.',
          );
        }
        final unit = _asMap(choice['unit'])!;
        savedUnits.add({
          ..._savedUnit(
            unit,
            reinforced: _isReinforced(unit, entry),
            onlyOne: choice['only_one'] == true,
            optionId: choice['option_id']?.toString(),
          ),
          'other_enhancements': _resolveUnitEnhancements(
            entry.enhancements,
            unit,
            _asMap(configuration['enhancements']) ?? const {},
          ),
        });
      }

      final enhancements = _resolveEnhancements(
        regimentDraft.enhancements,
        _asMap(configuration['enhancements']) ?? const {},
      );
      final heroEnhancements = [
        ..._asMaps(enhancements['other_enhancements']),
        ..._resolveUnitEnhancements(
          heroEntry.enhancements,
          hero,
          _asMap(configuration['enhancements']) ?? const {},
        ),
      ];
      regiments.add({
        'hero': hero,
        'units': savedUnits,
        'artefact': enhancements['artefact'],
        'heroic_trait': enhancements['heroic_trait'],
        'other_enhancements': heroEnhancements,
      });
    }

    final auxiliaryUnits = <JsonMap>[];
    for (final entry in draft.auxiliaryUnits) {
      final unit = _findNamed(auxiliaryChoices, entry.name, 'auxiliary unit');
      auxiliaryUnits.add({
        'warscroll': unit,
        'reinforced': _isReinforced(unit, entry),
        'other_enhancements': _resolveUnitEnhancements(
          entry.enhancements,
          unit,
          _asMap(configuration['enhancements']) ?? const {},
        ),
      });
    }

    final selectedOptions = <String, Object?>{
      'battle_formation': _resolveOptionalOption(
        _headerValue(draft, 'battle formation'),
        _asMaps(configuration['battle_formations']),
        'battle formation',
      ),
      'spell_lore': _resolveOptionalOption(
        _headerValue(draft, 'spell lore'),
        _asMaps(configuration['spell_lores']),
        'spell lore',
      ),
      'prayer_lore': _resolveOptionalOption(
        _headerValue(draft, 'prayer lore'),
        _asMaps(configuration['prayer_lores']),
        'prayer lore',
      ),
      'manifestation_lore': _resolveOptionalOption(
        _headerValue(draft, 'manifestation lore'),
        _asMaps(configuration['manifestation_lores']),
        'manifestation lore',
      ),
      'terrain': _resolveOptionalOption(
        _headerValue(draft, 'faction terrain'),
        _asMaps(configuration['terrain']),
        'faction terrain',
      ),
      'regiment_of_renown': _resolveOptionalOption(
        _headerValue(draft, 'regiment of renown'),
        _asMaps(configuration['regiments_of_renown']),
        'Regiment of Renown',
      ),
      'tactics': _resolveTactics(
        draft.headers['battle tactics cards'] ??
            draft.headers['battle tactics'],
        tactics,
      ),
    };

    return {
      'alliance': alliance,
      'faction': faction,
      'faction_name': faction['name']?.toString(),
      'total_points': draft.totalPoints,
      'points_limit': draft.pointsLimit,
      'general_index': generalIndex < 0 ? null : generalIndex,
      'regiments': regiments,
      'auxiliary_units': auxiliaryUnits,
      'selected_options': selectedOptions,
    };
  }

  static _CommunityExport _parseTextList(String text) {
    if (text.trim().isEmpty || text.length > 1024 * 1024) {
      throw const FormatException('Pasted army text is empty or too large.');
    }
    final headers = <String, String>{};
    final regiments = <_CommunityRegiment>[];
    final auxiliaryUnits = <_CommunityUnit>[];
    _CommunityRegiment? currentRegiment;
    var readingAuxiliary = false;
    var readingRegimentOfRenown = false;
    int? totalPoints;
    int? pointsLimit;
    final unitPattern = RegExp(
      r'^(?:(\d+)\s*x\s*)?(.+?)\s*(?:\((reinforced)\)\s*)?\(([\d,]+)\s*points?\)\s*,?$',
      caseSensitive: false,
    );
    final enhancementPattern = RegExp(r'^\[?(.+?)\]?\s*:\s*(.+?)\s*,?$');

    for (final rawLine in text.replaceAll('\r', '').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^[━─-]+$').hasMatch(line)) {
        currentRegiment = null;
        readingAuxiliary = false;
        readingRegimentOfRenown = false;
        continue;
      }
      if (line.toLowerCase().startsWith('exported with ')) continue;

      final pointsMatch = RegExp(
        r'(?:points?\s*:?\s*)?([\d,]+)\s*/\s*([\d,]+)\s*(?:pts?|points)?',
        caseSensitive: false,
      ).firstMatch(line);
      if (pointsMatch != null) {
        totalPoints = _integer(pointsMatch.group(1));
        pointsLimit = _integer(pointsMatch.group(2));
        currentRegiment = null;
        readingAuxiliary = false;
        readingRegimentOfRenown = false;
        continue;
      }

      final regimentMatch =
          RegExp(r'^regiment\s+\d+$', caseSensitive: false).firstMatch(line);
      if (regimentMatch != null) {
        if (regiments.length >= 5) {
          throw const FormatException(
              'A pasted list has more than five regiments.');
        }
        currentRegiment = _CommunityRegiment();
        regiments.add(currentRegiment);
        readingAuxiliary = false;
        readingRegimentOfRenown = false;
        continue;
      }
      if (line.toLowerCase() == 'auxiliary units') {
        currentRegiment = null;
        readingAuxiliary = true;
        readingRegimentOfRenown = false;
        continue;
      }
      if (_normalize(line) == 'regiment of renown') {
        if (headers.containsKey('regiment of renown')) {
          throw const FormatException(
            'The pasted list contains more than one Regiment of Renown.',
          );
        }
        currentRegiment = null;
        readingAuxiliary = false;
        readingRegimentOfRenown = true;
        continue;
      }
      if (readingRegimentOfRenown) {
        if (!headers.containsKey('regiment of renown')) {
          headers['regiment of renown'] = _stripPointsSuffix(line);
        }
        continue;
      }

      if (currentRegiment != null) {
        if (line.toLowerCase().startsWith('unit enhancement:')) {
          final value = line.substring('unit enhancement:'.length).trim();
          if (currentRegiment.units.isEmpty || value.isEmpty) {
            throw const FormatException(
              'A unit enhancement must follow a listed unit.',
            );
          }
          currentRegiment.units.last.enhancements.add(value);
          continue;
        }
        if (_normalize(line).contains('general s regiment')) {
          if (regiments.where((item) => item.isGeneral).isNotEmpty) {
            throw const FormatException(
              'The pasted list marks more than one general’s regiment.',
            );
          }
          currentRegiment.isGeneral = true;
          continue;
        }
        final unit = _parseUnit(line, unitPattern);
        if (unit != null) {
          currentRegiment.units.add(unit);
          continue;
        }
        final enhancement = enhancementPattern.firstMatch(line);
        if (enhancement != null) {
          final label = enhancement.group(1)!.trim();
          final value = enhancement.group(2)!.trim();
          currentRegiment.enhancements[label] = value;
          continue;
        }
        throw FormatException('Could not parse regiment entry: $line');
      }
      if (readingAuxiliary) {
        if (line.toLowerCase().startsWith('unit enhancement:')) {
          final value = line.substring('unit enhancement:'.length).trim();
          if (auxiliaryUnits.isEmpty || value.isEmpty) {
            throw const FormatException(
              'A unit enhancement must follow a listed auxiliary unit.',
            );
          }
          auxiliaryUnits.last.enhancements.add(value);
          continue;
        }
        final unit = _parseUnit(line, unitPattern);
        if (unit == null) {
          throw FormatException('Could not parse auxiliary unit: $line');
        }
        auxiliaryUnits.add(unit);
        continue;
      }

      final separator = line.indexOf(':');
      if (separator > 0) {
        final key = _normalize(line.substring(0, separator));
        var value = line.substring(separator + 1).trim();
        if (key == 'regiment of renown') {
          value = _stripPointsSuffix(value);
        } else if (key == 'manifestation lore') {
          value = _stripPointsSuffix(value);
        }
        if (key == 'grand alliance' ||
            key == 'faction' ||
            key == 'battle formation' ||
            key == 'battle tactics cards' ||
            key == 'battle tactics' ||
            key == 'spell lore' ||
            key == 'prayer lore' ||
            key == 'manifestation lore' ||
            key == 'faction terrain' ||
            key == 'regiment of renown') {
          headers[key] = value;
        }
      }
    }

    final allianceName = headers['grand alliance'];
    final factionName = headers['faction'];
    if (allianceName == null || allianceName.isEmpty) {
      throw const FormatException('The pasted text is missing Grand Alliance.');
    }
    if (factionName == null || factionName.isEmpty) {
      throw const FormatException('The pasted text is missing Faction.');
    }
    if (regiments.isEmpty) {
      throw const FormatException('The pasted text contains no regiments.');
    }
    return _CommunityExport(
      allianceName: allianceName,
      factionName: factionName,
      headers: headers,
      regiments: regiments,
      auxiliaryUnits: auxiliaryUnits,
      totalPoints: totalPoints,
      pointsLimit: pointsLimit,
    );
  }

  static _CommunityUnit? _parseUnit(String line, RegExp pattern) {
    final match = pattern.firstMatch(line);
    if (match == null) return null;
    final name = match.group(2)!.trim();
    if (name.isEmpty) return null;
    return _CommunityUnit(
      name: name,
      count: match.group(1) == null ? null : int.parse(match.group(1)!),
      reinforcedSuffix: match.group(3) != null,
    );
  }

  static String _stripPointsSuffix(String value) => value
      .replaceFirst(
        RegExp(r'\s*\([\d,]+\s*(?:pts?|points?)\)\s*$', caseSensitive: false),
        '',
      )
      .trim();

  static JsonMap _resolveEnhancements(
    Map<String, String> requested,
    JsonMap enhancementData,
  ) {
    JsonMap? artefact;
    JsonMap? heroicTrait;
    final other = <JsonMap>[];
    final artefacts = _asMaps(enhancementData['artefacts']);
    final traits = _asMaps(enhancementData['heroic_traits']);
    final otherGroups = _asMaps(enhancementData['other']);
    for (final entry in requested.entries) {
      final key = _normalize(entry.key);
      if (key == 'artefact') {
        artefact = _findNamed(artefacts, entry.value, 'artefact');
      } else if (key == 'heroic trait') {
        heroicTrait = _findNamed(traits, entry.value, 'heroic trait');
      } else if (key == 'enhancement') {
        final matches = <(JsonMap, JsonMap)>[];
        for (final group in otherGroups) {
          for (final ability in _asMaps(group['abilities'])) {
            if (_sameName(ability['name'], entry.value)) {
              matches.add((group, ability));
            }
          }
        }
        if (matches.length != 1) {
          throw FormatException(
            'Could not uniquely match enhancement “${entry.value}”.',
          );
        }
        final (group, ability) = matches.single;
        other.add({'group_id': group['id'], 'ability': ability});
      } else {
        final group = _findNamedOrNull(otherGroups, entry.key);
        if (group == null) {
          throw FormatException(
            'Unknown enhancement category “${entry.key}”.',
          );
        }
        final ability = _findNamed(
          _asMaps(group['abilities']),
          entry.value,
          entry.key,
        );
        other.add({'group_id': group['id'], 'ability': ability});
      }
    }
    return {
      'artefact': artefact,
      'heroic_trait': heroicTrait,
      'other_enhancements': other,
    };
  }

  static List<JsonMap> _resolveUnitEnhancements(
    List<String> requested,
    JsonMap unit,
    JsonMap enhancementData,
  ) {
    final otherGroups = _asMaps(enhancementData['other']);
    return [
      for (final name in requested)
        () {
          final matches = <(JsonMap, JsonMap)>[];
          for (final group in otherGroups) {
            if (!enhancementCanBeGivenTo(group, unit)) continue;
            for (final ability in _asMaps(group['abilities'])) {
              if (_sameName(ability['name'], name)) {
                matches.add((group, ability));
              }
            }
          }
          if (matches.length != 1) {
            throw FormatException(
              matches.isEmpty
                  ? 'Enhancement “$name” is not available for ${unit['name']}.'
                  : 'Could not uniquely match enhancement “$name”.',
            );
          }
          final (group, ability) = matches.single;
          return {'group_id': group['id'], 'ability': ability};
        }(),
    ];
  }

  static JsonMap? _resolveOptionalOption(
    String? value,
    List<JsonMap> options,
    String kind,
  ) {
    if (value == null || value.isEmpty || _normalize(value) == 'none') {
      return null;
    }
    return _findNamed(options, value, kind);
  }

  static List<JsonMap> _resolveTactics(
    String? value,
    List<JsonMap> options,
  ) {
    if (value == null || value.isEmpty || _normalize(value) == 'none') {
      return [];
    }
    final names = value
        .split(RegExp(r'\s*(?:,|\band\b)\s*', caseSensitive: false))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    return [
      for (final name in names)
        _findNamed(
          options,
          name,
          'battle tactic',
          nameFor: _tacticName,
        ),
    ];
  }

  static JsonMap _savedUnit(
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

  static bool _isReinforced(JsonMap unit, _CommunityUnit entry) {
    if (entry.reinforcedSuffix) return true;
    if (entry.count == null) return false;
    final modelCount = _integer(unit['modelCount']);
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

  static String? _headerValue(_CommunityExport draft, String key) {
    final value = draft.headers[key]?.trim();
    if (value == null || value.isEmpty || _normalize(value) == 'none') {
      return null;
    }
    return value;
  }

  static JsonMap _findNamed(
    List<JsonMap> items,
    String name,
    String kind, {
    String Function(JsonMap)? nameFor,
  }) {
    final item = _findNamedOrNull(items, name, nameFor: nameFor);
    if (item == null) {
      throw FormatException('Could not match $kind “$name” with app data.');
    }
    return item;
  }

  static JsonMap? _findNamedOrNull(
    List<JsonMap> items,
    String name, {
    String Function(JsonMap)? nameFor,
  }) {
    final normalized = _normalize(name);
    for (final item in items) {
      final itemName = nameFor?.call(item) ?? item['name']?.toString() ?? '';
      if (_normalize(itemName) == normalized) return item;
    }
    return null;
  }

  static bool _sameName(Object? first, String second) =>
      _normalize(first?.toString() ?? '') == _normalize(second);

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static String _tacticName(JsonMap tactic) {
    final title = tactic['title']?.toString() ?? '';
    final separator = title.indexOf(' - ');
    return separator < 0 ? title : title.substring(separator + 3);
  }

  static String? _name(Object? item) {
    final map = _asMap(item);
    return map?['name']?.toString() ?? map?['title']?.toString();
  }

  static int _points(JsonMap item) => _integer(item['points']) ?? 0;

  static int? _integer(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.replaceAll(',', ''));
    return null;
  }

  static List<JsonMap> _asMaps(Object? value) {
    if (value is! List) return [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  static JsonMap? _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : null;
}

class _CommunityExport {
  _CommunityExport({
    required this.allianceName,
    required this.factionName,
    required this.headers,
    required this.regiments,
    required this.auxiliaryUnits,
    required this.totalPoints,
    required this.pointsLimit,
  });

  final String allianceName;
  final String factionName;
  final Map<String, String> headers;
  final List<_CommunityRegiment> regiments;
  final List<_CommunityUnit> auxiliaryUnits;
  final int? totalPoints;
  final int? pointsLimit;
}

class _CommunityRegiment {
  bool isGeneral = false;
  final List<_CommunityUnit> units = [];
  final Map<String, String> enhancements = {};
}

class _CommunityUnit {
  _CommunityUnit({
    required this.name,
    required this.count,
    required this.reinforcedSuffix,
    List<String>? enhancements,
  }) : enhancements = enhancements ?? [];

  final String name;
  final int? count;
  final bool reinforcedSuffix;
  final List<String> enhancements;
}
