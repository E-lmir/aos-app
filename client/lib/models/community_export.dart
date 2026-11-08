import 'community_regiment.dart';
import 'community_unit.dart';

class CommunityExport {
  CommunityExport({
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
  final List<CommunityRegiment> regiments;
  final List<CommunityUnit> auxiliaryUnits;
  final int? totalPoints;
  final int? pointsLimit;
}
