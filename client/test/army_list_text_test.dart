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
        'battle_formations': [
          {'id': 'despoilers', 'name': 'Despoilers'},
        ],
        'spell_lores': [
          {'id': 'damned', 'name': 'Lore of the Damned'},
        ],
        'prayer_lores': [],
        'manifestation_lores': [
          {'id': 'primal-energy', 'name': 'Primal Energy'},
        ],
        'terrain': [
          {'id': 'nexus', 'name': 'Nexus Chaotica'},
        ],
        'regiments_of_renown': [
          {
            'id': 'curse-steel',
            'name': 'The Curse-Steel Battery',
            'regimentOfRenownPointsCost': 390,
          },
        ],
        'enhancements': {
          'artefacts': [
            {'id': 'artifact', 'name': "Realmwarper's Twist-rune"},
          ],
          'heroic_traits': [
            {'id': 'trait', 'name': 'Deathmonger'},
          ],
          'other': [
            {
              'id': 'banners',
              'name': 'Ensorcelled Banners',
              'abilities': [
                {'id': 'banner', 'name': 'The Banner of Screaming Flesh'},
              ],
            },
            {
              'id': 'brands',
              'name': 'Brands of the Dark Gods',
              'abilities': [
                {'id': 'brand', 'name': 'Brand of the Unaligned'},
              ],
            },
            {
              'id': 'mutations',
              'name': 'Moulder Mutations',
              'required_keywords': ['Cavalry'],
              'excluded_keywords': ['Hero'],
              'abilities': [
                {'id': 'mutation', 'name': 'Mutation'},
              ],
            },
          ],
        },
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
        'items': [
          {
            'unit': {
              'id': 'varanguard',
              'name': 'Varanguard',
              'modelCount': 3,
              'points': 290,
            },
            'option_id': 'varanguard-option',
          },
          {
            'unit': {
              'id': 'chaos-lord',
              'name': 'Chaos Lord on Daemonic Mount',
              'modelCount': 1,
              'points': 130,
            },
            'option_id': 'lord-option',
          },
          {
            'unit': {
              'id': 'chaos-knights',
              'name': 'Chaos Knights',
              'modelCount': 5,
              'points': 240,
              'referenceKeywords': 'Cavalry',
            },
            'option_id': 'knights-option',
          },
          {
            'unit': {
              'id': 'sloven-knights',
              'name': 'Scourge of Aqshy: Sloven Knights',
              'modelCount': 3,
              'points': 180,
            },
            'option_id': 'sloven-knights-option',
          },
        ],
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
