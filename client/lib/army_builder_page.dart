import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'army_builder_rules.dart';
import 'api_client.dart';
import 'data_details_sheet.dart';
import 'saved_army_store.dart';
import 'save_army_name_dialog.dart';
import 'unit_type_grouping.dart';

class ArmyBuilderPage extends StatefulWidget {
  const ArmyBuilderPage({
    super.key,
    this.savedArmy,
    this.apiClient,
    this.onClose,
  });

  final JsonMap? savedArmy;
  final ApiClient? apiClient;
  final VoidCallback? onClose;

  @override
  State<ArmyBuilderPage> createState() => _ArmyBuilderPageState();
}

class _ArmyBuilderPageState extends State<ArmyBuilderPage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _savedArmyStore = SavedArmyStore();
  List<JsonMap> _alliances = [];
  List<JsonMap> _factions = [];
  List<JsonMap> _armiesOfRenown = [];
  final List<_BuilderRegiment> _regiments = [];
  final List<_SelectedUnit> _auxiliaryUnits = [];
  List<JsonMap> _auxiliaryChoices = [];
  List<JsonMap> _tactics = [];
  JsonMap _configuration = {};
  JsonMap? _selectedAlliance;
  JsonMap? _selectedFaction;
  JsonMap? _battleFormation;
  JsonMap? _spellLore;
  JsonMap? _prayerLore;
  JsonMap? _manifestationLore;
  JsonMap? _terrain;
  JsonMap? _regimentOfRenown;
  JsonMap? _opponentArmy;
  JsonMap _opponentConfiguration = {};
  final List<JsonMap> _selectedTactics = [];
  String? _savedArmyId;
  String? _savedArmyName;
  int _pointsLimit = 2000;
  int? _generalIndex;
  bool _showOpponent = false;
  bool _showLegends = false;
  bool _loading = true;
  String? _error;

  int get _totalPoints =>
      _regiments.fold<int>(0, (total, regiment) {
        final heroPoints = _points(regiment.hero);
        final unitPoints = regiment.units.fold<int>(
          0,
          (subtotal, unit) => subtotal + unit.points,
        );
        final enhancementPoints = [
          regiment.artefact,
          regiment.heroicTrait,
          ...regiment.otherEnhancements.map((item) => item.ability),
          for (final unit in regiment.units)
            ...unit.enhancements.map((item) => item.ability),
        ].fold<int>(0, (sum, enhancement) => sum + _points(enhancement));
        return total + heroPoints + unitPoints + enhancementPoints;
      }) +
      _auxiliaryUnits.fold<int>(
        0,
        (sum, unit) =>
            sum +
            unit.points +
            unit.enhancements.fold<int>(
              0,
              (points, enhancement) => points + _points(enhancement.ability),
            ),
      ) +
      _points(_battleFormation) +
      _points(_spellLore) +
      _points(_prayerLore) +
      _points(_manifestationLore) +
      _points(_terrain) +
      _regimentOfRenownPoints(_regimentOfRenown);

  int get _regimentSlotsUsed =>
      _regiments.length + (_regimentOfRenown == null ? 0 : 1);

  List<String> get _validationErrors {
    final errors = <String>[];
    if (_selectedTactics.length > 2) {
      errors.add('Choose no more than two Battle Tactics Cards.');
    }
    if (_regiments.isEmpty) errors.add('Add at least one regiment.');
    if (_generalIndex == null) errors.add('Choose a General.');
    if (_regimentSlotsUsed > 5) {
      errors.add('An army cannot include more than five regiments.');
    }
    final duplicateUniqueNames = duplicateUniqueUnits(_allSelectedUnits())
        .map((unit) => unit['name']?.toString() ?? 'Unique unit')
        .toSet();
    for (final name in duplicateUniqueNames) {
      errors.add('You can only include one $name in an army.');
    }
    for (var index = 0; index < _regiments.length; index++) {
      final regiment = _regiments[index];
      if (regiment.hero == null) {
        errors.add('Choose a hero for Regiment ${index + 1}.');
      } else if (_unitCount(regiment) > _unitLimit(index)) {
        errors.add('Regiment ${index + 1} has too many units.');
      }
    }
    if (_totalPoints > _pointsLimit) {
      errors.add('The army exceeds the $_pointsLimit point limit.');
    }
    for (final regiment in _regiments) {
      for (final unit in regiment.units) {
        if (unit.reinforced && _points(unit.warscroll) * 2 > _pointsLimit) {
          errors.add(
              '${unit.warscroll['name']} exceeds the reinforcement limit.');
        }
      }
    }
    return errors;
  }

  @override
  void initState() {
    super.initState();
    if (widget.savedArmy == null) {
      unawaited(_loadAlliances());
    } else {
      unawaited(_restoreSavedArmy(widget.savedArmy!));
    }
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  Future<void> _loadAlliances() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final alliances = await _api.builderAlliances();
      if (!mounted) return;
      setState(() {
        _alliances = alliances;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectAlliance(JsonMap alliance) async {
    setState(() {
      _selectedAlliance = alliance;
      _selectedFaction = null;
      _regiments.clear();
      _generalIndex = null;
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.builderFactions(alliance['id'].toString());
      if (!mounted) return;
      setState(() {
        _factions = _asMaps(result['factions']);
        _armiesOfRenown = _asMaps(result['armies_of_renown']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectFaction(JsonMap faction) async {
    setState(() {
      _selectedFaction = faction;
      _regiments.clear();
      _auxiliaryUnits.clear();
      _generalIndex = null;
      _pointsLimit = 2000;
      _battleFormation = null;
      _spellLore = null;
      _prayerLore = null;
      _manifestationLore = null;
      _terrain = null;
      _regimentOfRenown = null;
      _opponentArmy = null;
      _opponentConfiguration = {};
      _showOpponent = false;
      _selectedTactics.clear();
      _savedArmyId = null;
      _savedArmyName = null;
      _loading = true;
      _error = null;
    });
    try {
      final factionId = faction['id'].toString();
      final results = await Future.wait([
        _api.builderConfiguration(factionId),
        _api.builderTactics(),
        _api.builderAuxiliaryUnits(factionId, showLegends: _showLegends),
      ]);
      if (!mounted) return;
      setState(() {
        _configuration = results[0] as JsonMap;
        _tactics = results[1] as List<JsonMap>;
        _auxiliaryChoices = results[2] as List<JsonMap>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _goBack() {
    if (widget.savedArmy != null) {
      final onClose = widget.onClose;
      if (onClose != null) {
        onClose();
      } else {
        Navigator.of(context).maybePop();
      }
    } else if (_selectedFaction != null) {
      setState(() {
        _selectedFaction = null;
        _opponentArmy = null;
        _opponentConfiguration = {};
        _showOpponent = false;
        _configuration = {};
        _auxiliaryChoices = [];
        _tactics = [];
        _regiments.clear();
        _auxiliaryUnits.clear();
        _generalIndex = null;
        _loading = false;
      });
    } else if (_selectedAlliance != null) {
      setState(() {
        _selectedAlliance = null;
        _factions = [];
        _armiesOfRenown = [];
        _error = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _addRegiment() async {
    if (_regimentSlotsUsed >= 5) return;
    final index = _regiments.length;
    setState(() => _regiments.add(_BuilderRegiment()));
    await _chooseHero(index);
  }

  Future<void> _chooseHero(int regimentIndex) async {
    final faction = _selectedFaction;
    if (faction == null) return;
    try {
      final heroes = await _api.builderHeroes(
        faction['id'].toString(),
        showLegends: _showLegends,
      );
      if (!mounted) return;
      final currentHero = _regiments[regimentIndex].hero;
      final availableHeroes = availableUniqueUnits(
        heroes,
        _allSelectedUnits(),
        except: currentHero,
      );
      final hero = await _showSelectionDialog(
        title: 'Choose a hero',
        items: availableHeroes,
        titleFor: (item) => item['name']?.toString() ?? 'Unnamed hero',
        subtitleFor: (item) => '${_points(item)} pts',
      );
      if (!mounted || hero == null) return;
      if (availableUniqueUnits(
        [hero],
        _allSelectedUnits(),
        except: _regiments[regimentIndex].hero,
      ).isEmpty) {
        _showMessage('A Unique unit can only be included once in an army.');
        return;
      }

      final regimentData = await _api.builderRegimentUnits(
        heroId: hero['id'].toString(),
        factionId: faction['id'].toString(),
        showLegends: _showLegends,
      );
      final requiredUnits = _asMaps(regimentData['required_units'])
          .map((unit) => _SelectedUnit(unit, isRequired: true))
          .toList();
      if (!mounted) return;
      if (availableUniqueUnits(
        [hero],
        _allSelectedUnits(),
        except: _regiments[regimentIndex].hero,
      ).isEmpty) {
        _showMessage('A Unique unit can only be included once in an army.');
        return;
      }

      var removedOtherEnhancements = false;
      setState(() {
        final regiment = _regiments[regimentIndex];
        regiment.hero = hero;
        final otherGroups = _asMaps(
          _asMap(_configuration['enhancements'])?['other'],
        );
        final groupsById = {
          for (final group in otherGroups)
            if (group['id']?.toString() case final id?) id: group,
        };
        regiment.otherEnhancements.removeWhere((enhancement) {
          final group = groupsById[enhancement.groupId];
          final ineligible =
              group == null || !enhancementCanBeGivenTo(group, hero);
          if (ineligible) removedOtherEnhancements = true;
          return ineligible;
        });
        regiment.units
          ..clear()
          ..addAll(requiredUnits);
        regiment.unitChoices = _asMaps(regimentData['items']);
      });
      if (removedOtherEnhancements) {
        _showMessage(
          'Enhancements not eligible for the new hero were removed.',
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleLegends(bool showLegends) async {
    setState(() => _showLegends = showLegends);
    final faction = _selectedFaction;
    if (faction == null) return;

    try {
      final regimentIndices = <int>[];
      final requests = <Future<JsonMap>>[];
      for (var index = 0; index < _regiments.length; index++) {
        final hero = _regiments[index].hero;
        if (hero == null) continue;
        regimentIndices.add(index);
        requests.add(
          _api.builderRegimentUnits(
            heroId: hero['id'].toString(),
            factionId: faction['id'].toString(),
            showLegends: showLegends,
          ),
        );
      }
      final auxiliaryChoices = await _api.builderAuxiliaryUnits(
        faction['id'].toString(),
        showLegends: showLegends,
      );
      final results = await Future.wait(requests);
      if (!mounted) return;
      setState(() {
        _auxiliaryChoices = auxiliaryChoices;
        for (var index = 0; index < regimentIndices.length; index++) {
          final regiment = _regiments[regimentIndices[index]];
          final requiredUnits = _asMaps(results[index]['required_units'])
              .map((unit) => _SelectedUnit(unit, isRequired: true));
          final selectedUnits =
              regiment.units.where((unit) => !unit.isRequired).toList();
          regiment.units
            ..clear()
            ..addAll(requiredUnits)
            ..addAll(selectedUnits);
          regiment.unitChoices = _asMaps(results[index]['items']);
        }
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _restoreSavedArmy(JsonMap savedArmy) async {
    final army = savedArmy['army'];
    if (army is! Map<String, dynamic>) {
      setState(() {
        _error = 'Saved army data is invalid.';
        _loading = false;
      });
      return;
    }
    final alliance = army['alliance'];
    final faction = army['faction'];
    if (alliance is! Map<String, dynamic> || faction is! Map<String, dynamic>) {
      setState(() {
        _error = 'Saved army is missing its faction.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _selectedAlliance = alliance;
      _selectedFaction = faction;
      _savedArmyId = savedArmy['id']?.toString();
      _savedArmyName = savedArmy['name']?.toString();
      _pointsLimit = (army['points_limit'] as num?)?.toInt() ?? 2000;
      _generalIndex = (army['general_index'] as num?)?.toInt();
    });

    try {
      final factionId = faction['id'].toString();
      final results = await Future.wait([
        _api.builderConfiguration(factionId),
        _api.builderTactics(),
        _api.builderAuxiliaryUnits(factionId, showLegends: _showLegends),
      ]);
      final configuration = results[0] as JsonMap;
      final enhancementGroups = _asMaps(
        _asMap(configuration['enhancements'])?['other'],
      );
      final enhancementGroupsById = {
        for (final group in enhancementGroups)
          if (group['id']?.toString() case final id?) id: group,
      };
      var removedIneligibleEnhancements = false;
      final regiments = <_BuilderRegiment>[];
      for (final savedRegiment in _asMaps(army['regiments'])) {
        final hero = savedRegiment['hero'];
        if (hero is! Map<String, dynamic>) continue;
        final choices = await _api.builderRegimentUnits(
          heroId: hero['id'].toString(),
          factionId: factionId,
          showLegends: _showLegends,
        );
        final regiment = _BuilderRegiment()
          ..hero = hero
          ..unitChoices = _asMaps(choices['items'])
          ..artefact = _asMap(savedRegiment['artefact'])
          ..heroicTrait = _asMap(savedRegiment['heroic_trait']);
        for (final item in _asMaps(savedRegiment['other_enhancements'])) {
          final groupId = item['group_id']?.toString();
          final ability = _asMap(item['ability']);
          final group = groupId == null ? null : enhancementGroupsById[groupId];
          if (groupId == null ||
              group == null ||
              ability == null ||
              !enhancementCanBeGivenTo(group, hero)) {
            removedIneligibleEnhancements = true;
            continue;
          }
          regiment.otherEnhancements.add(
            _SelectedEnhancement(groupId: groupId, ability: ability),
          );
        }
        regiment.units = _asMaps(savedRegiment['units'])
            .map((item) {
              final warscroll = item['warscroll'];
              if (warscroll is! Map<String, dynamic>) return null;
              final unit = _SelectedUnit(
                warscroll,
                onlyOne: item['only_one'] == true,
                optionId: item['option_id']?.toString(),
                isRequired: item['is_required'] == true,
                reinforced: item['reinforced'] == true,
              );
              for (final enhancement in _asMaps(item['other_enhancements'])) {
                final groupId = enhancement['group_id']?.toString();
                final ability = _asMap(enhancement['ability']);
                final group =
                    groupId == null ? null : enhancementGroupsById[groupId];
                if (groupId == null ||
                    group == null ||
                    ability == null ||
                    !enhancementCanBeGivenTo(group, warscroll)) {
                  removedIneligibleEnhancements = true;
                  continue;
                }
                unit.enhancements.add(
                  _SelectedEnhancement(groupId: groupId, ability: ability),
                );
              }
              return unit;
            })
            .whereType<_SelectedUnit>()
            .toList();
        regiments.add(regiment);
      }

      final options = army['selected_options'];
      final auxiliaryUnits = _asMaps(army['auxiliary_units'])
          .map((item) {
            final warscroll = item['warscroll'];
            if (warscroll is! Map<String, dynamic>) return null;
            final unit = _SelectedUnit(
              warscroll,
              reinforced: item['reinforced'] == true,
            );
            for (final enhancement in _asMaps(item['other_enhancements'])) {
              final groupId = enhancement['group_id']?.toString();
              final ability = _asMap(enhancement['ability']);
              final group =
                  groupId == null ? null : enhancementGroupsById[groupId];
              if (groupId == null ||
                  group == null ||
                  ability == null ||
                  !enhancementCanBeGivenTo(group, warscroll)) {
                removedIneligibleEnhancements = true;
                continue;
              }
              unit.enhancements.add(
                _SelectedEnhancement(groupId: groupId, ability: ability),
              );
            }
            return unit;
          })
          .whereType<_SelectedUnit>()
          .toList();
      removedIneligibleEnhancements = _pruneInvalidEnhancementAssignments(
            enhancementGroups,
            regiments,
            auxiliaryUnits,
          ) ||
          removedIneligibleEnhancements;
      if (!mounted) return;
      setState(() {
        _configuration = configuration;
        _tactics = results[1] as List<JsonMap>;
        _auxiliaryChoices = results[2] as List<JsonMap>;
        _regiments
          ..clear()
          ..addAll(regiments);
        _auxiliaryUnits
          ..clear()
          ..addAll(auxiliaryUnits);
        _battleFormation = _asMap(
          options is Map ? options['battle_formation'] : null,
        );
        _spellLore = _asMap(options is Map ? options['spell_lore'] : null);
        _prayerLore = _asMap(options is Map ? options['prayer_lore'] : null);
        _manifestationLore =
            _asMap(options is Map ? options['manifestation_lore'] : null);
        _terrain = _asMap(options is Map ? options['terrain'] : null);
        _regimentOfRenown =
            _asMap(options is Map ? options['regiment_of_renown'] : null);
        _selectedTactics
          ..clear()
          ..addAll(_asMaps(options is Map ? options['tactics'] : null));
        _loading = false;
      });
      if (removedIneligibleEnhancements) {
        _showMessage(
          'Some saved enhancements were removed because they were duplicated, exceeded recipient limits, or had ineligible units.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  bool _pruneInvalidEnhancementAssignments(
    List<JsonMap> groups,
    List<_BuilderRegiment> regiments,
    List<_SelectedUnit> auxiliaryUnits,
  ) {
    final groupsById = {
      for (final group in groups)
        if (group['id']?.toString() case final id?) id: group,
    };
    final rosterCounts = <String, int>{};
    final uniqueAbilitySelections = <String>{};
    var removed = false;

    void prune(JsonMap warscroll, List<_SelectedEnhancement> enhancements) {
      final unitCounts = <String, int>{};
      enhancements.removeWhere((enhancement) {
        final group = groupsById[enhancement.groupId];
        if (group == null || !enhancementCanBeGivenTo(group, warscroll)) {
          removed = true;
          return true;
        }
        final unitLimit = (group['unitLevelLimit'] as num?)?.toInt() ?? 1;
        final rosterLimit = (group['rosterLevelLimit'] as num?)?.toInt();
        final unitCount = unitCounts[enhancement.groupId] ?? 0;
        final rosterCount = rosterCounts[enhancement.groupId] ?? 0;
        if (unitCount >= unitLimit ||
            (rosterLimit != null && rosterCount >= rosterLimit)) {
          removed = true;
          return true;
        }
        if (group['uniqueAbilitySelections'] == true) {
          final abilityId = enhancement.ability['id']?.toString();
          if (abilityId == null ||
              !uniqueAbilitySelections.add(
                '${enhancement.groupId}:$abilityId',
              )) {
            removed = true;
            return true;
          }
        }
        unitCounts[enhancement.groupId] = unitCount + 1;
        rosterCounts[enhancement.groupId] = rosterCount + 1;
        return false;
      });
    }

    for (final regiment in regiments) {
      if (regiment.hero case final hero?) {
        prune(hero, regiment.otherEnhancements);
      }
      for (final unit in regiment.units) {
        prune(unit.warscroll, unit.enhancements);
      }
    }
    for (final unit in auxiliaryUnits) {
      prune(unit.warscroll, unit.enhancements);
    }
    return removed;
  }

  Future<void> _addUnit(int regimentIndex) async {
    final regiment = _regiments[regimentIndex];
    if (regiment.hero == null) {
      await _chooseHero(regimentIndex);
      return;
    }
    if (_unitCount(regiment) >= _unitLimit(regimentIndex)) {
      _showMessage('This regiment has reached its unit limit.');
      return;
    }

    final available = regiment.unitChoices.where((choice) {
      final unit = choice['unit'];
      if (unit is! Map<String, dynamic>) return false;
      final optionId = choice['option_id']?.toString();
      final onlyOne = choice['only_one'] == true;
      if (onlyOne &&
          optionId != null &&
          regiment.units.any((selected) => selected.optionId == optionId)) {
        return false;
      }
      if (availableUniqueUnits([unit], _allSelectedUnits()).isEmpty) {
        return false;
      }
      return true;
    }).toList();

    final choice = await _showSelectionDialog(
      title: 'Add a unit',
      items: available,
      groupByUnitType: true,
      titleFor: (item) {
        final unit = item['unit'];
        return unit is Map<String, dynamic>
            ? unit['name']?.toString() ?? 'Unnamed unit'
            : 'Unnamed unit';
      },
      subtitleFor: (item) {
        final unit = item['unit'];
        return unit is Map<String, dynamic> ? '${_points(unit)} pts' : '';
      },
    );
    if (!mounted || choice == null) return;
    if (_unitCount(regiment) >= _unitLimit(regimentIndex)) {
      _showMessage('This regiment has reached its unit limit.');
      return;
    }
    final unit = choice['unit'];
    if (unit is! Map<String, dynamic>) return;
    if (availableUniqueUnits([unit], _allSelectedUnits()).isEmpty) {
      _showMessage('A Unique unit can only be included once in an army.');
      return;
    }
    setState(() {
      regiment.units.add(
        _SelectedUnit(
          unit,
          onlyOne: choice['only_one'] == true,
          optionId: choice['option_id']?.toString(),
        ),
      );
    });
  }

  Future<JsonMap?> _showSelectionDialog({
    required String title,
    required List<JsonMap> items,
    required String Function(JsonMap) titleFor,
    required String Function(JsonMap) subtitleFor,
    bool groupByUnitType = false,
  }) {
    return showDialog<JsonMap>(
      context: context,
      builder: (context) => _SelectionDialog(
        title: title,
        items: items,
        groupByUnitType: groupByUnitType,
        titleFor: titleFor,
        subtitleFor: subtitleFor,
        onDetails: _showItemDetails,
      ),
    );
  }

  List<JsonMap> _allSelectedUnits({bool includeRegimentOfRenown = true}) => [
        for (final regiment in _regiments) ...[
          if (regiment.hero != null) regiment.hero!,
          for (final unit in regiment.units) unit.warscroll,
        ],
        for (final unit in _auxiliaryUnits) unit.warscroll,
        if (includeRegimentOfRenown)
          for (final regimentUnit in _asMaps(_regimentOfRenown?['units']))
            if (regimentUnit['warscroll'] is Map<String, dynamic>)
              regimentUnit['warscroll'] as JsonMap,
      ];

  int _unitCount(_BuilderRegiment regiment) =>
      (regiment.hero == null ? 0 : 1) + regiment.units.length;

  int _unitLimit(int regimentIndex) => _generalIndex == regimentIndex ? 5 : 4;

  void _removeRegiment(int index) {
    setState(() {
      _regiments.removeAt(index);
      if (_generalIndex == index) {
        _generalIndex = null;
      } else if (_generalIndex != null && _generalIndex! > index) {
        _generalIndex = _generalIndex! - 1;
      }
    });
  }

  void _removeUnit(int regimentIndex, int unitIndex) {
    if (_regiments[regimentIndex].units[unitIndex].isRequired) return;
    setState(() => _regiments[regimentIndex].units.removeAt(unitIndex));
  }

  void _toggleReinforcement(int regimentIndex, int unitIndex) {
    final selected = _regiments[regimentIndex].units[unitIndex];
    if (selected.isRequired ||
        selected.warscroll['cannotBeReinforced'] == true) {
      return;
    }
    if (!selected.reinforced &&
        _points(selected.warscroll) * 2 > _pointsLimit) {
      _showMessage('A reinforced unit cannot exceed half of the army limit.');
      return;
    }
    setState(() => selected.reinforced = !selected.reinforced);
  }

  void _setGeneral(int index, bool isGeneral) {
    setState(() => _generalIndex = isGeneral ? index : null);
  }

  Future<void> _chooseArmyOption({
    required String title,
    required String key,
    required void Function(JsonMap?) onSelected,
  }) async {
    final items = _asMaps(_configuration[key]);
    if (items.isEmpty) {
      _showMessage('No $title options are available for this faction.');
      return;
    }
    final selection = await _showSelectionDialog(
      title: 'Choose $title',
      items: items,
      titleFor: (item) =>
          item['name']?.toString() ??
          item['title']?.toString() ??
          'Unnamed option',
      subtitleFor: (item) =>
          '${_points(item)} pts${item['abilities'] is List && (item['abilities'] as List).isNotEmpty ? ' · ${(item['abilities'] as List).length} rules' : ''}',
    );
    if (!mounted || selection == null) return;
    setState(() => onSelected(selection));
  }

  Future<void> _chooseRegimentOfRenown() async {
    if (_regimentOfRenown == null && _regiments.length >= 5) {
      _showMessage('Remove a regiment before adding a Regiment of Renown.');
      return;
    }
    final allChoices = _asMaps(_configuration['regiments_of_renown']);
    if (allChoices.isEmpty) {
      _showMessage('No Regiments of Renown are available for this faction.');
      return;
    }
    final choices = availableUniqueRegimentsOfRenown(
      allChoices,
      _allSelectedUnits(includeRegimentOfRenown: false),
    );
    if (choices.isEmpty) {
      _showMessage(
        'No Regiments of Renown are available without repeating a Unique unit.',
      );
      return;
    }
    final selection = await _showSelectionDialog(
      title: 'Choose Regiment of Renown',
      items: choices,
      titleFor: (item) => item['name']?.toString() ?? 'Unnamed regiment',
      subtitleFor: (item) =>
          '${_regimentOfRenownPoints(item)} pts · ${_asMaps(item['units']).length} units',
    );
    if (!mounted || selection == null) return;
    if (availableUniqueRegimentsOfRenown(
      [selection],
      _allSelectedUnits(includeRegimentOfRenown: false),
    ).isEmpty) {
      _showMessage('A Unique unit can only be included once in an army.');
      return;
    }
    setState(() => _regimentOfRenown = selection);
  }

  Future<void> _chooseOpponentArmy() async {
    try {
      final savedArmies = await _savedArmyStore.load();
      final choices = savedArmies
          .where((army) =>
              _asMap(army['army']) != null &&
              army['id']?.toString() != _savedArmyId)
          .toList();
      if (choices.isEmpty) {
        _showMessage('Save another army list to choose an opponent.');
        return;
      }
      if (!mounted) return;
      final selection = await showDialog<JsonMap>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose opponent army'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: [
                for (final army in choices)
                  ListTile(
                    title: Text(army['name']?.toString() ?? 'Army'),
                    subtitle: Text(_savedArmySummary(army)),
                    onTap: () => Navigator.pop(context, army),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || selection == null) return;
      setState(() {
        _opponentArmy = selection;
        _opponentConfiguration = {};
        _showOpponent = false;
      });
      final army = _asMap(selection['army']);
      final faction = _asMap(army?['faction']);
      final factionId = faction?['id']?.toString();
      if (factionId != null) {
        unawaited(_loadOpponentConfiguration(factionId, selection));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _loadOpponentConfiguration(
    String factionId,
    JsonMap armyRecord,
  ) async {
    try {
      final configuration = await _api.builderConfiguration(factionId);
      if (!mounted || !identical(_opponentArmy, armyRecord)) return;
      setState(() => _opponentConfiguration = configuration);
    } catch (error) {
      if (!mounted || !identical(_opponentArmy, armyRecord)) return;
      _showError(error);
    }
  }

  String _savedArmySummary(JsonMap record) {
    final army = _asMap(record['army']);
    final faction = _asMap(army?['faction']);
    final factionName = faction?['name']?.toString() ?? 'Unknown faction';
    return '$factionName · ${army?['total_points'] ?? 0} pts';
  }

  Future<void> _chooseAuxiliary() async {
    final choices = _auxiliaryChoices;
    if (choices.isEmpty) {
      _showMessage('No auxiliary units are available for this faction.');
      return;
    }
    final selection = await _showSelectionDialog(
      title: 'Add auxiliary unit',
      items: choices,
      groupByUnitType: true,
      titleFor: (item) => item['name']?.toString() ?? 'Unnamed unit',
      subtitleFor: (item) => '${_points(item)} pts',
    );
    if (!mounted || selection == null) return;
    setState(() => _auxiliaryUnits.add(_SelectedUnit(selection)));
  }

  Future<void> _chooseEnhancement(
    int regimentIndex, {
    required String title,
    required List<JsonMap> choices,
    required void Function(_BuilderRegiment regiment, JsonMap? value) update,
  }) async {
    if (choices.isEmpty) {
      _showMessage('No $title options are available for this faction.');
      return;
    }
    final selection = await _showSelectionDialog(
      title: 'Choose $title',
      items: choices,
      titleFor: (item) => item['name']?.toString() ?? 'Unnamed enhancement',
      subtitleFor: (item) => '${_points(item)} pts',
    );
    if (!mounted) return;
    setState(() => update(_regiments[regimentIndex], selection));
  }

  Future<void> _chooseTactics() async {
    if (_tactics.isEmpty) {
      _showMessage('No battle tactics cards are available.');
      return;
    }
    final selected = await showDialog<List<JsonMap>>(
      context: context,
      builder: (context) => _TacticsSelectionDialog(
        items: _tactics,
        selected: _selectedTactics,
        onDetails: _showItemDetails,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedTactics
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _showItemDetails(JsonMap item) async {
    final nestedUnit = item['unit'];
    final target = nestedUnit is Map<String, dynamic> ? nestedUnit : item;
    JsonMap? details;
    final warscrollId = target['id']?.toString();
    if (warscrollId != null &&
        (target.containsKey('referenceKeywords') ||
            target.containsKey('rowImage'))) {
      try {
        details = await _api.builderWarscrollDetails(warscrollId);
      } catch (error) {
        _showError(error);
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DataDetailsSheet(
        item: target,
        details: details,
        onOpenDetails: _showItemDetails,
      ),
    );
  }

  Future<void> _saveArmy() async {
    final faction = _selectedFaction;
    if (faction == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SaveArmyNameDialog(
        title: _savedArmyId == null ? 'Save army' : 'Update saved army',
        initialName: _savedArmyName,
      ),
    );
    if (!mounted || name == null) return;
    try {
      final record = await _savedArmyStore.save(
        name: name,
        id: _savedArmyId,
        army: _serializeArmy(),
      );
      if (!mounted) return;
      setState(() {
        _savedArmyId = record['id']?.toString();
        _savedArmyName = name;
      });
      _showMessage('Army saved on this device.');
    } catch (error) {
      _showError(error);
    }
  }

  JsonMap _serializeArmy() {
    return {
      'alliance': _selectedAlliance,
      'faction': _selectedFaction,
      'faction_name': _selectedFaction?['name']?.toString(),
      'total_points': _totalPoints,
      'points_limit': _pointsLimit,
      'general_index': _generalIndex,
      'regiments': [
        for (final regiment in _regiments)
          {
            'hero': regiment.hero,
            'units': [
              for (final unit in regiment.units)
                {
                  'warscroll': unit.warscroll,
                  'only_one': unit.onlyOne,
                  'option_id': unit.optionId,
                  'is_required': unit.isRequired,
                  'reinforced': unit.reinforced,
                  'other_enhancements': [
                    for (final enhancement in unit.enhancements)
                      {
                        'group_id': enhancement.groupId,
                        'ability': enhancement.ability,
                      },
                  ],
                },
            ],
            'artefact': regiment.artefact,
            'heroic_trait': regiment.heroicTrait,
            'other_enhancements': [
              for (final enhancement in regiment.otherEnhancements)
                {
                  'group_id': enhancement.groupId,
                  'ability': enhancement.ability,
                },
            ],
          },
      ],
      'auxiliary_units': [
        for (final unit in _auxiliaryUnits)
          {
            'warscroll': unit.warscroll,
            'reinforced': unit.reinforced,
            'other_enhancements': [
              for (final enhancement in unit.enhancements)
                {
                  'group_id': enhancement.groupId,
                  'ability': enhancement.ability,
                },
            ],
          },
      ],
      'selected_options': {
        'battle_formation': _battleFormation,
        'spell_lore': _spellLore,
        'prayer_lore': _prayerLore,
        'manifestation_lore': _manifestationLore,
        'terrain': _terrain,
        'regiment_of_renown': _regimentOfRenown,
        'tactics': _selectedTactics,
      },
    };
  }

  Future<void> _copyRoster() async {
    final faction = _selectedFaction;
    if (faction == null) return;
    if (_validationErrors.isNotEmpty) {
      _showMessage(_validationErrors.first);
      return;
    }
    final buffer = StringBuffer()
      ..writeln('Grand Alliance: ${_selectedAlliance?['name'] ?? ''}')
      ..writeln('Faction: ${faction['name']}')
      ..writeln('Points: $_totalPoints/$_pointsLimit')
      ..writeln('Battle Formation: ${_battleFormation?['name'] ?? 'None'}')
      ..writeln('Spell Lore: ${_spellLore?['name'] ?? 'None'}')
      ..writeln('Prayer Lore: ${_prayerLore?['name'] ?? 'None'}')
      ..writeln('Manifestation Lore: ${_manifestationLore?['name'] ?? 'None'}')
      ..writeln('Faction Terrain: ${_terrain?['name'] ?? 'None'}')
      ..writeln(
        'Battle Tactics: ${_selectedTactics.map(_tacticName).join(', ')}',
      )
      ..writeln();
    if (_regimentOfRenown case final regiment?) {
      buffer.writeln(
        'Regiment of Renown: ${regiment['name']} '
        '(${_regimentOfRenownPoints(regiment)} points)',
      );
      for (final link in _asMaps(regiment['units'])) {
        final warscroll = _asMap(link['warscroll']);
        if (warscroll != null) {
          buffer.writeln('  ${regimentOfRenownUnitLabel(link, warscroll)}');
        }
      }
      buffer.writeln();
    }
    for (var index = 0; index < _regiments.length; index++) {
      final regiment = _regiments[index];
      buffer.writeln('Regiment ${index + 1}');
      if (_generalIndex == index) buffer.writeln("General's regiment");
      if (regiment.hero != null) {
        buffer.writeln(
          '${regiment.hero!['name']} (${_points(regiment.hero)} points)',
        );
      }
      if (regiment.artefact != null) {
        buffer.writeln('Artefact: ${regiment.artefact!['name']}');
      }
      if (regiment.heroicTrait != null) {
        buffer.writeln('Heroic Trait: ${regiment.heroicTrait!['name']}');
      }
      for (final enhancement in regiment.otherEnhancements) {
        buffer.writeln(
          "Enhancement: ${enhancement.ability['name']}",
        );
      }
      for (final selected in regiment.units) {
        final modelCount = (selected.warscroll['modelCount'] as num?)?.toInt();
        final count = modelCount == null
            ? null
            : modelCount * (selected.reinforced ? 2 : 1);
        final reinforcement = selected.reinforced ? ' (Reinforced)' : '';
        buffer.writeln(
          '${count == null ? '' : '$count x '}${selected.warscroll['name']}$reinforcement '
          '(${selected.points} points)',
        );
        for (final enhancement in selected.enhancements) {
          buffer.writeln(
            'Unit Enhancement: ${enhancement.ability['name']}',
          );
        }
      }
      buffer.writeln();
    }
    if (_auxiliaryUnits.isNotEmpty) {
      buffer.writeln('Auxiliary Units');
      for (final unit in _auxiliaryUnits) {
        buffer.writeln('${unit.warscroll['name']} (${unit.points} points)');
        for (final enhancement in unit.enhancements) {
          buffer.writeln(
            'Unit Enhancement: ${enhancement.ability['name']}',
          );
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) _showMessage('Army list copied.');
  }

  void _showError(Object error) {
    _showMessage(error.toString());
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _selectedFaction?['name']?.toString() ??
        _selectedAlliance?['name']?.toString() ??
        'Army Builder';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _BuilderError(message: _error!, onRetry: _retry)
              : _selectedFaction != null
                  ? _buildRoster()
                  : _selectedAlliance != null
                      ? _buildFactionSelection()
                      : _buildAllianceSelection(),
    );
  }

  Future<void> _retry() {
    final alliance = _selectedAlliance;
    return alliance == null ? _loadAlliances() : _selectAlliance(alliance);
  }

  Widget _buildAllianceSelection() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Choose Grand Alliance',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final alliance in _alliances)
          Card(
            child: ListTile(
              title: Text(alliance['name']?.toString() ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectAlliance(alliance),
            ),
          ),
      ],
    );
  }

  Widget _buildFactionSelection() {
    final armyGroups = <String, List<JsonMap>>{};
    final groupNames = <String, String>{};
    for (final army in _armiesOfRenown) {
      final parentId =
          army['parentFactionKeywordId']?.toString() ?? 'unassigned';
      final parentFaction = _factions
          .where((faction) => faction['id']?.toString() == parentId)
          .firstOrNull;
      final parentName = army['parentFactionName']?.toString() ??
          parentFaction?['name']?.toString() ??
          'Other Factions';
      armyGroups.putIfAbsent(parentId, () => []).add(army);
      groupNames[parentId] = parentName;
    }
    final groupIds = armyGroups.keys.toList()
      ..sort((first, second) => groupNames[first]!
          .toLowerCase()
          .compareTo(groupNames[second]!.toLowerCase()));
    for (final group in armyGroups.values) {
      group.sort((first, second) => (first['name']?.toString() ?? '')
          .compareTo(second['name']?.toString() ?? ''));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Choose Faction', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final faction in _factions) _factionTile(faction),
        if (groupIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Armies of Renown',
              style: Theme.of(context).textTheme.titleLarge),
          for (final groupId in groupIds) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
              child: Text(
                groupNames[groupId]!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final army in armyGroups[groupId]!) _factionTile(army),
          ],
        ],
      ],
    );
  }

  Widget _factionTile(JsonMap faction) {
    return Card(
      child: ListTile(
        title: Text(faction['name']?.toString() ?? ''),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _selectFaction(faction),
      ),
    );
  }

  Widget _buildRoster() {
    if (_opponentArmy == null) return _buildRosterContent();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(child: _buildRosterContent()),
              const VerticalDivider(width: 1),
              Expanded(child: _buildOpponentArmyPanel()),
            ],
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('My Army')),
                  ButtonSegment(value: true, label: Text('Opponent')),
                ],
                selected: {_showOpponent},
                onSelectionChanged: (selection) {
                  setState(() => _showOpponent = selection.single);
                },
              ),
            ),
            Expanded(
              child: _showOpponent
                  ? _buildOpponentArmyPanel()
                  : _buildRosterContent(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRosterContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_selectedFaction?['name']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _pointsLimit,
                  decoration: const InputDecoration(labelText: 'Points limit'),
                  items: const [1000, 1500, 2000, 2500, 3000]
                      .map(
                        (limit) => DropdownMenuItem(
                          value: limit,
                          child: Text('$limit points'),
                        ),
                      )
                      .toList(),
                  onChanged: (limit) {
                    if (limit != null) setState(() => _pointsLimit = limit);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Legends units'),
                  value: _showLegends,
                  onChanged: _toggleLegends,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: (_totalPoints / _pointsLimit).clamp(0, 1).toDouble(),
                  color: _totalPoints > _pointsLimit ? Colors.red : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'Army: $_totalPoints/$_pointsLimit points',
                  style: TextStyle(
                    color: _totalPoints > _pointsLimit
                        ? Theme.of(context).colorScheme.error
                        : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                for (final error in _validationErrors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _chooseOpponentArmy,
          icon: Icon(
            _opponentArmy == null ? Icons.compare_arrows : Icons.swap_horiz,
          ),
          label: Text(
            _opponentArmy == null
                ? 'Choose Opponent Army'
                : 'Change Opponent Army',
          ),
        ),
        _buildFactionBattleTraits(),
        _buildArmyOptions(),
        _buildOtherEnhancements(),
        if (_regimentOfRenown != null ||
            _asMaps(_configuration['regiments_of_renown']).isNotEmpty)
          _buildRegimentOfRenown(),
        for (var index = 0; index < _regiments.length; index++)
          _buildRegiment(index),
        if (_regimentSlotsUsed < 5)
          OutlinedButton.icon(
            onPressed: _addRegiment,
            icon: const Icon(Icons.add),
            label: const Text('Add Regiment'),
          ),
        OutlinedButton.icon(
          onPressed: _chooseAuxiliary,
          icon: const Icon(Icons.add),
          label: const Text('Add Auxiliary Unit'),
        ),
        for (var index = 0; index < _auxiliaryUnits.length; index++)
          Card(
            child: ListTile(
              leading: DataThumbnail(
                imageUrl:
                    _auxiliaryUnits[index].warscroll['rowImage']?.toString(),
                size: 44,
              ),
              title: Text(
                _auxiliaryUnits[index].warscroll['name']?.toString() ?? '',
              ),
              subtitle:
                  Text('${_auxiliaryUnits[index].points} pts · Auxiliary'),
              onTap: () => _showItemDetails(_auxiliaryUnits[index].warscroll),
              trailing: IconButton(
                tooltip: 'Remove auxiliary unit',
                onPressed: () =>
                    setState(() => _auxiliaryUnits.removeAt(index)),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        if (_regiments.isNotEmpty)
          FilledButton.icon(
            onPressed: _validationErrors.isEmpty ? _copyRoster : null,
            icon: const Icon(Icons.copy),
            label: const Text('Copy Army List'),
          ),
        if (_selectedFaction != null)
          OutlinedButton.icon(
            onPressed: _saveArmy,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _savedArmyId == null ? 'Save Army' : 'Update Saved Army',
            ),
          ),
      ],
    );
  }

  Widget _buildOpponentArmyPanel() {
    final record = _opponentArmy!;
    final army = _asMap(record['army']);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.visibility_outlined),
          title: Text(record['name']?.toString() ?? 'Opponent Army'),
          subtitle: Text(_savedArmySummary(record)),
          trailing: IconButton(
            tooltip: 'Close opponent army',
            onPressed: () {
              setState(() {
                _opponentArmy = null;
                _opponentConfiguration = {};
                _showOpponent = false;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: army == null
              ? const Center(child: Text('Saved army data is invalid.'))
              : _buildOpponentArmyContent(army),
        ),
      ],
    );
  }

  Widget _buildOpponentArmyContent(JsonMap army) {
    final options = _asMap(army['selected_options']) ?? const {};
    final regiments = _asMaps(army['regiments']);
    final selectedOptions = <(String, Object?)>[
      ('Battle Formation', options['battle_formation']),
      ('Spell Lore', options['spell_lore']),
      ('Prayer Lore', options['prayer_lore']),
      ('Manifestation Lore', options['manifestation_lore']),
      ('Faction Terrain', options['terrain']),
    ].where((option) => _asMap(option.$2) != null).toList();
    final tactics = _asMaps(options['tactics']);
    final regimentOfRenown = _asMap(options['regiment_of_renown']);
    final battleTraits = _asMaps(_opponentConfiguration['battle_traits']);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            title: Text(
              _asMap(army['faction'])?['name']?.toString() ?? 'Faction',
            ),
            subtitle: Text(
              '${army['total_points'] ?? 0}/${army['points_limit'] ?? 2000} pts',
            ),
          ),
        ),
        if (battleTraits.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final group in battleTraits) ...[
                  ListTile(
                    leading: const Icon(Icons.military_tech_outlined),
                    title: Text(group['name']?.toString() ?? 'Battle Traits'),
                  ),
                  for (final ability in _asMaps(group['abilities']))
                    ListTile(
                      contentPadding: const EdgeInsets.only(left: 40),
                      title: Text(
                        ability['name']?.toString() ?? 'Faction ability',
                      ),
                      subtitle: ability['phaseDetails'] is String
                          ? Text(ability['phaseDetails'].toString())
                          : null,
                      trailing: const Icon(Icons.info_outline),
                      onTap: () => _showItemDetails(ability),
                    ),
                ],
              ],
            ),
          ),
        if (selectedOptions.isNotEmpty || tactics.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Army Options',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final option in selectedOptions)
                    ListTile(
                      dense: true,
                      title: Text(option.$1),
                      subtitle: Text(_itemName(option.$2)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        final item = _asMap(option.$2);
                        if (item != null) _showItemDetails(item);
                      },
                    ),
                  for (final tactic in tactics)
                    ListTile(
                      dense: true,
                      title: const Text('Battle Tactic'),
                      subtitle: Text(_tacticName(tactic)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showItemDetails(tactic),
                    ),
                ],
              ),
            ),
          ),
        if (regimentOfRenown != null)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(
                    regimentOfRenown['name']?.toString() ??
                        'Regiment of Renown',
                  ),
                  subtitle: Text(
                    '${_regimentOfRenownPoints(regimentOfRenown)} pts',
                  ),
                  trailing: const Icon(Icons.info_outline),
                  onTap: () => _showItemDetails(regimentOfRenown),
                ),
                for (final link in _asMaps(regimentOfRenown['units']))
                  if (_asMap(link['warscroll']) case final unit?)
                    _opponentUnitTile(
                      unit,
                      title: regimentOfRenownUnitLabel(link, unit),
                      enhancements: _asMaps(link['other_enhancements'])
                          .map((item) => _asMap(item['ability']))
                          .whereType<JsonMap>()
                          .toList(),
                    ),
              ],
            ),
          ),
        for (var index = 0; index < regiments.length; index++)
          _buildOpponentRegiment(regiments[index], index, army),
        if (_asMaps(army['auxiliary_units']).isNotEmpty)
          Card(
            child: Column(
              children: [
                const ListTile(title: Text('Auxiliary Units')),
                for (final selected in _asMaps(army['auxiliary_units']))
                  if (_asMap(selected['warscroll']) case final unit?)
                    _opponentUnitTile(
                      unit,
                      reinforced: selected['reinforced'] == true,
                      enhancements: _asMaps(selected['other_enhancements'])
                          .map((item) => _asMap(item['ability']))
                          .whereType<JsonMap>()
                          .toList(),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildOpponentRegiment(JsonMap regiment, int index, JsonMap army) {
    final hero = _asMap(regiment['hero']);
    final isGeneral = (army['general_index'] as num?)?.toInt() == index;
    final otherEnhancements = _asMaps(regiment['other_enhancements'])
        .map((item) => _asMap(item['ability']))
        .whereType<JsonMap>();
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text('Regiment ${index + 1}'),
            subtitle: isGeneral ? const Text("General's regiment") : null,
          ),
          if (hero != null)
            _opponentUnitTile(
              hero,
              title: hero['name']?.toString() ?? 'Hero',
              subtitle: '${_points(hero)} pts · Hero',
              enhancements: otherEnhancements.toList(),
            ),
          if (_asMap(regiment['artefact']) case final artefact?)
            ListTile(
              dense: true,
              title: const Text('Artefact'),
              subtitle: Text(artefact['name']?.toString() ?? ''),
              trailing: const Icon(Icons.info_outline),
              onTap: () => _showItemDetails(artefact),
            ),
          if (_asMap(regiment['heroic_trait']) case final trait?)
            ListTile(
              dense: true,
              title: const Text('Heroic Trait'),
              subtitle: Text(trait['name']?.toString() ?? ''),
              trailing: const Icon(Icons.info_outline),
              onTap: () => _showItemDetails(trait),
            ),
          for (final selected in _asMaps(regiment['units']))
            if (_asMap(selected['warscroll']) case final unit?)
              _opponentUnitTile(
                unit,
                reinforced: selected['reinforced'] == true,
                enhancements: _asMaps(selected['other_enhancements'])
                    .map((item) => _asMap(item['ability']))
                    .whereType<JsonMap>()
                    .toList(),
              ),
        ],
      ),
    );
  }

  Widget _opponentUnitTile(
    JsonMap unit, {
    String? title,
    String? subtitle,
    bool reinforced = false,
    List<JsonMap> enhancements = const [],
  }) {
    final modelCount = (unit['modelCount'] as num?)?.toInt();
    final count = modelCount == null ? null : modelCount * (reinforced ? 2 : 1);
    final points = _points(unit) * (reinforced ? 2 : 1);
    final enhancementNames = enhancements
        .map((enhancement) => enhancement['name']?.toString())
        .whereType<String>()
        .toList();
    return ListTile(
      dense: true,
      leading: DataThumbnail(
        imageUrl: unit['rowImage']?.toString(),
        size: 40,
      ),
      title: Text(
        title ??
            '${count == null ? '' : '$count x '}${unit['name'] ?? 'Unit'}'
                '${reinforced ? ' (Reinforced)' : ''}',
      ),
      subtitle: Text(
        [
          subtitle ?? '$points pts',
          if (enhancementNames.isNotEmpty)
            'Enhancements: ${enhancementNames.join(', ')}',
        ].join('\n'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showItemDetails(unit),
    );
  }

  String _itemName(Object? item) {
    final map = _asMap(item);
    return map?['name']?.toString() ?? 'Not selected';
  }

  Widget _buildFactionBattleTraits() {
    final groups = _asMaps(_configuration['battle_traits']);
    if (groups.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in groups) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.military_tech_outlined),
                title: Text(group['name']?.toString() ?? 'Battle Traits'),
              ),
              for (final ability in _asMaps(group['abilities']))
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 40),
                  title: Text(ability['name']?.toString() ?? 'Faction ability'),
                  subtitle: ability['phaseDetails'] is String
                      ? Text(ability['phaseDetails'].toString())
                      : null,
                  trailing: const Icon(Icons.info_outline),
                  onTap: () => _showItemDetails(ability),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArmyOptions() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Army options',
                style: Theme.of(context).textTheme.titleMedium),
            _optionTile(
              'Battle Formation',
              _battleFormation,
              () => _chooseArmyOption(
                title: 'battle formation',
                key: 'battle_formations',
                onSelected: (value) => _battleFormation = value,
              ),
            ),
            _optionTile(
              'Spell Lore',
              _spellLore,
              () => _chooseArmyOption(
                title: 'spell lore',
                key: 'spell_lores',
                onSelected: (value) => _spellLore = value,
              ),
            ),
            _optionTile(
              'Prayer Lore',
              _prayerLore,
              () => _chooseArmyOption(
                title: 'prayer lore',
                key: 'prayer_lores',
                onSelected: (value) => _prayerLore = value,
              ),
            ),
            _optionTile(
              'Manifestation Lore',
              _manifestationLore,
              () => _chooseArmyOption(
                title: 'manifestation lore',
                key: 'manifestation_lores',
                onSelected: (value) => _manifestationLore = value,
              ),
            ),
            _optionTile(
              'Faction Terrain',
              _terrain,
              () => _chooseArmyOption(
                title: 'faction terrain',
                key: 'terrain',
                onSelected: (value) => _terrain = value,
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Battle Tactics Cards'),
              subtitle: Text(
                _selectedTactics.isEmpty
                    ? 'Choose up to two cards'
                    : _selectedTactics.map(_tacticName).join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tactic in _selectedTactics)
                    IconButton(
                      tooltip: 'Show ${_tacticName(tactic)} details',
                      onPressed: () => _showItemDetails(tactic),
                      icon: const Icon(Icons.info_outline),
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: _chooseTactics,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtherEnhancements() {
    final groups = _asMaps(_asMap(_configuration['enhancements'])?['other']);
    if (groups.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                'Other Enhancements',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                for (final group in groups) ...[
                  Builder(
                    builder: (context) {
                      final groupId = group['id']?.toString();
                      final assignments = groupId == null
                          ? <_EnhancementAssignmentView>[]
                          : _enhancementAssignments(groupId);
                      final rosterLimit =
                          (group['rosterLevelLimit'] as num?)?.toInt();
                      final limitReached = rosterLimit != null &&
                          assignments.length >= rosterLimit;
                      final restriction = group['restrictionText']?.toString();
                      return Tooltip(
                        message: restriction?.replaceAll('**', '') ??
                            'Add ${group['name'] ?? 'enhancement'}',
                        child: TextButton.icon(
                          onPressed: limitReached
                              ? null
                              : () => _chooseOtherEnhancement(group),
                          icon: const Icon(Icons.add, size: 18),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(group['name']?.toString() ?? 'Enhancement'),
                              if (rosterLimit != null)
                                Text(
                                  ' ${assignments.length}/$rosterLimit',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  for (final assignment in _enhancementAssignments(
                    group['id']?.toString() ?? '',
                  ))
                    InputChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${assignment.enhancement.ability['name'] ?? 'Enhancement'}'
                        ' · ${assignment.target.warscroll['name']}'
                        ' · ${assignment.target.label}',
                      ),
                      onPressed: () =>
                          _showItemDetails(assignment.enhancement.ability),
                      onDeleted: () => setState(
                        () => _enhancementsForTarget(assignment.target)
                            .remove(assignment.enhancement),
                      ),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_EnhancementTarget> _eligibleEnhancementTargets(JsonMap group) {
    final groupId = group['id']?.toString();
    if (groupId == null) return [];
    final unitLimit = (group['unitLevelLimit'] as num?)?.toInt() ?? 1;
    final targets = <_EnhancementTarget>[];
    for (var regimentIndex = 0;
        regimentIndex < _regiments.length;
        regimentIndex++) {
      final regiment = _regiments[regimentIndex];
      final hero = regiment.hero;
      if (hero != null &&
          enhancementCanBeGivenTo(group, hero) &&
          regiment.otherEnhancements
                  .where((item) => item.groupId == groupId)
                  .length <
              unitLimit) {
        targets.add(
          _EnhancementTarget(warscroll: hero, regimentIndex: regimentIndex),
        );
      }
      for (var unitIndex = 0; unitIndex < regiment.units.length; unitIndex++) {
        final unit = regiment.units[unitIndex];
        if (enhancementCanBeGivenTo(group, unit.warscroll) &&
            unit.enhancements.where((item) => item.groupId == groupId).length <
                unitLimit) {
          targets.add(
            _EnhancementTarget(
              warscroll: unit.warscroll,
              regimentIndex: regimentIndex,
              unitIndex: unitIndex,
            ),
          );
        }
      }
    }
    for (var auxiliaryIndex = 0;
        auxiliaryIndex < _auxiliaryUnits.length;
        auxiliaryIndex++) {
      final unit = _auxiliaryUnits[auxiliaryIndex];
      if (enhancementCanBeGivenTo(group, unit.warscroll) &&
          unit.enhancements.where((item) => item.groupId == groupId).length <
              unitLimit) {
        targets.add(
          _EnhancementTarget(
            warscroll: unit.warscroll,
            auxiliaryIndex: auxiliaryIndex,
          ),
        );
      }
    }
    return targets;
  }

  List<_SelectedEnhancement> _enhancementsForTarget(
    _EnhancementTarget target,
  ) {
    if (target.auxiliaryIndex case final index?) {
      return _auxiliaryUnits[index].enhancements;
    }
    final regiment = _regiments[target.regimentIndex!];
    if (target.unitIndex case final index?) {
      return regiment.units[index].enhancements;
    }
    return regiment.otherEnhancements;
  }

  List<_EnhancementAssignmentView> _enhancementAssignments(String groupId) {
    final assignments = <_EnhancementAssignmentView>[];
    for (var regimentIndex = 0;
        regimentIndex < _regiments.length;
        regimentIndex++) {
      final regiment = _regiments[regimentIndex];
      if (regiment.hero case final hero?) {
        final target =
            _EnhancementTarget(warscroll: hero, regimentIndex: regimentIndex);
        for (final enhancement in regiment.otherEnhancements
            .where((item) => item.groupId == groupId)) {
          assignments.add(
            _EnhancementAssignmentView(
              target: target,
              enhancement: enhancement,
            ),
          );
        }
      }
      for (var unitIndex = 0; unitIndex < regiment.units.length; unitIndex++) {
        final unit = regiment.units[unitIndex];
        final target = _EnhancementTarget(
          warscroll: unit.warscroll,
          regimentIndex: regimentIndex,
          unitIndex: unitIndex,
        );
        for (final enhancement
            in unit.enhancements.where((item) => item.groupId == groupId)) {
          assignments.add(
            _EnhancementAssignmentView(
              target: target,
              enhancement: enhancement,
            ),
          );
        }
      }
    }
    for (var auxiliaryIndex = 0;
        auxiliaryIndex < _auxiliaryUnits.length;
        auxiliaryIndex++) {
      final unit = _auxiliaryUnits[auxiliaryIndex];
      final target = _EnhancementTarget(
        warscroll: unit.warscroll,
        auxiliaryIndex: auxiliaryIndex,
      );
      for (final enhancement
          in unit.enhancements.where((item) => item.groupId == groupId)) {
        assignments.add(
          _EnhancementAssignmentView(
            target: target,
            enhancement: enhancement,
          ),
        );
      }
    }
    return assignments;
  }

  Future<void> _chooseOtherEnhancement(JsonMap group) async {
    final groupId = group['id']?.toString();
    if (groupId == null) {
      _showMessage('This enhancement group has no ID.');
      return;
    }
    final assignments = _enhancementAssignments(groupId);
    final choices = availableEnhancementChoices(
      group,
      _asMaps(group['abilities']),
      assignments.map((assignment) => assignment.enhancement.ability),
    );
    if (choices.isEmpty) {
      _showMessage('No ${group['name']} choices are available.');
      return;
    }
    final rosterLimit = (group['rosterLevelLimit'] as num?)?.toInt();
    if (rosterLimit != null && assignments.length >= rosterLimit) {
      _showMessage('The limit for ${group['name']} has been reached.');
      return;
    }
    final targets = _eligibleEnhancementTargets(group);
    if (targets.isEmpty) {
      _showMessage('No eligible units are available for ${group['name']}.');
      return;
    }
    final target = await showDialog<_EnhancementTarget>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose a unit for ${group['name']}'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView(
            children: [
              for (final candidate in targets)
                ListTile(
                  leading: DataThumbnail(
                    imageUrl: candidate.warscroll['rowImage']?.toString(),
                    size: 40,
                  ),
                  title: Text(
                    candidate.warscroll['name']?.toString() ?? 'Unit',
                  ),
                  subtitle: Text(candidate.label),
                  onTap: () => Navigator.pop(context, candidate),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || target == null) return;
    final selection = await _showSelectionDialog(
      title: 'Choose ${group['name']}',
      items: choices,
      titleFor: (item) => item['name']?.toString() ?? 'Unnamed enhancement',
      subtitleFor: (item) => '${_points(item)} pts',
    );
    if (!mounted || selection == null) return;

    final recipientEnhancements = _enhancementsForTarget(target);
    final unitLimit = (group['unitLevelLimit'] as num?)?.toInt() ?? 1;
    if (recipientEnhancements.where((item) => item.groupId == groupId).length >=
        unitLimit) {
      _showMessage('The limit for this unit has been reached.');
      return;
    }
    if (rosterLimit != null &&
        _enhancementAssignments(groupId).length >= rosterLimit) {
      _showMessage('The limit for ${group['name']} has been reached.');
      return;
    }
    if (availableEnhancementChoices(
      group,
      [selection],
      _enhancementAssignments(groupId)
          .map((assignment) => assignment.enhancement.ability),
    ).isEmpty) {
      _showMessage('This ${group['name']} choice has already been selected.');
      return;
    }
    setState(
      () => recipientEnhancements.add(
        _SelectedEnhancement(groupId: groupId, ability: selection),
      ),
    );
  }

  Widget _buildRegimentOfRenown() {
    final regiment = _regimentOfRenown;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          ListTile(
            leading: regiment == null
                ? const Icon(Icons.shield_outlined)
                : DataThumbnail(
                    imageUrl: dataPreviewImageUrl(regiment),
                    size: 44,
                  ),
            title: const Text('Regiments of Renown'),
            subtitle: Text(
              regiment == null
                  ? 'Choose one for this army'
                  : '${regiment['name']} · '
                      '${_regimentOfRenownPoints(regiment)} pts',
            ),
            onTap: _chooseRegimentOfRenown,
            trailing: regiment == null
                ? const Icon(Icons.chevron_right)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Show details',
                        onPressed: () => _showItemDetails(regiment),
                        icon: const Icon(Icons.info_outline),
                      ),
                      IconButton(
                        tooltip: 'Remove Regiment of Renown',
                        onPressed: () =>
                            setState(() => _regimentOfRenown = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
          ),
          if (regiment != null)
            for (final link in _asMaps(regiment['units']))
              if (_asMap(link['warscroll']) case final warscroll?)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                  leading: DataThumbnail(
                    imageUrl: dataImageUrl(warscroll),
                    size: 32,
                  ),
                  title: Text(regimentOfRenownUnitLabel(link, warscroll)),
                  onTap: () => _showItemDetails(warscroll),
                ),
        ],
      ),
    );
  }

  Widget _optionTile(
    String title,
    JsonMap? selected,
    Future<void> Function() onTap,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: selected == null
          ? null
          : DataThumbnail(
              imageUrl: _selectionImage(selected),
              size: 40,
            ),
      title: Text(title),
      subtitle: Text(selected?['name']?.toString() ?? 'Not selected'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected != null)
            IconButton(
              tooltip: 'Show details',
              onPressed: () => _showItemDetails(selected),
              icon: const Icon(Icons.info_outline),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildRegiment(int index) {
    final regiment = _regiments[index];
    final regimentPoints = _points(regiment.hero) +
        regiment.units.fold<int>(0, (sum, unit) => sum + unit.points) +
        _points(regiment.artefact) +
        _points(regiment.heroicTrait) +
        regiment.otherEnhancements.fold<int>(
          0,
          (sum, item) => sum + _points(item.ability),
        ) +
        regiment.units.fold<int>(
          0,
          (sum, unit) =>
              sum +
              unit.enhancements.fold<int>(
                0,
                (points, item) => points + _points(item.ability),
              ),
        );
    final maxUnits = _unitLimit(index);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Regiment ${index + 1} · $regimentPoints pts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (regiment.hero != null)
                  TextButton(
                    onPressed: () => _setGeneral(index, _generalIndex != index),
                    child: Text(
                        _generalIndex == index ? 'General' : 'Set General'),
                  ),
                IconButton(
                  tooltip: 'Remove regiment',
                  onPressed: () => _removeRegiment(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (regiment.hero == null)
              OutlinedButton.icon(
                onPressed: () => _chooseHero(index),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Choose Hero'),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: DataThumbnail(
                  imageUrl: regiment.hero!['rowImage']?.toString(),
                  size: 44,
                ),
                title: Text(regiment.hero!['name']?.toString() ?? ''),
                subtitle: Text('${_points(regiment.hero)} pts · Hero'),
                onTap: () => _showItemDetails(regiment.hero!),
                trailing: IconButton(
                  tooltip: 'Change hero',
                  onPressed: () => _chooseHero(index),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
              _buildHeroEnhancements(index),
              for (var unitIndex = 0;
                  unitIndex < regiment.units.length;
                  unitIndex++)
                _buildUnit(index, unitIndex),
              Text(
                '${_unitCount(regiment)}/$maxUnits units',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _unitCount(regiment) < maxUnits
                      ? () => _addUnit(index)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Unit'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroEnhancements(int index) {
    final rawEnhancements = _configuration['enhancements'];
    final enhancements = rawEnhancements is Map<String, dynamic>
        ? rawEnhancements
        : <String, dynamic>{};
    final regiment = _regiments[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _chooseEnhancement(
                index,
                title: 'Artefact',
                choices: _asMaps(enhancements['artefacts']),
                update: (value, selection) => value.artefact = selection,
              ),
              child: Text(
                'Artefact: ${regiment.artefact?['name'] ?? 'Choose'}',
              ),
            ),
            if (regiment.artefact != null)
              IconButton(
                tooltip: 'Show artefact details',
                onPressed: () => _showItemDetails(regiment.artefact!),
                icon: const Icon(Icons.info_outline),
              ),
            TextButton(
              onPressed: () => _chooseEnhancement(
                index,
                title: 'Heroic Trait',
                choices: _asMaps(enhancements['heroic_traits']),
                update: (value, selection) => value.heroicTrait = selection,
              ),
              child: Text(
                'Heroic Trait: ${regiment.heroicTrait?['name'] ?? 'Choose'}',
              ),
            ),
            if (regiment.heroicTrait != null)
              IconButton(
                tooltip: 'Show heroic trait details',
                onPressed: () => _showItemDetails(regiment.heroicTrait!),
                icon: const Icon(Icons.info_outline),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildUnit(int regimentIndex, int unitIndex) {
    final selected = _regiments[regimentIndex].units[unitIndex];
    final unit = selected.warscroll;
    final modelCount = (unit['modelCount'] as num?)?.toInt();
    final displayedCount =
        modelCount == null ? null : modelCount * (selected.reinforced ? 2 : 1);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      leading: DataThumbnail(
        imageUrl: unit['rowImage']?.toString(),
        size: 40,
      ),
      title: Text(
        '${displayedCount == null ? '' : '$displayedCount × '}${unit['name']}',
      ),
      subtitle: Text(
        '${selected.points} pts${selected.isRequired ? ' · Required' : ''}'
        '${selected.onlyOne ? ' · One per regiment option' : ''}'
        '${selected.enhancements.isEmpty ? '' : '\nEnhancements: '
            '${selected.enhancements.map((item) => item.ability['name']).join(', ')}'}',
      ),
      onTap: () => _showItemDetails(unit),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!selected.isRequired && unit['cannotBeReinforced'] != true)
            IconButton(
              tooltip:
                  selected.reinforced ? 'Remove reinforcement' : 'Reinforce',
              onPressed: () => _toggleReinforcement(regimentIndex, unitIndex),
              icon: Icon(selected.reinforced ? Icons.remove : Icons.add),
            ),
          if (!selected.isRequired)
            IconButton(
              tooltip: 'Remove unit',
              onPressed: () => _removeUnit(regimentIndex, unitIndex),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _BuilderRegiment {
  JsonMap? hero;
  List<_SelectedUnit> units = [];
  List<JsonMap> unitChoices = [];
  JsonMap? artefact;
  JsonMap? heroicTrait;
  final List<_SelectedEnhancement> otherEnhancements = [];
}

class _SelectedUnit {
  _SelectedUnit(
    this.warscroll, {
    this.onlyOne = false,
    this.optionId,
    this.isRequired = false,
    this.reinforced = false,
  });

  final JsonMap warscroll;
  final bool onlyOne;
  final String? optionId;
  final bool isRequired;
  bool reinforced;
  final List<_SelectedEnhancement> enhancements = [];

  int get points => _points(warscroll) * (reinforced ? 2 : 1);
}

class _SelectedEnhancement {
  const _SelectedEnhancement({
    required this.groupId,
    required this.ability,
  });

  final String groupId;
  final JsonMap ability;
}

class _EnhancementTarget {
  const _EnhancementTarget({
    required this.warscroll,
    this.regimentIndex,
    this.unitIndex,
    this.auxiliaryIndex,
  });

  final JsonMap warscroll;
  final int? regimentIndex;
  final int? unitIndex;
  final int? auxiliaryIndex;

  String get label {
    final regiment = regimentIndex;
    if (auxiliaryIndex != null) {
      return 'Auxiliary unit';
    }
    if (unitIndex == null) {
      return 'Regiment ${regiment! + 1} · Hero';
    }
    return 'Regiment ${regiment! + 1}';
  }
}

class _EnhancementAssignmentView {
  const _EnhancementAssignmentView({
    required this.target,
    required this.enhancement,
  });

  final _EnhancementTarget target;
  final _SelectedEnhancement enhancement;
}

class _SelectionDialog extends StatefulWidget {
  const _SelectionDialog({
    required this.title,
    required this.items,
    required this.groupByUnitType,
    required this.titleFor,
    required this.subtitleFor,
    required this.onDetails,
  });

  final String title;
  final List<JsonMap> items;
  final bool groupByUnitType;
  final String Function(JsonMap) titleFor;
  final String Function(JsonMap) subtitleFor;
  final Future<void> Function(JsonMap) onDetails;

  @override
  State<_SelectionDialog> createState() => _SelectionDialogState();
}

class _SelectionDialogState extends State<_SelectionDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.items.where((item) {
      return widget
          .titleFor(item)
          .toLowerCase()
          .contains(_search.toLowerCase());
    }).toList();
    final groups = widget.groupByUnitType
        ? groupBuilderUnitsByType(visible)
        : [BuilderUnitTypeGroup('', visible)];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
              ),
              onChanged: (value) => setState(() => _search = value.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visible.isEmpty
                  ? const Center(child: Text('No units available.'))
                  : ListView(
                      children: [
                        for (final group in groups) ...[
                          if (group.title.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                              child: Text(
                                group.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          for (final item in group.items)
                            ListTile(
                              leading: DataThumbnail(
                                imageUrl: _selectionImage(item),
                                size: 40,
                              ),
                              title: Text(widget.titleFor(item)),
                              subtitle: Text(widget.subtitleFor(item)),
                              trailing: IconButton(
                                tooltip: 'Show details',
                                onPressed: () => widget.onDetails(item),
                                icon: const Icon(Icons.info_outline),
                              ),
                              onTap: () => Navigator.of(context).pop(item),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _TacticsSelectionDialog extends StatefulWidget {
  const _TacticsSelectionDialog({
    required this.items,
    required this.selected,
    required this.onDetails,
  });

  final List<JsonMap> items;
  final List<JsonMap> selected;
  final Future<void> Function(JsonMap) onDetails;

  @override
  State<_TacticsSelectionDialog> createState() =>
      _TacticsSelectionDialogState();
}

class _TacticsSelectionDialogState extends State<_TacticsSelectionDialog> {
  late final List<JsonMap> _selected = List<JsonMap>.from(widget.selected);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Battle Tactics Cards'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListView(
          children: [
            for (final tactic in widget.items)
              CheckboxListTile(
                title: Text(_tacticName(tactic)),
                value: _selected.any((item) => item['id'] == tactic['id']),
                secondary: IconButton(
                  tooltip: 'Show details',
                  onPressed: () => widget.onDetails(tactic),
                  icon: const Icon(Icons.info_outline),
                ),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      if (_selected.length < 2) {
                        _selected.add({
                          ...tactic,
                          'name': _tacticName(tactic),
                        });
                      }
                    } else {
                      _selected.removeWhere(
                        (item) => item['id'] == tactic['id'],
                      );
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _BuilderError extends StatelessWidget {
  const _BuilderError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

List<JsonMap> _asMaps(Object? value) {
  if (value is! List) return [];
  return value.whereType<JsonMap>().toList(growable: false);
}

JsonMap? _asMap(Object? value) {
  if (value is! Map<String, dynamic>) return null;
  return value;
}

int _points(JsonMap? unit) => (unit?['points'] as num?)?.toInt() ?? 0;

int _regimentOfRenownPoints(JsonMap? regiment) =>
    (regiment?['regimentOfRenownPointsCost'] as num?)?.toInt() ?? 0;

String? _selectionImage(JsonMap item) {
  final unit = item['unit'];
  final source = unit is Map<String, dynamic> ? unit : item;
  return dataPreviewImageUrl(source);
}

String _tacticName(JsonMap tactic) {
  final title = tactic['title']?.toString() ?? '';
  final separator = title.indexOf(' - ');
  return separator < 0 ? title : title.substring(separator + 3);
}
