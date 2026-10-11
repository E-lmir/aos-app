import 'package:aos_client/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repository = OfflineDatabaseRepository({
    'metadata': {'data_version': 1},
    'data': {
      'faction_keyword': [
        {
          'id': 'alliance',
          'name': 'Grand Alliance Order',
          'parentFactionKeywordId': null,
        },
        {
          'id': 'faction',
          'name': 'Order',
          'parentFactionKeywordId': 'alliance'
        },
      ],
      'keyword': [
        {'id': 'infantry', 'name': 'Infantry'},
        {'id': 'forbidden', 'name': 'Forbidden'},
      ],
      'warscroll': [
        {
          'id': 'hero',
          'name': 'Hero',
          'referenceKeywords': 'Hero',
          'rowImage': 'https://images.example/hero.jpg',
        },
        {
          'id': 'manifestation',
          'name': 'Summoned Manifestation',
          'referenceKeywords': 'Manifestation',
        },
        {'id': 'legal', 'name': 'Legal Infantry', 'points': 100},
        {'id': 'excluded', 'name': 'Forbidden Infantry', 'points': 100},
        {
          'id': 'required',
          'name': 'Required Unit',
          'points': 50,
          'requiredPrimaryHeroWarscrollId': 'hero',
        },
      ],
      'warscroll_faction_keyword': [
        {'factionKeywordId': 'faction', 'warscrollId': 'hero'},
        {'factionKeywordId': 'faction', 'warscrollId': 'legal'},
        {'factionKeywordId': 'faction', 'warscrollId': 'excluded'},
        {'factionKeywordId': 'faction', 'warscrollId': 'required'},
      ],
      'warscroll_regiment_option': [
        {
          'id': 'option',
          'warscrollId': 'hero',
          'childQuantity': 'any',
          'requiredRosterFactionKeywordId': null,
        },
      ],
      'warscroll_regiment_option_required_keyword': [
        {'warscrollRegimentOptionId': 'option', 'keywordId': 'infantry'},
      ],
      'warscroll_regiment_option_excluded_keyword': [
        {'warscrollRegimentOptionId': 'option', 'keywordId': 'forbidden'},
      ],
      'warscroll_keyword': [
        {'warscrollId': 'legal', 'keywordId': 'infantry'},
        {'warscrollId': 'excluded', 'keywordId': 'infantry'},
        {'warscrollId': 'excluded', 'keywordId': 'forbidden'},
      ],
      'warscroll_ability': [
        {
          'id': 'ability',
          'warscrollId': 'hero',
          'name': 'Hero ability',
          'effect': 'An ability description.',
        },
      ],
      'warscroll_ability_keyword': [
        {'warscrollAbilityId': 'ability', 'keywordId': 'infantry'},
      ],
      'warscroll_weapon': [
        {
          'id': 'weapon',
          'warscrollId': 'hero',
          'name': 'Blade',
          'type': 'melee',
        },
        {
          'id': 'ranged-weapon',
          'warscrollId': 'hero',
          'name': 'Javelin',
          'type': 'ranged',
        },
      ],
      'warscroll_weapon_weapon_ability': [
        {
          'warscrollWeaponId': 'weapon',
          'weaponAbilityId': [
            'weapon-ability',
            'legacy-anti-infantry',
            'anti-war-machine',
          ],
        },
        {'warscrollWeaponId': 'ranged-weapon', 'weaponAbilityId': null},
      ],
      'weapon_ability': [
        {
          'id': 'weapon-ability',
          'name': 'Anti-INFANTRY (+1 Rend)',
          'rules': 'Weapon rules.',
        },
        {
          'id': 'legacy-anti-infantry',
          'name': 'Anti\u2011**Infantry** (+1 Rend)',
          'rules': null,
        },
        {
          'id': 'anti-war-machine',
          'name': 'Anti-WAR MACHINE (+1 Rend)',
          'rules': 'Bonus against War Machines.',
        },
      ],
      'ability': [
        {
          'id': 'battle-trait',
          'abilityGroupId': 'battle-traits',
          'name': 'Battle Trait',
          'effect': 'Battle trait effect.',
        },
        {
          'id': 'other-enhancement',
          'abilityGroupId': 'other-enhancements',
          'name': 'Test Enhancement',
        },
        {
          'id': 'regiment-ability',
          'abilityGroupId': 'regiment-of-renown',
          'name': 'Regiment Ability',
          'effect': 'A regiment ability effect.',
          'displayOrder': 1,
        },
        {
          'id': 'tactic-ability',
          'name': 'Tactic ability',
          'effect': 'Tactic effect.',
        },
      ],
      'ability_group': [
        {
          'id': 'battle-traits',
          'factionId': 'faction',
          'name': 'Test Battle Traits',
          'abilityGroupType': 'battleTraits',
        },
        {
          'id': 'other-enhancements',
          'factionId': 'faction',
          'name': 'Test Enhancements',
          'abilityGroupType': 'otherEnhancements',
          'rosterLevelLimit': 1,
          'unitLevelLimit': 1,
          'uniqueAbilitySelections': true,
        },
        {
          'id': 'regiment-of-renown',
          'name': 'Test Regiment of Renown',
          'abilityGroupType': 'regimentOfRenown',
          'image': 'https://images.example/renown.jpg',
          'regimentOfRenownPointsCost': 300,
          'isLegends': false,
        },
        {
          'id': 'legends-regiment-of-renown',
          'name': 'Legends Regiment of Renown',
          'abilityGroupType': 'regimentOfRenown',
          'isLegends': true,
        },
        {
          'id': 'unavailable-regiment-of-renown',
          'name': 'Unavailable Regiment of Renown',
          'abilityGroupType': 'regimentOfRenown',
          'isLegends': false,
        },
      ],
      'ability_group_regiment_of_renown_permitted_faction_keyword': [
        {
          'abilityGroupId': 'regiment-of-renown',
          'factionKeywordId': 'faction',
        },
        {
          'abilityGroupId': 'legends-regiment-of-renown',
          'factionKeywordId': 'faction',
        },
      ],
      'ability_group_regiment_of_renown_linked_warscroll': [
        {
          'abilityGroupId': 'regiment-of-renown',
          'warscrollId': 'hero',
          'minCount': 1,
          'maxCount': 1,
        },
      ],
      'ability_group_required_keyword': [
        {
          'abilityGroupId': 'other-enhancements',
          'keywordId': 'infantry',
        },
      ],
      'ability_group_excluded_keyword': [
        {
          'abilityGroupId': 'other-enhancements',
          'keywordId': 'forbidden',
        },
      ],
      'ability_group_required_warscroll': [
        {
          'abilityGroupId': 'other-enhancements',
          'warscrollId': 'hero',
        },
      ],
      'ability_keyword': [
        {'abilityId': 'tactic-ability', 'keywordId': 'infantry'},
        {'abilityId': 'regiment-ability', 'keywordId': 'infantry'},
      ],
      'rule_container': [
        {
          'id': 'tactic',
          'ruleSectionId': '03e7448e-15e4-498c-b5c8-971ec5224757',
          'title': 'Battle Tactics Card - Test',
        },
        {
          'id': 'core-rule',
          'ruleSectionId': 'test-rules',
          'title': 'Core rule',
          'displayOrder': 1,
        },
      ],
      'rule_container_component': [
        {
          'id': 'tactic-component',
          'ruleContainerId': 'tactic',
          'contentType': 'ability',
          'abilityId': 'tactic-ability',
          'displayOrder': 1,
        },
        {
          'id': 'battle-tactic-component',
          'ruleContainerId': 'tactic',
          'contentType': 'battleTactic',
          'battleTacticId': 'battle-tactic',
          'displayOrder': 2,
        },
        {
          'id': 'core-rule-text',
          'ruleContainerId': 'core-rule',
          'contentType': 'text',
          'textContent': 'Rules text.',
          'displayOrder': 1,
        },
      ],
      'battle_tactic': [
        {
          'id': 'battle-tactic',
          'name': 'Claim the Field',
          'battleTacticType': 'domination',
          'rulesText': 'Control the objective.',
          'victoryPoints': 5,
        },
      ],
      'battle_formation': [
        {
          'id': 'formation',
          'factionId': 'faction',
          'name': 'Test Formation',
          'publicationId': 'art-publication',
        },
      ],
      'battle_formation_rule': [],
      'lore': [
        {
          'id': 'spell-lore',
          'factionId': 'faction',
          'name': 'Lore of Test Spells',
          'publicationId': 'art-publication',
        },
        {
          'id': 'prayer-lore',
          'factionId': 'faction',
          'name': 'Prayer Lore',
          'publicationId': 'art-publication',
        },
        {
          'id': 'manifestation-lore',
          'factionId': null,
          'name': 'Universal Manifestations',
          'publicationId': '38c85d13-0436-48ac-adb3-1c9319b16d13',
        },
      ],
      'lore_ability': [
        {
          'id': 'summon-manifestation',
          'loreId': 'manifestation-lore',
          'name': 'Summon Manifestation',
          'castingValue': 7,
        },
      ],
      'lore_ability_linked_warscroll': [
        {
          'loreAbilityId': 'summon-manifestation',
          'warscrollId': 'manifestation',
        },
      ],
      'publication': [
        {
          'id': 'art-publication',
          'name': 'Core Rules',
          'backgroundImage': 'https://images.example/publication.jpg',
        },
      ],
      'bullet_point': [],
      'publication_group': [
        {
          'id': 'e918110c-418e-4a50-90bc-484581a0fa5c',
          'name': 'Core Documents',
        },
      ],
      'publication_publication_group': [
        {
          'publicationId': 'art-publication',
          'publicationGroupId': 'e918110c-418e-4a50-90bc-484581a0fa5c',
        },
      ],
      'rule_section': [
        {
          'id': 'test-rules',
          'name': 'Core Rules',
          'displayOrder': 1,
          'publicationId': 'art-publication',
          'parentId': null,
        },
      ],
      'warscroll_publication': [],
    },
  });

  test('normalizes alliances and filters faction heroes', () {
    expect(repository.alliances().single['name'], 'Order');
    expect(repository.heroes('faction').map((unit) => unit['id']), ['hero']);
  });

  test('applies regiment keywords and includes required units offline', () {
    final result = repository.regimentUnits(
      heroId: 'hero',
      factionId: 'faction',
    );

    expect(result['items'], hasLength(1));
    expect((result['items'] as List).single['unit']['id'], 'legal');
    expect((result['required_units'] as List).single['id'], 'required');
  });

  test('matches special hero roles in regiment options offline', () {
    final roleRepository = OfflineDatabaseRepository({
      'metadata': {'data_version': 1},
      'data': {
        'faction_keyword': [
          {'id': 'maggotkin', 'name': 'Maggotkin of Nurgle'},
        ],
        'keyword': [
          {'id': 'hero', 'name': 'Hero'},
          {'id': 'rotbringers', 'name': 'Rotbringers'},
          {'id': 'rotbringer-lord', 'name': 'Rotbringer Lord'},
          {'id': 'plague-scion', 'name': 'Plague Scion'},
        ],
        'warscroll': [
          {
            'id': 'gutrot',
            'name': 'Gutrot Spume',
            'referenceKeywords': 'Hero, Maggotkin of Nurgle, Rotbringers',
          },
          {
            'id': 'great-unclean-one',
            'name': 'Great Unclean One',
            'referenceKeywords': 'Hero, Maggotkin of Nurgle',
          },
          {
            'id': 'lord-of-plagues',
            'name': 'Lord of Plagues',
            'referenceKeywords': 'Hero, Maggotkin of Nurgle, Rotbringers',
            'notes':
                'This **HERO** can join an eligible regiment as a *Rotbringer Lord*.',
          },
          {
            'id': 'poxbringer',
            'name': 'Poxbringer',
            'referenceKeywords': 'Hero, Maggotkin of Nurgle',
            'notes':
                'This **HERO** can join an eligible regiment as a *Plague Scion*.',
          },
        ],
        'warscroll_faction_keyword': [
          {'factionKeywordId': 'maggotkin', 'warscrollId': 'gutrot'},
          {
            'factionKeywordId': 'maggotkin',
            'warscrollId': 'great-unclean-one',
          },
          {
            'factionKeywordId': 'maggotkin',
            'warscrollId': 'lord-of-plagues',
          },
          {'factionKeywordId': 'maggotkin', 'warscrollId': 'poxbringer'},
        ],
        'warscroll_regiment_option': [
          {
            'id': 'gutrot-rotbringers',
            'warscrollId': 'gutrot',
            'childQuantity': 'any',
            'requiredRosterFactionKeywordId': null,
          },
          {
            'id': 'gutrot-lord',
            'warscrollId': 'gutrot',
            'childQuantity': 'zeroToOne',
            'requiredRosterFactionKeywordId': null,
          },
          {
            'id': 'guo-maggotkin',
            'warscrollId': 'great-unclean-one',
            'childQuantity': 'any',
            'requiredRosterFactionKeywordId': null,
          },
          {
            'id': 'guo-scion',
            'warscrollId': 'great-unclean-one',
            'childQuantity': 'zeroToOne',
            'requiredRosterFactionKeywordId': null,
          },
        ],
        'warscroll_regiment_option_required_keyword': [
          {
            'warscrollRegimentOptionId': 'gutrot-rotbringers',
            'keywordId': 'rotbringers',
          },
          {
            'warscrollRegimentOptionId': 'gutrot-lord',
            'keywordId': 'rotbringer-lord',
          },
          {
            'warscrollRegimentOptionId': 'guo-scion',
            'keywordId': 'plague-scion',
          },
        ],
        'warscroll_regiment_option_excluded_keyword': [
          {
            'warscrollRegimentOptionId': 'gutrot-rotbringers',
            'keywordId': 'hero',
          },
          {
            'warscrollRegimentOptionId': 'guo-maggotkin',
            'keywordId': 'hero',
          },
        ],
        'warscroll_keyword': [
          {'warscrollId': 'gutrot', 'keywordId': 'hero'},
          {'warscrollId': 'gutrot', 'keywordId': 'rotbringers'},
          {'warscrollId': 'great-unclean-one', 'keywordId': 'hero'},
          {'warscrollId': 'lord-of-plagues', 'keywordId': 'hero'},
          {'warscrollId': 'lord-of-plagues', 'keywordId': 'rotbringers'},
          {'warscrollId': 'poxbringer', 'keywordId': 'hero'},
        ],
      },
    });

    final gutrotUnits = roleRepository.regimentUnits(
      heroId: 'gutrot',
      factionId: 'maggotkin',
    )['items'] as List;
    final greatUncleanOneUnits = roleRepository.regimentUnits(
      heroId: 'great-unclean-one',
      factionId: 'maggotkin',
    )['items'] as List;

    expect(gutrotUnits.map((item) => item['unit']['id']), ['lord-of-plagues']);
    expect(gutrotUnits.single['only_one'], true);
    expect(
      greatUncleanOneUnits.map((item) => item['unit']['id']),
      ['poxbringer'],
    );
    expect(greatUncleanOneUnits.single['only_one'], true);
  });

  test('loads warscroll abilities, weapon rules, and image links offline', () {
    final details = repository.warscrollDetails('hero');

    expect(details['unit']['rowImage'], 'https://images.example/hero.jpg');
    expect(details['abilities'].single['effect'], 'An ability description.');
    expect(details['abilities'].single['keywords'].single['name'], 'Infantry');
    expect(
      (details['weapons'] as List).map((weapon) => weapon['type']).toList(),
      ['ranged', 'melee'],
    );
    expect(
      (details['weapons'][1]['abilities'] as List)
          .map((ability) => ability['name'])
          .toList(),
      ['Anti-INFANTRY (+1 Rend)', 'Anti-WAR MACHINE (+1 Rend)'],
    );
    expect(
      details['weapons'][1]['abilities'][0]['rules'],
      'Weapon rules.',
    );
  });

  test('loads ability components for tactics cards offline', () {
    final tactic = repository.tactics().single;
    final components = tactic['components'] as List;

    expect(components[0]['ability']['effect'], 'Tactic effect.');
    expect(
      components[0]['ability']['keywords'].single['name'],
      'Infantry',
    );
    expect(
        components[1]['battleTactic']['rulesText'], 'Control the objective.');
  });

  test('adds publication artwork to formations and spell and prayer lores', () {
    final configuration = repository.configuration('faction');
    const image = 'https://images.example/publication.jpg';

    expect(
      (configuration['battle_formations'] as List).single['backgroundImage'],
      image,
    );
    expect(
      (configuration['battle_traits'] as List)
          .single['abilities']
          .single['name'],
      'Battle Trait',
    );
    expect(
      (configuration['spell_lores'] as List).single['backgroundImage'],
      image,
    );
    expect(
      (configuration['prayer_lores'] as List).single['backgroundImage'],
      image,
    );
    final otherEnhancement =
        ((configuration['enhancements'] as Map)['other'] as List).single as Map;
    expect(otherEnhancement['required_keywords'], ['Infantry']);
    expect(otherEnhancement['excluded_keywords'], ['Forbidden']);
    expect(otherEnhancement['required_warscroll_ids'], ['hero']);
    expect(otherEnhancement['uniqueAbilitySelections'], isTrue);
    expect(
      (configuration['manifestation_lores'] as List).single['backgroundImage'],
      isNull,
    );
    final manifestation = ((configuration['manifestation_lores'] as List)
            .single['abilities'] as List)
        .single as Map;
    expect(manifestation['id'], 'manifestation');
    expect(manifestation['summonAbility']['castingValue'], 7);
  });

  test('loads the rules catalog and linked section content offline', () {
    final catalog = repository.rulesCatalog();
    final section = repository.rulesSection('test-rules');

    expect((catalog['publications'] as List).single['name'], 'Core Rules');
    expect((catalog['sections'] as List).single['id'], 'test-rules');
    expect(
      (catalog['regimentsOfRenown'] as List)
          .any((group) => group['id'] == 'regiment-of-renown'),
      isTrue,
    );
    final regiment = (catalog['regimentsOfRenown'] as List)
        .singleWhere((group) => group['id'] == 'regiment-of-renown');
    expect(
        regiment['abilities'].single['effect'], 'A regiment ability effect.');
    expect(regiment['abilities'].single['keywords'].single['name'], 'Infantry');
    expect(
      (section['rules'] as List).single['components'][0]['textContent'],
      'Rules text.',
    );
  });

  test('loads all linked faction warscrolls for Rules offline', () {
    final warscrolls = repository.rulesFactionWarscrolls('faction');

    expect(warscrolls.map((unit) => unit['id']), [
      'excluded',
      'hero',
      'legal',
      'required',
    ]);
  });

  test('loads permitted Regiment of Renown with its image and composition', () {
    final regiments =
        repository.configuration('faction')['regiments_of_renown'] as List;

    expect(regiments, hasLength(1));
    expect(regiments.single['name'], 'Test Regiment of Renown');
    expect(regiments.single['image'], 'https://images.example/renown.jpg');
    expect(regiments.single['regimentOfRenownPointsCost'], 300);
    expect(regiments.single['units'].single['warscroll']['id'], 'hero');
    expect(regiments.single['abilities'].single['effect'],
        'A regiment ability effect.');
    expect(regiments.single['abilities'].single['keywords'].single['name'],
        'Infantry');
  });
}
