import 'package:aos_client/army_builder_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uniqueHeroA = {
    'id': 'hero-a',
    'name': 'Unique Hero A',
    'referenceKeywords': 'Unique, Hero',
  };
  const uniqueHeroB = {
    'id': 'hero-b',
    'name': 'Unique Hero B',
    'referenceKeywords': 'Unique, Hero',
  };
  const regularHero = {
    'id': 'hero-c',
    'name': 'Regular Hero',
    'referenceKeywords': 'Hero',
  };

  test('filters an already selected Unique warscroll, not other Unique heroes',
      () {
    final available = availableUniqueUnits(
      [uniqueHeroA, uniqueHeroB, regularHero],
      [uniqueHeroA],
    );

    expect(available.map((unit) => unit['id']), ['hero-b', 'hero-c']);
  });

  test('allows the current Unique hero to remain selected', () {
    final available = availableUniqueUnits(
      [uniqueHeroA, uniqueHeroB],
      [uniqueHeroA],
      except: uniqueHeroA,
    );

    expect(available.map((unit) => unit['id']), ['hero-a', 'hero-b']);
  });

  test('reports only duplicate copies of the same Unique warscroll', () {
    final duplicates = duplicateUniqueUnits([
      uniqueHeroA,
      uniqueHeroB,
      {...uniqueHeroA},
      regularHero,
      regularHero,
    ]);

    expect(duplicates.map((unit) => unit['id']), ['hero-a']);
  });

  test('filters Regiments of Renown containing a selected Unique warscroll',
      () {
    final available = availableUniqueRegimentsOfRenown(
      [
        {
          'id': 'regiment-a',
          'units': [
            {'warscroll': uniqueHeroA},
          ],
        },
        {
          'id': 'regiment-b',
          'units': [
            {'warscroll': uniqueHeroB},
          ],
        },
        {
          'id': 'regiment-c',
          'units': [
            {'warscroll': regularHero},
          ],
        },
      ],
      [uniqueHeroA],
    );

    expect(available.map((regiment) => regiment['id']),
        ['regiment-b', 'regiment-c']);
  });

  test('applies required and excluded keywords to enhancement recipients', () {
    const moulderMutations = {
      'required_keywords': <String>[],
      'excluded_keywords': ['Hero', 'War Machine', 'Faction Terrain'],
    };

    expect(
      enhancementCanBeGivenTo(moulderMutations, {
        'id': 'rat-ogors',
        'referenceKeywords': 'Infantry, Chaos, Skaven, Moulder',
      }),
      isTrue,
    );
    expect(
      enhancementCanBeGivenTo(moulderMutations, {
        'id': 'master-moulder',
        'referenceKeywords': 'Hero, Infantry, Chaos, Skaven, Moulder',
      }),
      isFalse,
    );
    expect(
      enhancementCanBeGivenTo(moulderMutations, {
        'id': 'doomwheel',
        'referenceKeywords': 'War Machine, Chaos, Skaven, Skryre',
      }),
      isFalse,
    );
  });

  test('allows any required keyword and enforces exact warscroll targets', () {
    const enhancement = {
      'required_keywords': ['Infantry', 'Cavalry'],
      'excluded_keywords': ['Hero'],
      'required_warscroll_ids': <String>[],
    };
    expect(
      enhancementCanBeGivenTo(enhancement, {
        'id': 'cavalry',
        'referenceKeywords': 'Cavalry, Order',
      }),
      isTrue,
    );
    expect(
      enhancementCanBeGivenTo(enhancement, {
        'id': 'hero',
        'referenceKeywords': 'Hero, Infantry',
      }),
      isFalse,
    );
    expect(
      enhancementCanBeGivenTo({
        'required_keywords': <String>[],
        'excluded_keywords': <String>[],
        'required_warscroll_ids': ['varanguard'],
      }, {
        'id': 'other',
        'referenceKeywords': 'Infantry',
      }),
      isFalse,
    );
  });

  test('filters choices already selected in a unique enhancement group', () {
    const group = {'uniqueAbilitySelections': true};
    const choices = [
      {'id': 'title-a', 'name': 'First Title'},
      {'id': 'title-b', 'name': 'Second Title'},
    ];

    expect(
      availableEnhancementChoices(
        group,
        choices,
        [
          {'id': 'title-a'},
        ],
      ).map((choice) => choice['id']),
      ['title-b'],
    );
  });

  test('does not impose unique choices on other enhancement groups', () {
    const choices = [
      {'id': 'title-a', 'name': 'First Title'},
    ];

    expect(
      availableEnhancementChoices(
        const {},
        choices,
        [
          {'id': 'title-a'},
        ],
      ),
      choices,
    );
  });
}
