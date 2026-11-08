import 'models/community_export.dart';
import 'models/community_regiment.dart';
import 'models/community_unit.dart';
import 'army_list_text_utils.dart';

class CommunityArmyTextParser {
  static final _unitPattern = RegExp(
    r'^(?:(\d+)\s*x\s*)?(.+?)\s*(?:\((reinforced)\)\s*)?\(([\d,]+)\s*points?\)\s*,?$',
    caseSensitive: false,
  );
  static final _enhancementPattern =
      RegExp(r'^\[?(.+?)\]?\s*:\s*(.+?)\s*,?$');
  static final _pointsPattern = RegExp(
    r'(?:points?\s*:?\s*)?([\d,]+)\s*/\s*([\d,]+)\s*(?:pts?|points)?',
    caseSensitive: false,
  );
  static final _regimentPattern =
      RegExp(r'^regiment\s+\d+$', caseSensitive: false);
  static const _headerKeys = {
    'grand alliance',
    'faction',
    'battle formation',
    'battle tactics cards',
    'battle tactics',
    'spell lore',
    'prayer lore',
    'manifestation lore',
    'faction terrain',
    'regiment of renown',
  };

  final _headers = <String, String>{};
  final _regiments = <CommunityRegiment>[];
  final _auxiliaryUnits = <CommunityUnit>[];
  CommunityRegiment? _currentRegiment;
  bool _readingAuxiliary = false;
  bool _readingRegimentOfRenown = false;
  int? _totalPoints;
  int? _pointsLimit;

  CommunityExport parse(String text) {
    if (text.trim().isEmpty || text.length > 1024 * 1024) {
      throw const FormatException('Pasted army text is empty or too large.');
    }
    for (final rawLine in text.replaceAll('\r', '').split('\n')) {
      _parseLine(rawLine.trim());
    }
    return _createExport();
  }

  void _parseLine(String line) {
    if (line.isEmpty) return;
    if (_isSeparator(line)) {
      _resetSections();
      return;
    }
    if (line.toLowerCase().startsWith('exported with ')) return;
    if (_parsePoints(line) ||
        _startRegiment(line) ||
        _startAuxiliarySection(line) ||
        _startRegimentOfRenown(line)) {
      return;
    }
    if (_readingRegimentOfRenown) {
      _readRegimentOfRenown(line);
    } else if (_currentRegiment != null) {
      _parseRegimentLine(line);
    } else if (_readingAuxiliary) {
      _parseAuxiliaryLine(line);
    } else {
      _parseHeader(line);
    }
  }

  bool _isSeparator(String line) => RegExp(r'^[━─-]+$').hasMatch(line);

  void _resetSections() {
    _currentRegiment = null;
    _readingAuxiliary = false;
    _readingRegimentOfRenown = false;
  }

  bool _parsePoints(String line) {
    final match = _pointsPattern.firstMatch(line);
    if (match == null) return false;
    _totalPoints = parseArmyInteger(match.group(1));
    _pointsLimit = parseArmyInteger(match.group(2));
    _resetSections();
    return true;
  }

  bool _startRegiment(String line) {
    if (!_regimentPattern.hasMatch(line)) return false;
    if (_regiments.length >= 5) {
      throw const FormatException(
        'A pasted list has more than five regiments.',
      );
    }
    _currentRegiment = CommunityRegiment();
    _regiments.add(_currentRegiment!);
    _readingAuxiliary = false;
    _readingRegimentOfRenown = false;
    return true;
  }

  bool _startAuxiliarySection(String line) {
    if (line.toLowerCase() != 'auxiliary units') return false;
    _currentRegiment = null;
    _readingAuxiliary = true;
    _readingRegimentOfRenown = false;
    return true;
  }

  bool _startRegimentOfRenown(String line) {
    if (normalizeArmyText(line) != 'regiment of renown') return false;
    if (_headers.containsKey('regiment of renown')) {
      throw const FormatException(
        'The pasted list contains more than one Regiment of Renown.',
      );
    }
    _currentRegiment = null;
    _readingAuxiliary = false;
    _readingRegimentOfRenown = true;
    return true;
  }

  void _readRegimentOfRenown(String line) {
    if (!_headers.containsKey('regiment of renown')) {
      _headers['regiment of renown'] = stripPointsSuffix(line);
    }
  }

  void _parseRegimentLine(String line) {
    final regiment = _currentRegiment!;
    if (_parseUnitEnhancement(line, regiment.units)) return;
    if (_markGeneralRegiment(line, regiment)) return;
    final unit = _parseUnit(line);
    if (unit != null) {
      regiment.units.add(unit);
      return;
    }
    final enhancement = _enhancementPattern.firstMatch(line);
    if (enhancement != null) {
      regiment.enhancements[enhancement.group(1)!.trim()] =
          enhancement.group(2)!.trim();
      return;
    }
    throw FormatException('Could not parse regiment entry: $line');
  }

  void _parseAuxiliaryLine(String line) {
    if (_parseUnitEnhancement(line, _auxiliaryUnits)) return;
    final unit = _parseUnit(line);
    if (unit == null) {
      throw FormatException('Could not parse auxiliary unit: $line');
    }
    _auxiliaryUnits.add(unit);
  }

  bool _parseUnitEnhancement(String line, List<CommunityUnit> units) {
    if (!line.toLowerCase().startsWith('unit enhancement:')) return false;
    final value = line.substring('unit enhancement:'.length).trim();
    if (units.isEmpty || value.isEmpty) {
      throw const FormatException(
        'A unit enhancement must follow a listed unit.',
      );
    }
    units.last.enhancements.add(value);
    return true;
  }

  bool _markGeneralRegiment(String line, CommunityRegiment regiment) {
    if (!normalizeArmyText(line).contains('general s regiment')) return false;
    if (_regiments.where((item) => item.isGeneral).isNotEmpty) {
      throw const FormatException(
        'The pasted list marks more than one general’s regiment.',
      );
    }
    regiment.isGeneral = true;
    return true;
  }

  CommunityUnit? _parseUnit(String line) {
    final match = _unitPattern.firstMatch(line);
    if (match == null) return null;
    final name = match.group(2)!.trim();
    if (name.isEmpty) return null;
    return CommunityUnit(
      name: name,
      count: match.group(1) == null ? null : int.parse(match.group(1)!),
      reinforcedSuffix: match.group(3) != null,
    );
  }

  void _parseHeader(String line) {
    final separator = line.indexOf(':');
    if (separator <= 0) return;
    final key = normalizeArmyText(line.substring(0, separator));
    if (!_headerKeys.contains(key)) return;
    var value = line.substring(separator + 1).trim();
    if (key == 'regiment of renown' || key == 'manifestation lore') {
      value = stripPointsSuffix(value);
    }
    _headers[key] = value;
  }

  CommunityExport _createExport() {
    final allianceName = _headers['grand alliance'];
    final factionName = _headers['faction'];
    if (allianceName == null || allianceName.isEmpty) {
      throw const FormatException('The pasted text is missing Grand Alliance.');
    }
    if (factionName == null || factionName.isEmpty) {
      throw const FormatException('The pasted text is missing Faction.');
    }
    if (_regiments.isEmpty) {
      throw const FormatException('The pasted text contains no regiments.');
    }
    return CommunityExport(
      allianceName: allianceName,
      factionName: factionName,
      headers: _headers,
      regiments: _regiments,
      auxiliaryUnits: _auxiliaryUnits,
      totalPoints: _totalPoints,
      pointsLimit: _pointsLimit,
    );
  }
}
