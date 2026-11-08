import 'package:flutter_test/flutter_test.dart';

import 'package:aos_client/api_client.dart';
import 'package:aos_client/army_list_text.dart';

void main() {
  test('formats a saved army as readable list text', () {
    final text = ArmyListText.formatSavedArmy({
      'army': {
        'alliance': {'id': 'chaos', 'name': 'Chaos'},
        'faction': {'id': 'slaves', 'name': 'Slaves to Darkness'},
        'total_points': 520,
        'points_limit': 1000,
        'general_index': 0,
        'regiments': [
          {
            'hero': {'id': 'hero', 'name': 'Abraxia', 'points': 230},
            'units': [
              {
                'warscroll': {
                  'id': 'varanguard',
                  'name': 'Varanguard',
                  'modelCount': 3,
                  'points': 290,
                },
                'reinforced': false,
                'other_enhancements': [
                  {
                    'group_id': 'mutations',
                    'ability': {'id': 'mutation', 'name': 'Mutation'},
                  },
                ],
              },
            ],
            'artefact': null,
            'heroic_trait': null,
            'other_enhancements': [],
          },
        ],
        'auxiliary_units': [],
        'selected_options': {
          'battle_formation': null,
          'spell_lore': null,
          'prayer_lore': null,
          'manifestation_lore': null,
          'terrain': null,
          'regiment_of_renown': null,
          'tactics': [],
        },
      },
    });

    expect(text, contains('Grand Alliance: Chaos'));
    expect(text, contains('Points: 520/1000'));
    expect(text, contains("General's regiment"));
    expect(text, contains('3 x Varanguard (290 points)'));
    expect(text, contains('Unit Enhancement: Mutation'));
    expect(text, isNot(startsWith('AOS-')));
  });

  test('imports a Community App text export into a builder army', () async {
    final api = _ImportApiClient();
    const text = '''
Grand Alliance: Chaos
Faction: Slaves to Darkness
Battle Formation: Despoilers
Battle Tactics Cards: Flanking Firestorm and Smokescreen
Drops: 1

Spell Lore: Lore of the Damned
Faction Terrain: Nexus Chaotica
━━━━━━━━━━
Regiment 1
General's regiment
1 x Abraxia, Spear of the Everchosen (230 points),
6 x Varanguard (580 points),
1 x Chaos Lord on Daemonic Mount (130 points)
[Artefact]: Realmwarper's Twist-rune
[Heroic Trait]: Deathmonger,
10 x Chaos Knights (480 points),
[Ensorcelled Banners]: The Banner of Screaming Flesh,
10 x Chaos Knights (480 points),
[Brands of the Dark Gods]: Brand of the Unaligned
Unit Enhancement: Mutation
━━━━━━━━━━

Wounds: 132
1900/2000 Pts

Exported with Age of Sigmar Community App (Data Version: v488)
''';

    final army = await ArmyListText.importText(text, api);
    final regiment = (army['regiments'] as List).single as Map;
    final units = regiment['units'] as List;
    final options = army['selected_options'] as Map;
    final otherEnhancements = regiment['other_enhancements'] as List;

    expect(army['faction_name'], 'Slaves to Darkness');
    expect(army['total_points'], 1900);
    expect(army['points_limit'], 2000);
    expect(regiment['hero']['name'], 'Abraxia, Spear of the Everchosen');
    expect(units, hasLength(4));
    expect(
      units.map((unit) => unit['reinforced']),
      [true, false, true, true],
    );
    expect(regiment['artefact']['name'], "Realmwarper's Twist-rune");
    expect(regiment['heroic_trait']['name'], 'Deathmonger');
    expect(otherEnhancements, hasLength(2));
    expect(
      ((units.last as Map)['other_enhancements'] as List).single['ability']
          ['name'],
      'Mutation',
    );
    expect(options['battle_formation']['name'], 'Despoilers');
    expect(options['spell_lore']['name'], 'Lore of the Damned');
    expect(options['terrain']['name'], 'Nexus Chaotica');
    expect(
      options['tactics'].map((tactic) => tactic['title']),
      [
        'Battle Tactic - Flanking Firestorm',
        'Battle Tactic - Smokescreen',
      ],
    );
    api.close();
  });

  test('imports the builder readable text format', () async {
    final api = _ImportApiClient();
    const text = '''
Grand Alliance: Chaos
Faction: Slaves to Darkness
Points: 520/1000
Battle Formation: None
Battle Tactics: None

Regiment 1
General's regiment
Abraxia, Spear of the Everchosen (230 points)
Artefact: Realmwarper's Twist-rune
Varanguard (290 points)
''';

    final army = await ArmyListText.importText(text, api);
    final regiment = (army['regiments'] as List).single as Map;

    expect(army['total_points'], 520);
    expect(army['points_limit'], 1000);
    expect(regiment['artefact']['name'], "Realmwarper's Twist-rune");
    expect((regiment['units'] as List).single['reinforced'], isFalse);
    expect((army['selected_options'] as Map)['battle_formation'], isNull);
    api.close();
  });

  test('imports colon-bearing units, lore costs, and Regiment of Renown',
      () async {
    final api = _ImportApiClient();
    const text = '''
Grand Alliance: Chaos
Faction: Slaves to Darkness
Manifestation Lore: Primal Energy (10 pts)
━━━━━━━━━━
Regiment 1
General's regiment
1 x Abraxia, Spear of the Everchosen (230 points)
3 x Scourge of Aqshy: Sloven Knights (180 points)
━━━━━━━━━━
Regiment Of Renown
The Curse-Steel Battery (390 points)
1 x Deathshrieker Rocket Battery (190 points)
━━━━━━━━━━
2000/2000 Pts
''';

    final army = await ArmyListText.importText(text, api);
    final regiment = (army['regiments'] as List).single as Map;
    final units = regiment['units'] as List;
    final options = army['selected_options'] as Map;

    expect(units, hasLength(1));
    expect(
      ((units.single as Map)['warscroll'] as Map)['name'],
      'Scourge of Aqshy: Sloven Knights',
    );
    expect(options['manifestation_lore']['name'], 'Primal Energy');
    expect(options['regiment_of_renown']['name'], 'The Curse-Steel Battery');
    api.close();
  });
}

