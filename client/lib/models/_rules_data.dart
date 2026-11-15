part of '../rules_page.dart';

class _RulesData {
  _RulesData(this.raw);

  static const _coreDocumentsGroupId = 'e918110c-418e-4a50-90bc-484581a0fa5c';
  static const _currentHandbookGroupId = 'cf456401-f84b-4278-a63d-a4de52dde29f';
  static const _manifestationsPublicationId =
      '38c85d13-0436-48ac-adb3-1c9319b16d13';

  final JsonMap raw;

  List<JsonMap> get publications => _asMaps(raw['publications']);
  List<JsonMap> get sections => _asMaps(raw['sections']);
  List<JsonMap> get factions => _asMaps(raw['factions']);
  List<JsonMap> get regiments => _asMaps(raw['regimentsOfRenown']);
  List<JsonMap> get regimentLinks => _asMaps(raw['regimentLinks']);
  List<JsonMap> get manifestationLores => _asMaps(raw['manifestationLores']);
  List<JsonMap> get manifestationAbilities =>
      _asMaps(raw['manifestationAbilities']);
  List<JsonMap> get manifestationLinks => _asMaps(raw['manifestationLinks']);
  List<JsonMap> get warscrolls => _asMaps(raw['warscrolls']);

  List<JsonMap> get coreDocuments {
    final groupIds = {_coreDocumentsGroupId, _currentHandbookGroupId};
    final publicationIds = _asMaps(raw['publicationGroupLinks'])
        .where((link) => groupIds.contains(link['publicationGroupId']))
        .map((link) => link['publicationId'])
        .toSet();
    return publications
        .where((publication) =>
            publicationIds.contains(publication['id']) &&
            publication['id'] != _manifestationsPublicationId &&
            publication['hiddenFromSearch'] != true)
        .toList()
      ..sort(_compareNames);
  }

  List<JsonMap> regimentUnits(JsonMap regiment) {
    return regimentLinks
        .where((link) => link['abilityGroupId'] == regiment['id'])
        .map((link) {
          final warscroll = warscrollById(link['warscrollId']);
          return warscroll == null ? null : {...link, 'warscroll': warscroll};
        })
        .whereType<JsonMap>()
        .toList();
  }

  List<JsonMap> manifestationsFor(JsonMap lore) {
    return manifestationAbilities
        .where((ability) => ability['loreId'] == lore['id'])
        .expand((ability) {
          return manifestationLinks
              .where((link) => link['loreAbilityId'] == ability['id'])
              .map((link) {
            final warscroll = warscrollById(link['warscrollId']);
            if (warscroll == null) return null;
            return {...warscroll, 'summonAbility': ability};
          });
        })
        .whereType<JsonMap>()
        .toList();
  }

  JsonMap? warscrollById(Object? id) {
    return warscrolls.where((unit) => unit['id'] == id).firstOrNull;
  }
}
