import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'army_builder_rules.dart';
import 'api_client.dart';
import 'data_details_sheet.dart';
import 'saved_army_store.dart';
import 'save_army_name_dialog.dart';
import 'unit_type_grouping.dart';

part 'models/_builder_regiment.dart';
part 'models/_selected_unit.dart';
part 'models/_selected_enhancement.dart';
part 'models/_enhancement_target.dart';
part 'models/_enhancement_assignment_view.dart';

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
    setState(() => _resetFactionState(faction));
    try {
      final factionId = faction['id'].toString();
      final result = await _fetchFactionBuilderData(factionId);
      if (!mounted) return;
      setState(() => _applyFactionBuilderData(result));
    } catch (error) {
      _showFactionLoadError(error);
    }
  }

  void _resetFactionState(JsonMap faction) {
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
  }

  Future<
      ({
        JsonMap configuration,
        List<JsonMap> tactics,
        List<JsonMap> auxiliaryChoices,
      })> _fetchFactionBuilderData(String factionId) async {
    final values = await Future.wait([
      _api.builderConfiguration(factionId),
      _api.builderTactics(),
      _api.builderAuxiliaryUnits(factionId, showLegends: _showLegends),
    ]);
    return (
      configuration: values[0] as JsonMap,
      tactics: values[1] as List<JsonMap>,
      auxiliaryChoices: values[2] as List<JsonMap>,
    );
  }

  void _applyFactionBuilderData(
    ({
      JsonMap configuration,
      List<JsonMap> tactics,
      List<JsonMap> auxiliaryChoices,
    }) data,
  ) {
    _configuration = data.configuration;
    _tactics = data.tactics;
    _auxiliaryChoices = data.auxiliaryChoices;
    _loading = false;
  }

  void _showFactionLoadError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error.toString();
      _loading = false;
    });
  }

  void _goBack() {
    if (widget.savedArmy != null) {
      _closeSavedArmy();
    } else if (_selectedFaction != null) {
      setState(_resetFactionSelection);
    } else if (_selectedAlliance != null) {
      setState(_resetAllianceSelection);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _closeSavedArmy() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _resetFactionSelection() {
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
  }

  void _resetAllianceSelection() {
    _selectedAlliance = null;
    _factions = [];
    _armiesOfRenown = [];
    _error = null;
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
      final hero = await _chooseHeroFrom(heroes, regimentIndex);
      if (!mounted || hero == null) return;
      if (!_isUniqueHero(hero, regimentIndex)) return;
      final data = await _api.builderRegimentUnits(
        heroId: hero['id'].toString(),
        factionId: faction['id'].toString(),
        showLegends: _showLegends,
      );
      if (!mounted) return;
      if (!_isUniqueHero(hero, regimentIndex)) return;
      final removed = _applyHeroSelection(regimentIndex, hero, data);
      if (removed) {
        _showMessage(
          'Enhancements not eligible for the new hero were removed.',
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<JsonMap?> _chooseHeroFrom(
    List<JsonMap> heroes,
    int regimentIndex,
  ) {
    final available = availableUniqueUnits(
      heroes,
      _allSelectedUnits(),
      except: _regiments[regimentIndex].hero,
    );
    return _showSelectionDialog(
      title: 'Choose a hero',
      items: available,
      titleFor: (item) => item['name']?.toString() ?? 'Unnamed hero',
      subtitleFor: (item) => '${_points(item)} pts',
    );
  }

  bool _isUniqueHero(JsonMap hero, int regimentIndex) {
    final isUnique = availableUniqueUnits(
      [hero],
      _allSelectedUnits(),
      except: _regiments[regimentIndex].hero,
    ).isNotEmpty;
    if (!isUnique) {
      _showMessage('A Unique unit can only be included once in an army.');
    }
    return isUnique;
  }

  bool _applyHeroSelection(
    int regimentIndex,
    JsonMap hero,
    JsonMap regimentData,
  ) {
    final regiment = _regiments[regimentIndex];
    final groups = _enhancementGroups(_configuration);
    var removed = false;
    regiment.otherEnhancements.removeWhere((enhancement) {
      final group = groups[enhancement.groupId];
      final ineligible = group == null || !enhancementCanBeGivenTo(group, hero);
      removed = removed || ineligible;
      return ineligible;
    });
    setState(() {
      regiment.hero = hero;
      regiment.units
        ..clear()
        ..addAll(
          _asMaps(regimentData['required_units'])
              .map((unit) => _SelectedUnit(unit, isRequired: true)),
        );
      regiment.unitChoices = _asMaps(regimentData['items']);
    });
    return removed;
  }

  Future<void> _toggleLegends(bool showLegends) async {
    setState(() => _showLegends = showLegends);
    final faction = _selectedFaction;
    if (faction == null) return;
    try {
      final refreshed =
          await _fetchLegendsChoices(faction['id'].toString(), showLegends);
      if (!mounted) return;
      setState(() => _applyLegendsChoices(refreshed));
    } catch (error) {
      _showError(error);
    }
  }

  Future<
      ({
        List<int> regimentIndices,
        List<JsonMap> results,
        List<JsonMap> auxiliaryChoices,
      })> _fetchLegendsChoices(String factionId, bool showLegends) async {
    final regimentIndices = <int>[];
    final requests = <Future<JsonMap>>[];
    for (var index = 0; index < _regiments.length; index++) {
      final hero = _regiments[index].hero;
      if (hero == null) continue;
      regimentIndices.add(index);
      requests.add(_api.builderRegimentUnits(
        heroId: hero['id'].toString(),
        factionId: factionId,
        showLegends: showLegends,
      ));
    }
    final choices = await _api.builderAuxiliaryUnits(
      factionId,
      showLegends: showLegends,
    );
    return (
      regimentIndices: regimentIndices,
      results: await Future.wait(requests),
      auxiliaryChoices: choices,
    );
  }

  void _applyLegendsChoices(
    ({
      List<int> regimentIndices,
      List<JsonMap> results,
      List<JsonMap> auxiliaryChoices,
    }) refreshed,
  ) {
    _auxiliaryChoices = refreshed.auxiliaryChoices;
    for (var index = 0; index < refreshed.regimentIndices.length; index++) {
      final regiment = _regiments[refreshed.regimentIndices[index]];
      final requiredUnits = _asMaps(refreshed.results[index]['required_units'])
          .map((unit) => _SelectedUnit(unit, isRequired: true));
      final selectedUnits =
          regiment.units.where((unit) => !unit.isRequired).toList();
      regiment.units
        ..clear()
        ..addAll(requiredUnits)
        ..addAll(selectedUnits);
      regiment.unitChoices = _asMaps(refreshed.results[index]['items']);
    }
  }

  Future<void> _restoreSavedArmy(JsonMap savedArmy) async {
    final parts = _savedArmyParts(savedArmy);
    if (parts == null) return;
    _selectSavedArmy(savedArmy, parts.army, parts.alliance, parts.faction);
    try {
      final restored = await _restoreSavedArmyData(parts.army, parts.faction);
      if (!mounted) return;
      _applySavedArmyData(restored);
      if (restored.removedEnhancements) {
        _showMessage(
          'Some saved enhancements were removed because they were duplicated, exceeded recipient limits, or had ineligible units.',
        );
      }
    } catch (error) {
      _showRestoreError(error);
    }
  }

  ({
    JsonMap army,
    JsonMap alliance,
    JsonMap faction,
  })? _savedArmyParts(JsonMap savedArmy) {
    final army = _asMap(savedArmy['army']);
    if (army == null) {
      _setRestoreError('Saved army data is invalid.');
      return null;
    }
    final alliance = _asMap(army['alliance']);
    final faction = _asMap(army['faction']);
    if (alliance == null || faction == null) {
      _setRestoreError('Saved army is missing its faction.');
      return null;
    }
    return (army: army, alliance: alliance, faction: faction);
  }

  void _selectSavedArmy(
    JsonMap savedArmy,
    JsonMap army,
    JsonMap alliance,
    JsonMap faction,
  ) {
    setState(() {
      _selectedAlliance = alliance;
      _selectedFaction = faction;
      _savedArmyId = savedArmy['id']?.toString();
      _savedArmyName = savedArmy['name']?.toString();
      _pointsLimit = (army['points_limit'] as num?)?.toInt() ?? 2000;
      _generalIndex = (army['general_index'] as num?)?.toInt();
    });
  }

  Future<
      ({
        JsonMap configuration,
        List<JsonMap> tactics,
        List<JsonMap> auxiliaryChoices,
      })> _fetchSavedArmyData(String factionId) async {
    final results = await Future.wait([
      _api.builderConfiguration(factionId),
      _api.builderTactics(),
      _api.builderAuxiliaryUnits(factionId, showLegends: _showLegends),
    ]);
    return (
      configuration: results[0] as JsonMap,
      tactics: results[1] as List<JsonMap>,
      auxiliaryChoices: results[2] as List<JsonMap>,
    );
  }

  Future<
      ({
        JsonMap configuration,
        List<JsonMap> tactics,
        List<JsonMap> auxiliaryChoices,
        List<_BuilderRegiment> regiments,
        List<_SelectedUnit> auxiliaryUnits,
        Object? options,
        bool removedEnhancements,
      })> _restoreSavedArmyData(JsonMap army, JsonMap faction) async {
    final data = await _fetchSavedArmyData(faction['id'].toString());
    final groups = _enhancementGroups(data.configuration);
    final regiments = await _restoreSavedRegiments(
      army,
      faction['id'].toString(),
      groups,
    );
    final auxiliaryUnits = _restoreSavedUnits(
      army['auxiliary_units'],
      groups,
      regimentUnits: false,
    );
    final removed = _pruneInvalidEnhancementAssignments(
          _asMaps(_asMap(data.configuration['enhancements'])?['other']),
          regiments.regiments,
          auxiliaryUnits.units,
        ) ||
        regiments.removedEnhancements ||
        auxiliaryUnits.removedEnhancements;
    return (
      configuration: data.configuration,
      tactics: data.tactics,
      auxiliaryChoices: data.auxiliaryChoices,
      regiments: regiments.regiments,
      auxiliaryUnits: auxiliaryUnits.units,
      options: army['selected_options'],
      removedEnhancements: removed,
    );
  }

  Map<String, JsonMap> _enhancementGroups(JsonMap configuration) => {
        for (final group in _asMaps(
          _asMap(configuration['enhancements'])?['other'],
        ))
          if (group['id']?.toString() case final id?) id: group,
      };

  Future<
      ({
        List<_BuilderRegiment> regiments,
        bool removedEnhancements,
      })> _restoreSavedRegiments(
    JsonMap army,
    String factionId,
    Map<String, JsonMap> groups,
  ) async {
    final regiments = <_BuilderRegiment>[];
    var removed = false;
    for (final saved in _asMaps(army['regiments'])) {
      final result = await _restoreSavedRegiment(saved, factionId, groups);
      if (result == null) continue;
      regiments.add(result.regiment);
      removed = removed || result.removedEnhancements;
    }
    return (regiments: regiments, removedEnhancements: removed);
  }

  Future<
      ({
        _BuilderRegiment regiment,
        bool removedEnhancements,
      })?> _restoreSavedRegiment(
    JsonMap saved,
    String factionId,
    Map<String, JsonMap> groups,
  ) async {
    final hero = _asMap(saved['hero']);
    if (hero == null) return null;
    final choices = await _api.builderRegimentUnits(
      heroId: hero['id'].toString(),
      factionId: factionId,
      showLegends: _showLegends,
    );
    final regiment = _BuilderRegiment()
      ..hero = hero
      ..unitChoices = _asMaps(choices['items'])
      ..artefact = _asMap(saved['artefact'])
      ..heroicTrait = _asMap(saved['heroic_trait']);
    final enhancements = _restoreEnhancements(
      saved['other_enhancements'],
      hero,
      groups,
    );
    regiment.otherEnhancements.addAll(enhancements.items);
    final units = _restoreSavedUnits(saved['units'], groups);
    regiment.units = units.units;
    return (
      regiment: regiment,
      removedEnhancements: enhancements.removed || units.removedEnhancements,
    );
  }

  ({
    List<_SelectedEnhancement> items,
    bool removed,
  }) _restoreEnhancements(
    Object? savedEnhancements,
    JsonMap recipient,
    Map<String, JsonMap> groups,
  ) {
    final items = <_SelectedEnhancement>[];
    var removed = false;
    for (final item in _asMaps(savedEnhancements)) {
      final groupId = item['group_id']?.toString();
      final ability = _asMap(item['ability']);
      final group = groupId == null ? null : groups[groupId];
      if (groupId == null ||
          group == null ||
          ability == null ||
          !enhancementCanBeGivenTo(group, recipient)) {
        removed = true;
        continue;
      }
      items.add(_SelectedEnhancement(groupId: groupId, ability: ability));
    }
    return (items: items, removed: removed);
  }

  ({
    List<_SelectedUnit> units,
    bool removedEnhancements,
  }) _restoreSavedUnits(
    Object? savedUnits,
    Map<String, JsonMap> groups, {
    bool regimentUnits = true,
  }) {
    final units = <_SelectedUnit>[];
    var removed = false;
    for (final item in _asMaps(savedUnits)) {
      final warscroll = _asMap(item['warscroll']);
      if (warscroll == null) continue;
      final unit = _SelectedUnit(
        warscroll,
        onlyOne: regimentUnits && item['only_one'] == true,
        optionId: regimentUnits ? item['option_id']?.toString() : null,
        isRequired: regimentUnits && item['is_required'] == true,
        reinforced: item['reinforced'] == true,
      );
      final enhancements = _restoreEnhancements(
        item['other_enhancements'],
        warscroll,
        groups,
      );
      unit.enhancements.addAll(enhancements.items);
      removed = removed || enhancements.removed;
      units.add(unit);
    }
    return (units: units, removedEnhancements: removed);
  }

  void _applySavedArmyData(
    ({
      JsonMap configuration,
      List<JsonMap> tactics,
      List<JsonMap> auxiliaryChoices,
      List<_BuilderRegiment> regiments,
      List<_SelectedUnit> auxiliaryUnits,
      Object? options,
      bool removedEnhancements,
    }) restored,
  ) {
    setState(() {
      _applyRestoredRoster(restored);
      _applyRestoredOptions(restored.options);
      _loading = false;
    });
  }

  void _applyRestoredRoster(
    ({
      JsonMap configuration,
      List<JsonMap> tactics,
      List<JsonMap> auxiliaryChoices,
      List<_BuilderRegiment> regiments,
      List<_SelectedUnit> auxiliaryUnits,
      Object? options,
      bool removedEnhancements,
    }) restored,
  ) {
    _configuration = restored.configuration;
    _tactics = restored.tactics;
    _auxiliaryChoices = restored.auxiliaryChoices;
    _regiments
      ..clear()
      ..addAll(restored.regiments);
    _auxiliaryUnits
      ..clear()
      ..addAll(restored.auxiliaryUnits);
  }

  void _applyRestoredOptions(Object? options) {
    _battleFormation = _savedOption(options, 'battle_formation');
    _spellLore = _savedOption(options, 'spell_lore');
    _prayerLore = _savedOption(options, 'prayer_lore');
    _manifestationLore = _savedOption(options, 'manifestation_lore');
    _terrain = _savedOption(options, 'terrain');
    _regimentOfRenown = _savedOption(options, 'regiment_of_renown');
    _selectedTactics
      ..clear()
      ..addAll(_asMaps(options is Map ? options['tactics'] : null));
  }

  JsonMap? _savedOption(Object? options, String key) =>
      _asMap(options is Map ? options[key] : null);

  void _setRestoreError(String message) {
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  void _showRestoreError(Object error) {
    if (!mounted) return;
    _setRestoreError(error.toString());
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
    final removedRegiments = _pruneRegiments(
      regiments,
      groupsById,
      rosterCounts,
      uniqueAbilitySelections,
    );
    final removedAuxiliary = _pruneAuxiliaryUnits(
      auxiliaryUnits,
      groupsById,
      rosterCounts,
      uniqueAbilitySelections,
    );
    return removedRegiments || removedAuxiliary;
  }

  bool _pruneRegiments(
    List<_BuilderRegiment> regiments,
    Map<String, JsonMap> groupsById,
    Map<String, int> rosterCounts,
    Set<String> uniqueAbilitySelections,
  ) {
    var removed = false;
    for (final regiment in regiments) {
      removed = _pruneRegiment(
            regiment,
            groupsById,
            rosterCounts,
            uniqueAbilitySelections,
          ) ||
          removed;
    }
    return removed;
  }

  bool _pruneRegiment(
    _BuilderRegiment regiment,
    Map<String, JsonMap> groupsById,
    Map<String, int> rosterCounts,
    Set<String> uniqueAbilitySelections,
  ) {
    var removed = false;
    if (regiment.hero case final hero?) {
      removed = _pruneRecipientEnhancements(
            hero,
            regiment.otherEnhancements,
            groupsById,
            rosterCounts,
            uniqueAbilitySelections,
          ) ||
          removed;
    }
    for (final unit in regiment.units) {
      removed = _pruneRecipientEnhancements(
            unit.warscroll,
            unit.enhancements,
            groupsById,
            rosterCounts,
            uniqueAbilitySelections,
          ) ||
          removed;
    }
    return removed;
  }

  bool _pruneAuxiliaryUnits(
    List<_SelectedUnit> units,
    Map<String, JsonMap> groupsById,
    Map<String, int> rosterCounts,
    Set<String> uniqueAbilitySelections,
  ) {
    var removed = false;
    for (final unit in units) {
      removed = _pruneRecipientEnhancements(
            unit.warscroll,
            unit.enhancements,
            groupsById,
            rosterCounts,
            uniqueAbilitySelections,
          ) ||
          removed;
    }
    return removed;
  }

  bool _pruneRecipientEnhancements(
    JsonMap warscroll,
    List<_SelectedEnhancement> enhancements,
    Map<String, JsonMap> groupsById,
    Map<String, int> rosterCounts,
    Set<String> uniqueAbilitySelections,
  ) {
    final unitCounts = <String, int>{};
    var removed = false;
    enhancements.removeWhere((enhancement) {
      final remove = _shouldRemoveEnhancement(
        enhancement,
        warscroll,
        groupsById,
        unitCounts,
        rosterCounts,
        uniqueAbilitySelections,
      );
      if (remove) {
        removed = true;
      } else {
        unitCounts[enhancement.groupId] =
            (unitCounts[enhancement.groupId] ?? 0) + 1;
        rosterCounts[enhancement.groupId] =
            (rosterCounts[enhancement.groupId] ?? 0) + 1;
      }
      return remove;
    });
    return removed;
  }

  bool _shouldRemoveEnhancement(
    _SelectedEnhancement enhancement,
    JsonMap warscroll,
    Map<String, JsonMap> groupsById,
    Map<String, int> unitCounts,
    Map<String, int> rosterCounts,
    Set<String> uniqueAbilitySelections,
  ) {
    final group = groupsById[enhancement.groupId];
    if (group == null || !enhancementCanBeGivenTo(group, warscroll)) {
      return true;
    }
    final unitLimit = (group['unitLevelLimit'] as num?)?.toInt() ?? 1;
    final rosterLimit = (group['rosterLevelLimit'] as num?)?.toInt();
    if ((unitCounts[enhancement.groupId] ?? 0) >= unitLimit ||
        (rosterLimit != null &&
            (rosterCounts[enhancement.groupId] ?? 0) >= rosterLimit)) {
      return true;
    }
    if (group['uniqueAbilitySelections'] != true) return false;
    final abilityId = enhancement.ability['id']?.toString();
    return abilityId == null ||
        !uniqueAbilitySelections.add('${enhancement.groupId}:$abilityId');
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
    final choice = await _showSelectionDialog(
      title: 'Add a unit',
      items: _availableRegimentChoices(regiment),
      groupByUnitType: true,
      titleFor: _unitChoiceTitle,
      subtitleFor: _unitChoiceSubtitle,
    );
    if (!mounted || choice == null) return;
    final unit = _validatedRegimentChoice(regimentIndex, choice);
    if (unit == null) return;
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

  List<JsonMap> _availableRegimentChoices(_BuilderRegiment regiment) =>
      regiment.unitChoices.where((choice) {
        final unit = _asMap(choice['unit']);
        if (unit == null) return false;
        final optionId = choice['option_id']?.toString();
        if (choice['only_one'] == true &&
            optionId != null &&
            regiment.units.any((selected) => selected.optionId == optionId)) {
          return false;
        }
        return availableUniqueUnits([unit], _allSelectedUnits()).isNotEmpty;
      }).toList();

  String _unitChoiceTitle(JsonMap choice) {
    final unit = _asMap(choice['unit']);
    return unit?['name']?.toString() ?? 'Unnamed unit';
  }

  String _unitChoiceSubtitle(JsonMap choice) {
    final unit = _asMap(choice['unit']);
    return unit == null ? '' : '${_points(unit)} pts';
  }

  JsonMap? _validatedRegimentChoice(int regimentIndex, JsonMap choice) {
    final regiment = _regiments[regimentIndex];
    if (_unitCount(regiment) >= _unitLimit(regimentIndex)) {
      _showMessage('This regiment has reached its unit limit.');
      return null;
    }
    final unit = _asMap(choice['unit']);
    if (unit == null) return null;
    if (availableUniqueUnits([unit], _allSelectedUnits()).isEmpty) {
      _showMessage('A Unique unit can only be included once in an army.');
      return null;
    }
    return unit;
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
    final choices = _availableRegimentOfRenownChoices();
    if (choices == null || choices.isEmpty) return;
    final selection = await _showRegimentOfRenownDialog(choices);
    if (!mounted || selection == null) return;
    if (!_isUniqueRegimentOfRenown(selection)) {
      _showMessage('A Unique unit can only be included once in an army.');
      return;
    }
    setState(() => _regimentOfRenown = selection);
  }

  List<JsonMap>? _availableRegimentOfRenownChoices() {
    final allChoices = _asMaps(_configuration['regiments_of_renown']);
    if (allChoices.isEmpty) {
      _showMessage('No Regiments of Renown are available for this faction.');
      return null;
    }
    final choices = availableUniqueRegimentsOfRenown(
      allChoices,
      _allSelectedUnits(includeRegimentOfRenown: false),
    );
    if (choices.isEmpty) {
      _showMessage(
        'No Regiments of Renown are available without repeating a Unique unit.',
      );
      return null;
    }
    return choices;
  }

  Future<JsonMap?> _showRegimentOfRenownDialog(List<JsonMap> choices) =>
      _showSelectionDialog(
        title: 'Choose Regiment of Renown',
        items: choices,
        titleFor: (item) => item['name']?.toString() ?? 'Unnamed regiment',
        subtitleFor: (item) => '${_regimentOfRenownPoints(item)} pts · '
            '${_asMaps(item['units']).length} units',
      );

  bool _isUniqueRegimentOfRenown(JsonMap selection) =>
      availableUniqueRegimentsOfRenown(
        [selection],
        _allSelectedUnits(includeRegimentOfRenown: false),
      ).isNotEmpty;

  Future<void> _chooseOpponentArmy() async {
    try {
      final choices = await _opponentArmyChoices();
      if (choices.isEmpty) {
        _showMessage('Save another army list to choose an opponent.');
        return;
      }
      if (!mounted) return;
      final selection = await _showOpponentArmyDialog(choices);
      if (!mounted || selection == null) return;
      _selectOpponentArmy(selection);
      if (_opponentFactionId(selection) case final factionId?) {
        unawaited(_loadOpponentConfiguration(factionId, selection));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<List<JsonMap>> _opponentArmyChoices() async =>
      (await _savedArmyStore.load())
          .where((army) =>
              _asMap(army['army']) != null &&
              army['id']?.toString() != _savedArmyId)
          .toList();

  Future<JsonMap?> _showOpponentArmyDialog(List<JsonMap> choices) =>
      showDialog<JsonMap>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose opponent army'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: [
                for (final army in choices) _opponentArmyChoiceTile(army),
              ],
            ),
          ),
        ),
      );

  Widget _opponentArmyChoiceTile(JsonMap army) => ListTile(
        title: Text(army['name']?.toString() ?? 'Army'),
        subtitle: Text(_savedArmySummary(army)),
        onTap: () => Navigator.pop(context, army),
      );

  void _selectOpponentArmy(JsonMap army) {
    setState(() {
      _opponentArmy = army;
      _opponentConfiguration = {};
      _showOpponent = false;
    });
  }

  String? _opponentFactionId(JsonMap armyRecord) {
    final army = _asMap(armyRecord['army']);
    final faction = _asMap(army?['faction']);
    return faction?['id']?.toString();
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
      'regiments': _serializeRegiments(),
      'auxiliary_units': _auxiliaryUnits.map(_serializeAuxiliaryUnit).toList(),
      'selected_options': _serializeOptions(),
    };
  }

  List<JsonMap> _serializeRegiments() =>
      _regiments.map(_serializeRegiment).toList();

  JsonMap _serializeRegiment(_BuilderRegiment regiment) => {
        'hero': regiment.hero,
        'units': regiment.units.map(_serializeSelectedUnit).toList(),
        'artefact': regiment.artefact,
        'heroic_trait': regiment.heroicTrait,
        'other_enhancements':
            regiment.otherEnhancements.map(_serializeEnhancement).toList(),
      };

  JsonMap _serializeSelectedUnit(_SelectedUnit unit) => {
        'warscroll': unit.warscroll,
        'only_one': unit.onlyOne,
        'option_id': unit.optionId,
        'is_required': unit.isRequired,
        'reinforced': unit.reinforced,
        'other_enhancements':
            unit.enhancements.map(_serializeEnhancement).toList(),
      };

  JsonMap _serializeAuxiliaryUnit(_SelectedUnit unit) => {
        'warscroll': unit.warscroll,
        'reinforced': unit.reinforced,
        'other_enhancements':
            unit.enhancements.map(_serializeEnhancement).toList(),
      };

  JsonMap _serializeEnhancement(_SelectedEnhancement enhancement) => {
        'group_id': enhancement.groupId,
        'ability': enhancement.ability,
      };

  JsonMap _serializeOptions() => {
        'battle_formation': _battleFormation,
        'spell_lore': _spellLore,
        'prayer_lore': _prayerLore,
        'manifestation_lore': _manifestationLore,
        'terrain': _terrain,
        'regiment_of_renown': _regimentOfRenown,
        'tactics': _selectedTactics,
      };

  Future<void> _copyRoster() async {
    final faction = _selectedFaction;
    if (faction == null) return;
    if (_validationErrors.isNotEmpty) {
      _showMessage(_validationErrors.first);
      return;
    }
    final buffer = StringBuffer();
    _writeRosterHeader(buffer, faction);
    if (_regimentOfRenown case final regiment?) {
      _writeRegimentOfRenown(buffer, regiment);
    }
    for (var index = 0; index < _regiments.length; index++) {
      _writeRegimentRoster(buffer, _regiments[index], index);
    }
    _writeAuxiliaryRoster(buffer);
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) _showMessage('Army list copied.');
  }

  void _writeRosterHeader(StringBuffer buffer, JsonMap faction) {
    buffer
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
  }

  void _writeRegimentOfRenown(StringBuffer buffer, JsonMap regiment) {
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

  void _writeRegimentRoster(
    StringBuffer buffer,
    _BuilderRegiment regiment,
    int index,
  ) {
    buffer.writeln('Regiment ${index + 1}');
    if (_generalIndex == index) buffer.writeln("General's regiment");
    _writeRegimentEnhancements(buffer, regiment);
    for (final unit in regiment.units) {
      _writeSelectedUnitRoster(buffer, unit);
    }
    buffer.writeln();
  }

  void _writeRegimentEnhancements(
    StringBuffer buffer,
    _BuilderRegiment regiment,
  ) {
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
      buffer.writeln("Enhancement: ${enhancement.ability['name']}");
    }
  }

  void _writeSelectedUnitRoster(StringBuffer buffer, _SelectedUnit unit) {
    final modelCount = (unit.warscroll['modelCount'] as num?)?.toInt();
    final count =
        modelCount == null ? null : modelCount * (unit.reinforced ? 2 : 1);
    final reinforcement = unit.reinforced ? ' (Reinforced)' : '';
    buffer.writeln(
      '${count == null ? '' : '$count x '}${unit.warscroll['name']}$reinforcement '
      '(${unit.points} points)',
    );
    _writeUnitEnhancements(buffer, unit.enhancements);
  }

  void _writeUnitEnhancements(
    StringBuffer buffer,
    List<_SelectedEnhancement> enhancements,
  ) {
    for (final enhancement in enhancements) {
      buffer.writeln('Unit Enhancement: ${enhancement.ability['name']}');
    }
  }

  void _writeAuxiliaryRoster(StringBuffer buffer) {
    if (_auxiliaryUnits.isEmpty) return;
    buffer.writeln('Auxiliary Units');
    for (final unit in _auxiliaryUnits) {
      buffer.writeln('${unit.warscroll['name']} (${unit.points} points)');
      _writeUnitEnhancements(buffer, unit.enhancements);
    }
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
    final grouped = _groupRenownArmies();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Choose Faction', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final faction in _factions) _factionTile(faction),
        ..._renownFactionEntries(grouped),
      ],
    );
  }

  ({
    Map<String, List<JsonMap>> groups,
    Map<String, String> names,
    List<String> ids,
  }) _groupRenownArmies() {
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
    return (groups: armyGroups, names: groupNames, ids: groupIds);
  }

  List<Widget> _renownFactionEntries(
    ({
      Map<String, List<JsonMap>> groups,
      Map<String, String> names,
      List<String> ids,
    }) grouped,
  ) {
    if (grouped.ids.isEmpty) return [];
    return [
      const SizedBox(height: 12),
      Text('Armies of Renown', style: Theme.of(context).textTheme.titleLarge),
      for (final id in grouped.ids) ...[
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
          child: Text(
            grouped.names[id]!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final army in grouped.groups[id]!) _factionTile(army),
      ],
    ];
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
      builder: (context, constraints) =>
          _rosterLayout(context, constraints.maxWidth),
    );
  }

  Widget _rosterLayout(BuildContext context, double width) {
    if (width >= 760) {
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
        _opponentViewToggle(),
        Expanded(
          child:
              _showOpponent ? _buildOpponentArmyPanel() : _buildRosterContent(),
        ),
      ],
    );
  }

  Widget _opponentViewToggle() => Padding(
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
      );

  Widget _buildRosterContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _rosterSummaryCard(),
        _opponentArmyButton(),
        _buildFactionBattleTraits(),
        _buildArmyOptions(),
        _buildOtherEnhancements(),
        if (_regimentOfRenown != null ||
            _asMaps(_configuration['regiments_of_renown']).isNotEmpty)
          _buildRegimentOfRenown(),
        for (var index = 0; index < _regiments.length; index++)
          _buildRegiment(index),
        ..._rosterActions(),
        ..._auxiliaryUnitCards(),
        ..._rosterSaveActions(),
      ],
    );
  }

  Widget _rosterSummaryCard() => Card(
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
              _pointsLimitDropdown(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show Legends units'),
                value: _showLegends,
                onChanged: _toggleLegends,
              ),
              _armyProgress(),
              ..._validationErrorWidgets(),
            ],
          ),
        ),
      );

  Widget _pointsLimitDropdown() => DropdownButtonFormField<int>(
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
      );

  Widget _armyProgress() => Column(
        children: [
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
        ],
      );

  List<Widget> _validationErrorWidgets() => [
        for (final error in _validationErrors)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ];

  Widget _opponentArmyButton() => OutlinedButton.icon(
        onPressed: _chooseOpponentArmy,
        icon: Icon(
          _opponentArmy == null ? Icons.compare_arrows : Icons.swap_horiz,
        ),
        label: Text(
          _opponentArmy == null
              ? 'Choose Opponent Army'
              : 'Change Opponent Army',
        ),
      );

  List<Widget> _rosterActions() => [
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
      ];

  List<Widget> _auxiliaryUnitCards() => [
        for (var index = 0; index < _auxiliaryUnits.length; index++)
          _auxiliaryUnitCard(index),
      ];

  Widget _auxiliaryUnitCard(int index) {
    final unit = _auxiliaryUnits[index];
    return Card(
      child: ListTile(
        leading: DataThumbnail(
          imageUrl: unit.warscroll['rowImage']?.toString(),
          size: 44,
        ),
        title: Text(unit.warscroll['name']?.toString() ?? ''),
        subtitle: Text('${unit.points} pts · Auxiliary'),
        onTap: () => _showItemDetails(unit.warscroll),
        trailing: IconButton(
          tooltip: 'Remove auxiliary unit',
          onPressed: () => setState(() => _auxiliaryUnits.removeAt(index)),
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }

  List<Widget> _rosterSaveActions() => [
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
      ];

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
    final regimentOfRenown = _asMap(options['regiment_of_renown']);
    final battleTraits = _asMaps(_opponentConfiguration['battle_traits']);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _opponentArmySummaryCard(army),
        if (battleTraits.isNotEmpty) _opponentBattleTraitsCard(battleTraits),
        if (_hasSelectedArmyOptions(options)) _opponentOptionsCard(options),
        if (regimentOfRenown != null)
          _opponentRegimentOfRenownCard(regimentOfRenown),
        for (var index = 0; index < regiments.length; index++)
          _buildOpponentRegiment(regiments[index], index, army),
        if (_asMaps(army['auxiliary_units']).isNotEmpty)
          _opponentAuxiliaryCard(army),
      ],
    );
  }

  Widget _opponentArmySummaryCard(JsonMap army) => Card(
        child: ListTile(
          title: Text(
            _asMap(army['faction'])?['name']?.toString() ?? 'Faction',
          ),
          subtitle: Text(
            '${army['total_points'] ?? 0}/${army['points_limit'] ?? 2000} pts',
          ),
        ),
      );

  Widget _opponentBattleTraitsCard(List<JsonMap> groups) => Card(
        child: Column(
          children: [
            for (final group in groups) ...[
              ListTile(
                leading: const Icon(Icons.military_tech_outlined),
                title: Text(group['name']?.toString() ?? 'Battle Traits'),
              ),
              for (final ability in _asMaps(group['abilities']))
                _opponentBattleTraitTile(ability),
            ],
          ],
        ),
      );

  Widget _opponentBattleTraitTile(JsonMap ability) => ListTile(
        contentPadding: const EdgeInsets.only(left: 40),
        title: Text(ability['name']?.toString() ?? 'Faction ability'),
        subtitle: ability['phaseDetails'] is String
            ? Text(ability['phaseDetails'].toString())
            : null,
        trailing: const Icon(Icons.info_outline),
        onTap: () => _showItemDetails(ability),
      );

  bool _hasSelectedArmyOptions(JsonMap options) =>
      _selectedArmyOptions(options).isNotEmpty ||
      _asMaps(options['tactics']).isNotEmpty;

  List<(String, Object?)> _selectedArmyOptions(JsonMap options) =>
      <(String, Object?)>[
        ('Battle Formation', options['battle_formation']),
        ('Spell Lore', options['spell_lore']),
        ('Prayer Lore', options['prayer_lore']),
        ('Manifestation Lore', options['manifestation_lore']),
        ('Faction Terrain', options['terrain']),
      ].where((option) => _asMap(option.$2) != null).toList();

  Widget _opponentOptionsCard(JsonMap options) {
    final selectedOptions = _selectedArmyOptions(options);
    final tactics = _asMaps(options['tactics']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Army Options',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final option in selectedOptions) _opponentOptionTile(option),
            for (final tactic in tactics) _opponentTacticTile(tactic),
          ],
        ),
      ),
    );
  }

  Widget _opponentOptionTile((String, Object?) option) => ListTile(
        dense: true,
        title: Text(option.$1),
        subtitle: Text(_itemName(option.$2)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final item = _asMap(option.$2);
          if (item != null) _showItemDetails(item);
        },
      );

  Widget _opponentTacticTile(JsonMap tactic) => ListTile(
        dense: true,
        title: const Text('Battle Tactic'),
        subtitle: Text(_tacticName(tactic)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showItemDetails(tactic),
      );

  Widget _opponentRegimentOfRenownCard(JsonMap regiment) => Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(
                regiment['name']?.toString() ?? 'Regiment of Renown',
              ),
              subtitle: Text('${_regimentOfRenownPoints(regiment)} pts'),
              trailing: const Icon(Icons.info_outline),
              onTap: () => _showItemDetails(regiment),
            ),
            for (final link in _asMaps(regiment['units']))
              if (_asMap(link['warscroll']) case final unit?)
                _opponentUnitTile(
                  unit,
                  title: regimentOfRenownUnitLabel(link, unit),
                  enhancements: _linkedEnhancements(link),
                ),
          ],
        ),
      );

  List<JsonMap> _linkedEnhancements(JsonMap link) => _asMaps(
        link['other_enhancements'],
      ).map((item) => _asMap(item['ability'])).whereType<JsonMap>().toList();

  Widget _opponentAuxiliaryCard(JsonMap army) => Card(
        child: Column(
          children: [
            const ListTile(title: Text('Auxiliary Units')),
            for (final selected in _asMaps(army['auxiliary_units']))
              if (_asMap(selected['warscroll']) case final unit?)
                _opponentUnitTile(
                  unit,
                  reinforced: selected['reinforced'] == true,
                  enhancements: _linkedEnhancements(selected),
                ),
          ],
        ),
      );

  Widget _buildOpponentRegiment(JsonMap regiment, int index, JsonMap army) {
    final hero = _asMap(regiment['hero']);
    final isGeneral = (army['general_index'] as num?)?.toInt() == index;
    return Card(
      child: Column(
        children: [
          _opponentRegimentHeading(index, isGeneral),
          if (hero != null)
            _opponentUnitTile(
              hero,
              title: hero['name']?.toString() ?? 'Hero',
              subtitle: '${_points(hero)} pts · Hero',
              enhancements: _linkedEnhancements(regiment),
            ),
          ..._opponentRegimentEnhancements(regiment),
          ..._opponentRegimentUnits(regiment),
        ],
      ),
    );
  }

  Widget _opponentRegimentHeading(int index, bool isGeneral) => ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: Text('Regiment ${index + 1}'),
        subtitle: isGeneral ? const Text("General's regiment") : null,
      );

  List<Widget> _opponentRegimentEnhancements(JsonMap regiment) => [
        if (_asMap(regiment['artefact']) case final artefact?)
          _opponentEnhancementTile('Artefact', artefact),
        if (_asMap(regiment['heroic_trait']) case final trait?)
          _opponentEnhancementTile('Heroic Trait', trait),
      ];

  Widget _opponentEnhancementTile(String label, JsonMap item) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: Text(item['name']?.toString() ?? ''),
        trailing: const Icon(Icons.info_outline),
        onTap: () => _showItemDetails(item),
      );

  List<Widget> _opponentRegimentUnits(JsonMap regiment) => [
        for (final selected in _asMaps(regiment['units']))
          if (_asMap(selected['warscroll']) case final unit?)
            _opponentUnitTile(
              unit,
              reinforced: selected['reinforced'] == true,
              enhancements: _linkedEnhancements(selected),
            ),
      ];

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
      title: _opponentUnitTitle(unit, title, count, reinforced),
      subtitle: _opponentUnitSubtitle(points, subtitle, enhancementNames),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showItemDetails(unit),
    );
  }

  Widget _opponentUnitTitle(
    JsonMap unit,
    String? title,
    int? count,
    bool reinforced,
  ) =>
      Text(
        title ??
            '${count == null ? '' : '$count x '}${unit['name'] ?? 'Unit'}'
                '${reinforced ? ' (Reinforced)' : ''}',
      );

  Widget _opponentUnitSubtitle(
    int points,
    String? subtitle,
    List<String> enhancementNames,
  ) =>
      Text(
        [
          subtitle ?? '$points pts',
          if (enhancementNames.isNotEmpty)
            'Enhancements: ${enhancementNames.join(', ')}',
        ].join('\n'),
      );

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
          children: _battleTraitWidgets(groups),
        ),
      ),
    );
  }

  List<Widget> _battleTraitWidgets(List<JsonMap> groups) => [
        for (final group in groups) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.military_tech_outlined),
            title: Text(group['name']?.toString() ?? 'Battle Traits'),
          ),
          for (final ability in _asMaps(group['abilities']))
            _battleTraitAbilityTile(ability),
        ],
      ];

  Widget _battleTraitAbilityTile(JsonMap ability) => ListTile(
        contentPadding: const EdgeInsets.only(left: 40),
        title: Text(ability['name']?.toString() ?? 'Faction ability'),
        subtitle: ability['phaseDetails'] is String
            ? Text(ability['phaseDetails'].toString())
            : null,
        trailing: const Icon(Icons.info_outline),
        onTap: () => _showItemDetails(ability),
      );

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
            ..._armyOptionEntries(),
            _battleTacticsTile(),
          ],
        ),
      ),
    );
  }

  List<Widget> _armyOptionEntries() => [
        _armyOptionEntry(
          'Battle Formation',
          _battleFormation,
          'battle formation',
          'battle_formations',
          (value) => _battleFormation = value,
        ),
        _armyOptionEntry(
          'Spell Lore',
          _spellLore,
          'spell lore',
          'spell_lores',
          (value) => _spellLore = value,
        ),
        _armyOptionEntry(
          'Prayer Lore',
          _prayerLore,
          'prayer lore',
          'prayer_lores',
          (value) => _prayerLore = value,
        ),
        _armyOptionEntry(
          'Manifestation Lore',
          _manifestationLore,
          'manifestation lore',
          'manifestation_lores',
          (value) => _manifestationLore = value,
        ),
        _armyOptionEntry(
          'Faction Terrain',
          _terrain,
          'faction terrain',
          'terrain',
          (value) => _terrain = value,
        ),
      ];

  Widget _armyOptionEntry(
    String label,
    JsonMap? selected,
    String title,
    String key,
    void Function(JsonMap?) onSelected,
  ) =>
      _optionTile(
        label,
        selected,
        () => _chooseArmyOption(
          title: title,
          key: key,
          onSelected: onSelected,
        ),
      );

  Widget _battleTacticsTile() => ListTile(
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
      );

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
            _enhancementSectionHeading(),
            _enhancementGroupActions(groups),
          ],
        ),
      ),
    );
  }

  Widget _enhancementSectionHeading() => Padding(
        padding: const EdgeInsets.only(left: 4, top: 4),
        child: Text(
          'Other Enhancements',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      );

  Widget _enhancementGroupActions(List<JsonMap> groups) => Wrap(
        spacing: 4,
        runSpacing: 0,
        children: [
          for (final group in groups) ...[
            _enhancementGroupButton(group),
            for (final assignment in _enhancementGroupAssignments(group))
              _enhancementAssignmentChip(assignment),
          ],
        ],
      );

  Widget _enhancementGroupButton(JsonMap group) {
    final assignments = _enhancementGroupAssignments(group);
    final rosterLimit = (group['rosterLevelLimit'] as num?)?.toInt();
    final limitReached =
        rosterLimit != null && assignments.length >= rosterLimit;
    final restriction = group['restrictionText']?.toString();
    return Tooltip(
      message: restriction?.replaceAll('**', '') ??
          'Add ${group['name'] ?? 'enhancement'}',
      child: TextButton.icon(
        onPressed: limitReached ? null : () => _chooseOtherEnhancement(group),
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
  }

  List<_EnhancementAssignmentView> _enhancementGroupAssignments(
    JsonMap group,
  ) {
    final groupId = group['id']?.toString();
    return groupId == null ? [] : _enhancementAssignments(groupId);
  }

  Widget _enhancementAssignmentChip(_EnhancementAssignmentView assignment) =>
      InputChip(
        visualDensity: VisualDensity.compact,
        label: Text(
          '${assignment.enhancement.ability['name'] ?? 'Enhancement'}'
          ' · ${assignment.target.warscroll['name']}'
          ' · ${assignment.target.label}',
        ),
        onPressed: () => _showItemDetails(assignment.enhancement.ability),
        onDeleted: () => setState(
          () => _enhancementsForTarget(assignment.target)
              .remove(assignment.enhancement),
        ),
      );

  List<_EnhancementTarget> _eligibleEnhancementTargets(JsonMap group) {
    final groupId = group['id']?.toString();
    if (groupId == null) return [];
    final unitLimit = (group['unitLevelLimit'] as num?)?.toInt() ?? 1;
    final targets = <_EnhancementTarget>[];
    for (var index = 0; index < _regiments.length; index++) {
      targets.addAll(
          _regimentEnhancementTargets(group, groupId, unitLimit, index));
    }
    targets.addAll(_auxiliaryEnhancementTargets(group, groupId, unitLimit));
    return targets;
  }

  List<_EnhancementTarget> _regimentEnhancementTargets(
    JsonMap group,
    String groupId,
    int unitLimit,
    int regimentIndex,
  ) {
    final regiment = _regiments[regimentIndex];
    return [
      ..._heroEnhancementTargets(group, groupId, unitLimit, regimentIndex),
      ..._regimentUnitEnhancementTargets(
        group,
        groupId,
        unitLimit,
        regiment,
        regimentIndex,
      ),
    ];
  }

  List<_EnhancementTarget> _heroEnhancementTargets(
    JsonMap group,
    String groupId,
    int unitLimit,
    int regimentIndex,
  ) {
    final regiment = _regiments[regimentIndex];
    final hero = regiment.hero;
    if (hero == null ||
        !_hasEnhancementCapacity(
          group,
          hero,
          regiment.otherEnhancements,
          groupId,
          unitLimit,
        )) {
      return [];
    }
    return [_EnhancementTarget(warscroll: hero, regimentIndex: regimentIndex)];
  }

  List<_EnhancementTarget> _regimentUnitEnhancementTargets(
    JsonMap group,
    String groupId,
    int unitLimit,
    _BuilderRegiment regiment,
    int regimentIndex,
  ) {
    final targets = <_EnhancementTarget>[];
    for (var unitIndex = 0; unitIndex < regiment.units.length; unitIndex++) {
      final unit = regiment.units[unitIndex];
      if (_hasEnhancementCapacity(
        group,
        unit.warscroll,
        unit.enhancements,
        groupId,
        unitLimit,
      )) {
        targets.add(
          _EnhancementTarget(
            warscroll: unit.warscroll,
            regimentIndex: regimentIndex,
            unitIndex: unitIndex,
          ),
        );
      }
    }
    return targets;
  }

  List<_EnhancementTarget> _auxiliaryEnhancementTargets(
    JsonMap group,
    String groupId,
    int unitLimit,
  ) {
    final targets = <_EnhancementTarget>[];
    for (var index = 0; index < _auxiliaryUnits.length; index++) {
      final unit = _auxiliaryUnits[index];
      if (_hasEnhancementCapacity(
        group,
        unit.warscroll,
        unit.enhancements,
        groupId,
        unitLimit,
      )) {
        targets.add(
          _EnhancementTarget(
            warscroll: unit.warscroll,
            auxiliaryIndex: index,
          ),
        );
      }
    }
    return targets;
  }

  bool _hasEnhancementCapacity(
    JsonMap group,
    JsonMap warscroll,
    List<_SelectedEnhancement> enhancements,
    String groupId,
    int unitLimit,
  ) =>
      enhancementCanBeGivenTo(group, warscroll) &&
      enhancements.where((item) => item.groupId == groupId).length < unitLimit;

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
    for (var index = 0; index < _regiments.length; index++) {
      _appendRegimentAssignments(assignments, groupId, index);
    }
    for (var index = 0; index < _auxiliaryUnits.length; index++) {
      _appendAuxiliaryAssignments(assignments, groupId, index);
    }
    return assignments;
  }

  void _appendRegimentAssignments(
    List<_EnhancementAssignmentView> assignments,
    String groupId,
    int regimentIndex,
  ) {
    final regiment = _regiments[regimentIndex];
    if (regiment.hero case final hero?) {
      final target =
          _EnhancementTarget(warscroll: hero, regimentIndex: regimentIndex);
      _appendAssignments(
          assignments, groupId, target, regiment.otherEnhancements);
    }
    for (var index = 0; index < regiment.units.length; index++) {
      final unit = regiment.units[index];
      final target = _EnhancementTarget(
        warscroll: unit.warscroll,
        regimentIndex: regimentIndex,
        unitIndex: index,
      );
      _appendAssignments(assignments, groupId, target, unit.enhancements);
    }
  }

  void _appendAuxiliaryAssignments(
    List<_EnhancementAssignmentView> assignments,
    String groupId,
    int index,
  ) {
    final unit = _auxiliaryUnits[index];
    final target = _EnhancementTarget(
      warscroll: unit.warscroll,
      auxiliaryIndex: index,
    );
    _appendAssignments(assignments, groupId, target, unit.enhancements);
  }

  void _appendAssignments(
    List<_EnhancementAssignmentView> assignments,
    String groupId,
    _EnhancementTarget target,
    List<_SelectedEnhancement> enhancements,
  ) {
    for (final enhancement
        in enhancements.where((item) => item.groupId == groupId)) {
      assignments.add(
        _EnhancementAssignmentView(
          target: target,
          enhancement: enhancement,
        ),
      );
    }
  }

  Future<void> _chooseOtherEnhancement(JsonMap group) async {
    final groupId = group['id']?.toString();
    if (groupId == null) {
      _showMessage('This enhancement group has no ID.');
      return;
    }
    final setup = _prepareEnhancementSelection(group, groupId);
    if (setup == null) return;
    final target = await _chooseEnhancementTarget(group, setup.targets);
    if (!mounted || target == null) return;
    final selection = await _chooseEnhancementValue(group, setup.choices);
    if (!mounted || selection == null) return;
    _assignEnhancement(group, groupId, target, selection, setup.rosterLimit);
  }

  ({
    List<JsonMap> choices,
    List<_EnhancementTarget> targets,
    int? rosterLimit,
  })? _prepareEnhancementSelection(JsonMap group, String groupId) {
    final assignments = _enhancementAssignments(groupId);
    final choices = availableEnhancementChoices(
      group,
      _asMaps(group['abilities']),
      assignments.map((assignment) => assignment.enhancement.ability),
    );
    if (choices.isEmpty) {
      _showMessage('No ${group['name']} choices are available.');
      return null;
    }
    final rosterLimit = (group['rosterLevelLimit'] as num?)?.toInt();
    if (rosterLimit != null && assignments.length >= rosterLimit) {
      _showMessage('The limit for ${group['name']} has been reached.');
      return null;
    }
    final targets = _eligibleEnhancementTargets(group);
    if (targets.isEmpty) {
      _showMessage('No eligible units are available for ${group['name']}.');
      return null;
    }
    return (choices: choices, targets: targets, rosterLimit: rosterLimit);
  }

  Future<_EnhancementTarget?> _chooseEnhancementTarget(
    JsonMap group,
    List<_EnhancementTarget> targets,
  ) =>
      showDialog<_EnhancementTarget>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Choose a unit for ${group['name']}'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: [
                for (final candidate in targets)
                  _enhancementTargetTile(candidate),
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

  Widget _enhancementTargetTile(_EnhancementTarget target) => ListTile(
        leading: DataThumbnail(
          imageUrl: target.warscroll['rowImage']?.toString(),
          size: 40,
        ),
        title: Text(target.warscroll['name']?.toString() ?? 'Unit'),
        subtitle: Text(target.label),
        onTap: () => Navigator.pop(context, target),
      );

  Future<JsonMap?> _chooseEnhancementValue(
    JsonMap group,
    List<JsonMap> choices,
  ) =>
      _showSelectionDialog(
        title: 'Choose ${group['name']}',
        items: choices,
        titleFor: (item) => item['name']?.toString() ?? 'Unnamed enhancement',
        subtitleFor: (item) => '${_points(item)} pts',
      );

  void _assignEnhancement(
    JsonMap group,
    String groupId,
    _EnhancementTarget target,
    JsonMap selection,
    int? rosterLimit,
  ) {
    final recipientEnhancements = _enhancementsForTarget(target);
    if (!_canAssignEnhancement(
      group,
      groupId,
      recipientEnhancements,
      selection,
      rosterLimit,
    )) {
      return;
    }
    setState(
      () => recipientEnhancements.add(
        _SelectedEnhancement(groupId: groupId, ability: selection),
      ),
    );
  }

  bool _canAssignEnhancement(
    JsonMap group,
    String groupId,
    List<_SelectedEnhancement> recipientEnhancements,
    JsonMap selection,
    int? rosterLimit,
  ) {
    final unitLimit = (group['unitLevelLimit'] as num?)?.toInt() ?? 1;
    if (recipientEnhancements.where((item) => item.groupId == groupId).length >=
        unitLimit) {
      _showMessage('The limit for this unit has been reached.');
      return false;
    }
    if (rosterLimit != null &&
        _enhancementAssignments(groupId).length >= rosterLimit) {
      _showMessage('The limit for ${group['name']} has been reached.');
      return false;
    }
    final assignments = _enhancementAssignments(groupId)
        .map((assignment) => assignment.enhancement.ability);
    if (availableEnhancementChoices(
      group,
      [selection],
      assignments,
    ).isNotEmpty) {
      return true;
    }
    _showMessage('This ${group['name']} choice has already been selected.');
    return false;
  }

  Widget _buildRegimentOfRenown() {
    final regiment = _regimentOfRenown;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _regimentOfRenownTile(regiment),
          ..._regimentOfRenownUnits(regiment),
        ],
      ),
    );
  }

  Widget _regimentOfRenownTile(JsonMap? regiment) => ListTile(
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
              : '${regiment['name']} · ${_regimentOfRenownPoints(regiment)} pts',
        ),
        onTap: _chooseRegimentOfRenown,
        trailing: _regimentOfRenownActions(regiment),
      );

  Widget _regimentOfRenownActions(JsonMap? regiment) {
    if (regiment == null) return const Icon(Icons.chevron_right);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Show details',
          onPressed: () => _showItemDetails(regiment),
          icon: const Icon(Icons.info_outline),
        ),
        IconButton(
          tooltip: 'Remove Regiment of Renown',
          onPressed: () => setState(() => _regimentOfRenown = null),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  List<Widget> _regimentOfRenownUnits(JsonMap? regiment) {
    if (regiment == null) return [];
    return [
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
    ];
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
    final maxUnits = _unitLimit(index);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _regimentHeader(index, regiment),
            ..._regimentContent(index, regiment, maxUnits),
          ],
        ),
      ),
    );
  }

  int _regimentPoints(_BuilderRegiment regiment) =>
      _points(regiment.hero) +
      regiment.units.fold<int>(0, (sum, unit) => sum + unit.points) +
      _points(regiment.artefact) +
      _points(regiment.heroicTrait) +
      regiment.otherEnhancements.fold<int>(
        0,
        (sum, item) => sum + _points(item.ability),
      ) +
      regiment.units.fold<int>(
        0,
        (sum, unit) => sum + _unitEnhancementPoints(unit),
      );

  int _unitEnhancementPoints(_SelectedUnit unit) => unit.enhancements.fold<int>(
        0,
        (points, item) => points + _points(item.ability),
      );

  Widget _regimentHeader(int index, _BuilderRegiment regiment) => Row(
        children: [
          Expanded(
            child: Text(
              'Regiment ${index + 1} · ${_regimentPoints(regiment)} pts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (regiment.hero != null)
            TextButton(
              onPressed: () => _setGeneral(index, _generalIndex != index),
              child: Text(_generalIndex == index ? 'General' : 'Set General'),
            ),
          IconButton(
            tooltip: 'Remove regiment',
            onPressed: () => _removeRegiment(index),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      );

  List<Widget> _regimentContent(
    int index,
    _BuilderRegiment regiment,
    int maxUnits,
  ) {
    if (regiment.hero == null) {
      return [
        OutlinedButton.icon(
          onPressed: () => _chooseHero(index),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Choose Hero'),
        ),
      ];
    }
    return [
      _regimentHeroTile(index, regiment.hero!),
      _buildHeroEnhancements(index),
      ..._regimentUnitWidgets(index, regiment, maxUnits),
    ];
  }

  List<Widget> _regimentUnitWidgets(
    int index,
    _BuilderRegiment regiment,
    int maxUnits,
  ) =>
      [
        for (var unitIndex = 0; unitIndex < regiment.units.length; unitIndex++)
          _buildUnit(index, unitIndex),
        Text(
          '${_unitCount(regiment)}/$maxUnits units',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        _addRegimentUnitButton(index, regiment, maxUnits),
      ];

  Widget _addRegimentUnitButton(
    int index,
    _BuilderRegiment regiment,
    int maxUnits,
  ) =>
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed:
              _unitCount(regiment) < maxUnits ? () => _addUnit(index) : null,
          icon: const Icon(Icons.add),
          label: const Text('Add Unit'),
        ),
      );

  Widget _regimentHeroTile(int index, JsonMap hero) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: DataThumbnail(
          imageUrl: hero['rowImage']?.toString(),
          size: 44,
        ),
        title: Text(hero['name']?.toString() ?? ''),
        subtitle: Text('${_points(hero)} pts · Hero'),
        onTap: () => _showItemDetails(hero),
        trailing: IconButton(
          tooltip: 'Change hero',
          onPressed: () => _chooseHero(index),
          icon: const Icon(Icons.edit_outlined),
        ),
      );

  Widget _buildHeroEnhancements(int index) {
    final enhancements =
        _asMap(_configuration['enhancements']) ?? const <String, dynamic>{};
    final regiment = _regiments[index];
    return Wrap(
      spacing: 8,
      children: [
        ..._heroEnhancementActions(
          index,
          'Artefact',
          regiment.artefact,
          _asMaps(enhancements['artefacts']),
          (value, selection) => value.artefact = selection,
          'Show artefact details',
        ),
        ..._heroEnhancementActions(
          index,
          'Heroic Trait',
          regiment.heroicTrait,
          _asMaps(enhancements['heroic_traits']),
          (value, selection) => value.heroicTrait = selection,
          'Show heroic trait details',
        ),
      ],
    );
  }

  List<Widget> _heroEnhancementActions(
    int index,
    String title,
    JsonMap? selected,
    List<JsonMap> choices,
    void Function(_BuilderRegiment, JsonMap?) update,
    String detailsTooltip,
  ) =>
      [
        TextButton(
          onPressed: () => _chooseEnhancement(
            index,
            title: title,
            choices: choices,
            update: update,
          ),
          child: Text('$title: ${selected?['name'] ?? 'Choose'}'),
        ),
        if (selected != null)
          IconButton(
            tooltip: detailsTooltip,
            onPressed: () => _showItemDetails(selected),
            icon: const Icon(Icons.info_outline),
          ),
      ];

  Widget _buildUnit(int regimentIndex, int unitIndex) {
    final selected = _regiments[regimentIndex].units[unitIndex];
    final unit = selected.warscroll;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 12),
      leading: DataThumbnail(
        imageUrl: unit['rowImage']?.toString(),
        size: 40,
      ),
      title: _unitTitle(unit, selected),
      subtitle: _unitSubtitle(selected),
      onTap: () => _showItemDetails(unit),
      trailing: _unitActions(regimentIndex, unitIndex, selected, unit),
    );
  }

  Widget _unitTitle(JsonMap unit, _SelectedUnit selected) {
    final count = (unit['modelCount'] as num?)?.toInt();
    final displayedCount =
        count == null ? null : count * (selected.reinforced ? 2 : 1);
    return Text(
      '${displayedCount == null ? '' : '$displayedCount × '}${unit['name']}',
    );
  }

  Widget _unitSubtitle(_SelectedUnit selected) {
    final status = [
      if (selected.isRequired) 'Required',
      if (selected.onlyOne) 'One per regiment option',
    ];
    final enhancements = selected.enhancements.isEmpty
        ? ''
        : '\nEnhancements: ${selected.enhancements.map((item) => item.ability['name']).join(', ')}';
    return Text(
      '${selected.points} pts${status.isEmpty ? '' : ' · ${status.join(' · ')}'}'
      '$enhancements',
    );
  }

  Widget _unitActions(
    int regimentIndex,
    int unitIndex,
    _SelectedUnit selected,
    JsonMap unit,
  ) =>
      Row(
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
      );
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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            _searchField(),
            const SizedBox(height: 8),
            Expanded(child: _selectionItems(context)),
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

  Widget _searchField() => TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search',
        ),
        onChanged: (value) => setState(() => _search = value.trim()),
      );

  List<JsonMap> _visibleItems() => widget.items
      .where((item) =>
          widget.titleFor(item).toLowerCase().contains(_search.toLowerCase()))
      .toList();

  List<BuilderUnitTypeGroup> _visibleGroups(List<JsonMap> visible) =>
      widget.groupByUnitType
          ? groupBuilderUnitsByType(visible)
          : [BuilderUnitTypeGroup('', visible)];

  Widget _selectionItems(BuildContext context) {
    final visible = _visibleItems();
    if (visible.isEmpty) {
      return const Center(child: Text('No units available.'));
    }
    return ListView(
      children: [
        for (final group in _visibleGroups(visible)) ...[
          if (group.title.isNotEmpty) _groupHeading(context, group.title),
          for (final item in group.items) _selectionTile(item),
        ],
      ],
    );
  }

  Widget _groupHeading(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      );

  Widget _selectionTile(JsonMap item) => ListTile(
        leading: DataThumbnail(imageUrl: _selectionImage(item), size: 40),
        title: Text(widget.titleFor(item)),
        subtitle: Text(widget.subtitleFor(item)),
        trailing: IconButton(
          tooltip: 'Show details',
          onPressed: () => widget.onDetails(item),
          icon: const Icon(Icons.info_outline),
        ),
        onTap: () => Navigator.of(context).pop(item),
      );
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
            for (final tactic in widget.items) _tacticTile(tactic),
          ],
        ),
      ),
      actions: _actions(context),
    );
  }

  Widget _tacticTile(JsonMap tactic) => CheckboxListTile(
        title: Text(_tacticName(tactic)),
        value: _selected.any((item) => item['id'] == tactic['id']),
        secondary: IconButton(
          tooltip: 'Show details',
          onPressed: () => widget.onDetails(tactic),
          icon: const Icon(Icons.info_outline),
        ),
        onChanged: (checked) => _updateSelection(tactic, checked),
      );

  void _updateSelection(JsonMap tactic, bool? checked) {
    setState(() {
      if (checked == true) {
        if (_selected.length < 2) {
          _selected.add({...tactic, 'name': _tacticName(tactic)});
        }
      } else {
        _selected.removeWhere((item) => item['id'] == tactic['id']);
      }
    });
  }

  List<Widget> _actions(BuildContext context) => [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Done'),
        ),
      ];
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
