import '../api_client.dart';

class ArmyListImportData {
  const ArmyListImportData({
    required this.alliance,
    required this.faction,
    required this.configuration,
    required this.heroes,
    required this.auxiliaryChoices,
    required this.tactics,
  });

  final JsonMap alliance;
  final JsonMap faction;
  final JsonMap configuration;
  final List<JsonMap> heroes;
  final List<JsonMap> auxiliaryChoices;
  final List<JsonMap> tactics;
}