class _ImportApiClient extends ApiClient {
  _ImportApiClient() : super(baseUrl: 'http://localhost:3000');

  @override
  Future<List<JsonMap>> builderAlliances() async => [
        {'id': 'chaos', 'name': 'Chaos'},
      ];

  @override
  Future<JsonMap> builderFactions(String allianceId) async => {
        'factions': [
          {'id': 'slaves', 'name': 'Slaves to Darkness'},
        ],
        'armies_of_renown': [],
      };

  @override
  Future<JsonMap> builderConfiguration(String factionId) async => {
        'battle_formations': _namedItems('despoilers', 'Despoilers'),
        'spell_lores': _namedItems('damned', 'Lore of the Damned'),
        'prayer_lores': <JsonMap>[],
        'manifestation_lores': _namedItems('primal-energy', 'Primal Energy'),
        'terrain': _namedItems('nexus', 'Nexus Chaotica'),
        'regiments_of_renown': [
          {
            'id': 'curse-steel',
            'name': 'The Curse-Steel Battery',
            'regimentOfRenownPointsCost': 390,
          },
        ],
        'enhancements': {
          'artefacts': _namedItems('artifact', "Realmwarper's Twist-rune"),
          'heroic_traits': _namedItems('trait', 'Deathmonger'),
          'other': _otherEnhancements(),
        },
      };

  List<JsonMap> _namedItems(String id, String name) => [
        {'id': id, 'name': name},
      ];

  List<JsonMap> _otherEnhancements() => [
        _enhancementGroup(
          'banners',
          'Ensorcelled Banners',
          {'id': 'banner', 'name': 'The Banner of Screaming Flesh'},
        ),
        _enhancementGroup(
          'brands',
          'Brands of the Dark Gods',
          {'id': 'brand', 'name': 'Brand of the Unaligned'},
        ),
        _enhancementGroup(
          'mutations',
          'Moulder Mutations',
          {'id': 'mutation', 'name': 'Mutation'},
          requiredKeywords: ['Cavalry'],
          excludedKeywords: ['Hero'],
        ),
      ];

  JsonMap _enhancementGroup(
    String id,
    String name,
    JsonMap ability, {
    List<String>? requiredKeywords,
    List<String>? excludedKeywords,
  }) =>
      {
        'id': id,
        'name': name,
        if (requiredKeywords != null) 'required_keywords': requiredKeywords,
        if (excludedKeywords != null) 'excluded_keywords': excludedKeywords,
        'abilities': [ability],
      };

  @override
  Future<List<JsonMap>> builderHeroes(
    String factionId, {
    String search = '',
    bool showLegends = false,
  }) async =>
      [
        {
          'id': 'abraxia',
          'name': 'Abraxia, Spear of the Everchosen',
          'modelCount': 1,
          'points': 230,
        },
      ];

  @override
  Future<JsonMap> builderRegimentUnits({
    required String heroId,
    required String factionId,
    bool showLegends = false,
  }) async =>
      {
        'required_units': [],
        'items': _regimentChoices(),
      };

  List<JsonMap> _regimentChoices() => [
        _unitChoice('varanguard', 'Varanguard', 3, 290, 'varanguard-option'),
        _unitChoice(
          'chaos-lord',
          'Chaos Lord on Daemonic Mount',
          1,
          130,
          'lord-option',
        ),
        _unitChoice(
          'chaos-knights',
          'Chaos Knights',
          5,
          240,
          'knights-option',
          referenceKeywords: 'Cavalry',
        ),
        _unitChoice(
          'sloven-knights',
          'Scourge of Aqshy: Sloven Knights',
          3,
          180,
          'sloven-knights-option',
        ),
      ];

  JsonMap _unitChoice(
    String id,
    String name,
    int modelCount,
    int points,
    String optionId, {
    String? referenceKeywords,
  }) =>
      {
        'unit': {
          'id': id,
          'name': name,
          'modelCount': modelCount,
          'points': points,
          if (referenceKeywords != null) 'referenceKeywords': referenceKeywords,
        },
        'option_id': optionId,
      };

  @override
  Future<List<JsonMap>> builderAuxiliaryUnits(
    String factionId, {
    bool showLegends = false,
  }) async =>
      [];

  @override
  Future<List<JsonMap>> builderTactics() async => [
        {'id': 'flanking', 'title': 'Battle Tactic - Flanking Firestorm'},
        {'id': 'smokescreen', 'title': 'Battle Tactic - Smokescreen'},
      ];
}
