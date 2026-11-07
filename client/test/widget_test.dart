import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aos_client/api_client.dart';
import 'package:aos_client/army_builder_page.dart';
import 'package:aos_client/data_details_sheet.dart';
import 'package:aos_client/main.dart';
import 'package:aos_client/rules_page.dart';
import 'package:aos_client/save_army_name_dialog.dart';
import 'package:aos_client/saved_army_store.dart';

void main() {
  test('uses the first related manifestation image as a preview', () {
    expect(
      dataPreviewImageUrl(const {
        'name': 'Manifestation Lore',
        'abilities': [
          {'id': 'first', 'name': 'First manifestation'},
          {
            'id': 'second',
            'name': 'Second manifestation',
            'rowImage': 'https://images.example/manifestation.jpg',
          },
        ],
      }),
      'https://images.example/manifestation.jpg',
    );
  });

  test('uses Regiment of Renown artwork as a preview', () {
    expect(
      dataPreviewImageUrl({
        'name': 'Test Regiment of Renown',
        'image': 'https://images.example/renown.jpg',
      }),
      'https://images.example/renown.jpg',
    );
  });

  testWidgets('shows Regiment of Renown composition, rules, and abilities',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DataDetailsSheet(
            item: {
              'id': 'renown',
              'name': 'Test Regiment of Renown',
              'image': 'https://images.example/renown.jpg',
              'regimentOfRenownPointsCost': 300,
              'subsectionRulesText': 'Regiment rules.',
              'abilities': [
                {
                  'name': 'Insubstantial',
                  'phaseDetails': 'Passive',
                  'effect': 'Ignore negative modifiers to save rolls.',
                },
              ],
              'units': [
                {
                  'minCount': 2,
                  'maxCount': 2,
                  'warscroll': {
                    'id': 'guard',
                    'name': 'Mortek Guard',
                    'modelCount': 10,
                    'rowImage': 'https://images.example/guard.jpg',
                    'referenceKeywords': 'Infantry',
                  },
                },
              ],
            },
          ),
        ),
      ),
    );

    expect(find.text('300 pts'), findsOneWidget);
    expect(find.text('Regiment composition'), findsOneWidget);
    expect(find.text('2 x 10 Mortek Guard'), findsOneWidget);
    expect(find.text('Regiment rules.'), findsOneWidget);
    expect(find.text('Insubstantial'), findsOneWidget);
    expect(
      find.text(
        'Effect: Ignore negative modifiers to save rolls.',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows casting value, cost, and command points separately',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DataDetailsSheet(
            item: {
              'name': 'Regiment of Renown',
              'abilities': [
                {
                  'name': 'Spell',
                  'castingValue': 7,
                  'effect': 'Spell effect.',
                },
                {
                  'name': 'Cost ability',
                  'cost': '1+',
                  'effect': 'Cost effect.',
                },
                {
                  'name': 'Prayer',
                  'chantingValue': 4,
                  'effect': 'Prayer effect.',
                },
                {
                  'name': 'Command ability',
                  'cpCost': 1,
                  'effect': 'Command effect.',
                },
              ],
            },
          ),
        ),
      ),
    );

    expect(find.text('Casting 7'), findsOneWidget);
    expect(find.text('Chanting 4'), findsOneWidget);
    expect(find.text('Cost 1+'), findsOneWidget);
    expect(find.text('1 CP'), findsOneWidget);
    expect(find.text('Casting 1+'), findsNothing);
  });

  testWidgets('opens linked manifestation warscroll details', (tester) async {
    String? openedWarscrollId;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataDetailsSheet(
            item: const {
              'name': 'Manifestation Lore',
              'abilities': [
                {
                  'id': 'manifestation',
                  'name': 'Summoned Manifestation',
                  'points': 100,
                  'referenceKeywords': 'Manifestation, Order',
                  'summonAbility': {
                    'name': 'Summon Manifestation',
                    'castingValue': 7,
                  },
                },
              ],
            },
            onOpenDetails: (unit) async {
              openedWarscrollId = unit['id']?.toString();
            },
          ),
        ),
      ),
    );

    expect(find.text('Manifestations'), findsOneWidget);
    expect(find.text('Summoned Manifestation'), findsOneWidget);
    expect(find.textContaining('Cast 7'), findsOneWidget);
    expect(find.textContaining('Banish 8'), findsOneWidget);
    await tester.tap(find.byTooltip('Show details'));
    await tester.pump();

    expect(openedWarscrollId, 'manifestation');
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows casting and banishment information for a manifestation',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DataDetailsSheet(
            item: {
              'id': 'manifestation',
              'name': 'Summoned Manifestation',
              'referenceKeywords': 'Manifestation',
              'summonAbility': {
                'name': 'Summon Manifestation',
                'castingValue': 7,
              },
            },
            details: {
              'unit': {
                'id': 'manifestation',
                'name': 'Summoned Manifestation',
                'referenceKeywords': 'Manifestation',
              },
              'abilities': [],
              'weapons': [],
            },
          ),
        ),
      ),
    );

    expect(find.text('Summoning spell'), findsOneWidget);
    expect(find.text('Casting 7'), findsOneWidget);
    expect(find.text('Banishment'), findsOneWidget);
    expect(find.textContaining('Banishment value: 8'), findsOneWidget);
    expect(find.textContaining('Cast 7 + 1'), findsOneWidget);
    expect(find.textContaining('2D6'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browses core rules from the Rules section', (tester) async {
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: RulesPage(apiClient: api),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rules'), findsOneWidget);
    expect(find.text('Core Documents'), findsOneWidget);
    await tester.tap(find.text('Core Documents'));
    await tester.pumpAndSettle();
    expect(find.text('Core Rulebook'), findsOneWidget);
    await tester.tap(find.text('Core Rulebook'));
    await tester.pumpAndSettle();
    expect(find.text('Core Rules'), findsOneWidget);
    await tester.tap(find.text('Core Rules'));
    await tester.pumpAndSettle();
    expect(find.text('General Rules'), findsOneWidget);
    await tester.tap(find.text('General Rules'));
    await tester.pumpAndSettle();

    expect(find.text('A rule description.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('keeps app navigation visible in Rules subpages', (tester) async {
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RulesPage(apiClient: api),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 1,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                label: 'Builder',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                label: 'Rules',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Core Documents'));
    await tester.pumpAndSettle();

    expect(find.text('Core Rulebook'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('groups Armies of Renown by their faction', (tester) async {
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(home: RulesPage(apiClient: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Armies of Renown'));
    await tester.pumpAndSettle();

    expect(find.text('Stormcast Eternals'), findsOneWidget);
    expect(find.text('Test Army of Renown'), findsOneWidget);

    await tester.tap(find.text('Test Army of Renown'));
    await tester.pumpAndSettle();
    expect(find.text('Test Army of Renown'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('shows faction warscrolls and faction rules', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(home: RulesPage(apiClient: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stormcast Eternals').first);
    await tester.pumpAndSettle();

    expect(find.text('Warscrolls'), findsOneWidget);
    expect(find.text('Battle Traits'), findsOneWidget);
    expect(find.text('Units Keywords'), findsOneWidget);
    expect(find.text('Armies of Renown'), findsOneWidget);
    expect(find.byIcon(Icons.label_outline), findsOneWidget);
    expect(find.byIcon(Icons.military_tech_outlined), findsOneWidget);
    expect(find.byIcon(Icons.build_outlined), findsOneWidget);
    final defaultIconSection = find.ancestor(
      of: find.text('Battle Formations'),
      matching: find.byType(ExpansionTile),
    );
    expect(
      find.descendant(
        of: defaultIconSection,
        matching: find.byIcon(Icons.shield_outlined),
      ),
      findsOneWidget,
    );
    for (final sectionIcon in [
      ('Artefacts of Power', Icons.auto_awesome_outlined),
      ('Heroic Traits', Icons.star_outline),
      ('Armies of Renown', Icons.groups_outlined),
    ]) {
      final section = find.ancestor(
        of: find.text(sectionIcon.$1),
        matching: find.byType(ExpansionTile),
      );
      expect(
        find.descendant(
          of: section,
          matching: find.byIcon(sectionIcon.$2),
        ),
        findsOneWidget,
        reason: '${sectionIcon.$1} should show its rules-section icon',
      );
    }
    await tester.tap(find.text('Warscrolls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Infantry'));
    await tester.pumpAndSettle();
    expect(find.text('Test Warrior'), findsOneWidget);

    await tester.tap(find.text('Test Warrior'));
    await tester.pumpAndSettle();
    expect(find.text('A faction warscroll description.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('groups builder Armies of Renown by their faction', (
    tester,
  ) async {
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(home: ArmyBuilderPage(apiClient: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();

    expect(find.text('Armies of Renown'), findsOneWidget);
    expect(find.text('Stormcast Eternals'), findsNWidgets(2));
    expect(find.text('Test Army of Renown'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('shows faction traits and abilities in the army builder', (
    tester,
  ) async {
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(home: ArmyBuilderPage(apiClient: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stormcast Eternals').first);
    await tester.pumpAndSettle();

    expect(find.text('Test Battle Traits'), findsOneWidget);
    expect(find.text('Test Faction Ability'), findsOneWidget);
    await tester.tap(find.text('Test Faction Ability'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test faction effect.'), findsOneWidget);
    api.close();
  });

  testWidgets('keeps selected lores when their selection dialog is dismissed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(home: ArmyBuilderPage(apiClient: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stormcast Eternals').first);
    await tester.pumpAndSettle();

    for (final option in [
      ('Spell Lore', 'Test Spell Lore'),
      ('Prayer Lore', 'Test Prayer Lore'),
      ('Manifestation Lore', 'Test Manifestation Lore'),
    ]) {
      await tester.ensureVisible(find.text(option.$1));
      await tester.tap(find.text(option.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option.$2));
      await tester.pumpAndSettle();
      expect(find.text(option.$2), findsOneWidget);

      await tester.tap(find.text(option.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(option.$2), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('offers unit enhancements only to eligible recipients', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RulesApiClient();
    await tester.pumpWidget(
      MaterialApp(home: ArmyBuilderPage(apiClient: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stormcast Eternals').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add Regiment'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add Regiment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Hero'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add Unit'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Add Unit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Unit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eligible Infantry'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Moulder Mutations'));
    await tester.tap(find.text('Moulder Mutations'));
    await tester.pumpAndSettle();

    final targetDialog = find.ancestor(
      of: find.text('Choose a unit for Moulder Mutations'),
      matching: find.byType(AlertDialog),
    );
    expect(
      find.descendant(
        of: targetDialog,
        matching: find.text('Eligible Infantry'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: targetDialog, matching: find.text('Test Hero')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: targetDialog,
        matching: find.text('Hero Infantry'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: targetDialog, matching: find.text('War Machine')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: targetDialog,
        matching: find.text('Eligible Infantry'),
      ),
    );
    await tester.pumpAndSettle();
    final abilityDialog = find.ancestor(
      of: find.text('Choose Moulder Mutations'),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(
      find.descendant(of: abilityDialog, matching: find.text('Mutation')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Enhancements: Mutation'), findsOneWidget);
    expect(
        find.textContaining('Eligible Infantry · Regiment 1'), findsOneWidget);
    final addEnhancementButton = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Moulder Mutations'),
        matching: find.byType(TextButton),
      ),
    );
    expect(addEnhancementButton.onPressed, isNotNull);

    await tester.ensureVisible(find.text('Add Unit'));
    await tester.tap(find.text('Add Unit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second Eligible Infantry'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Moulder Mutations'));
    await tester.tap(find.text('Moulder Mutations'));
    await tester.pumpAndSettle();
    final secondTargetDialog = find.ancestor(
      of: find.text('Choose a unit for Moulder Mutations'),
      matching: find.byType(AlertDialog),
    );
    await tester.tap(
      find.descendant(
        of: secondTargetDialog,
        matching: find.text('Second Eligible Infantry'),
      ),
    );
    await tester.pumpAndSettle();
    final secondAbilityDialog = find.ancestor(
      of: find.text('Choose Moulder Mutations'),
      matching: find.byType(AlertDialog),
    );
    expect(
      find.descendant(
        of: secondAbilityDialog,
        matching: find.text('Mutation'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: secondAbilityDialog,
        matching: find.text('Second Mutation'),
      ),
      findsOneWidget,
    );
    api.close();
  });

  testWidgets('shows an opponent army beside the roster on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await SavedArmyStore().save(
      name: 'Opponent List',
      army: _opponentArmyData(),
    );
    final api = _RulesApiClient();

    await _chooseOpponentFromBuilder(tester, api);

    expect(find.text('Opponent List'), findsOneWidget);
    expect(find.text('Enemy General'), findsOneWidget);
    expect(find.text('6 x Enemy Cavalry (Reinforced)'), findsOneWidget);
    expect(find.text('My Army'), findsNothing);
    api.close();
  });

  testWidgets('switches to the opponent army on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await SavedArmyStore().save(
      name: 'Opponent List',
      army: _opponentArmyData(),
    );
    final api = _RulesApiClient();

    await _chooseOpponentFromBuilder(tester, api);
    await tester.tap(find.text('Opponent'));
    await tester.pumpAndSettle();

    expect(find.text('Enemy General'), findsOneWidget);
    expect(find.text('6 x Enemy Cavalry (Reinforced)'), findsOneWidget);
    api.close();
  });

  testWidgets('opens opponent warscroll abilities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await SavedArmyStore().save(
      name: 'Opponent List',
      army: _opponentArmyData(),
    );
    final api = _RulesApiClient();

    await _chooseOpponentFromBuilder(tester, api);
    await tester.ensureVisible(find.text('Enemy Faction Ability'));
    await tester.tap(find.text('Enemy Faction Ability'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enemy faction effect.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('6 x Enemy Cavalry (Reinforced)'));
    await tester.tap(find.text('6 x Enemy Cavalry (Reinforced)'));
    await tester.pumpAndSettle();

    expect(find.text('Rapid Assault'), findsOneWidget);
    await tester.ensureVisible(find.text('Rapid Assault'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Enemy cavalry can make a powerful charge.'),
      findsOneWidget,
    );
    api.close();
  });

  testWidgets('reloads saved armies when the tab becomes active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var isActive = false;
    late StateSetter updateParent;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateParent = setState;
            return Scaffold(
              body: Column(
                children: [
                  Expanded(child: SavedArmiesPage(isActive: isActive)),
                  TextButton(
                    onPressed: () => setState(() => isActive = true),
                    child: const Text('Open armies'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await SavedArmyStore().save(
      name: 'Recently saved list',
      army: {'faction_name': 'Stormcast Eternals', 'total_points': 1000},
    );
    updateParent(() => isActive = true);
    await tester.pumpAndSettle();

    expect(find.text('Recently saved list'), findsOneWidget);
  });

  testWidgets('opens a saved army through the provided callback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    String? openedArmyName;
    await SavedArmyStore().save(
      name: 'Army from Armies',
      army: {
        'alliance': {'id': 'alliance', 'name': 'Order'},
        'faction': {'id': 'faction', 'name': 'Stormcast Eternals'},
        'faction_name': 'Stormcast Eternals',
        'points_limit': 2000,
        'regiments': [],
        'auxiliary_units': [],
        'selected_options': {},
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedArmiesPage(
            onOpen: (army) => openedArmyName = army['name']?.toString(),
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.shield),
                label: 'Builder',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmarks),
                label: 'Armies',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Army from Armies'));
    await tester.pump();

    expect(openedArmyName, 'Army from Armies');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('shows warscroll abilities and weapon descriptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DataDetailsSheet(
            item: {'id': 'hero', 'name': 'Hero'},
            details: {
              'unit': {
                'id': 'hero',
                'name': 'Hero',
                'points': 100,
                'move': '5"',
                'health': '5',
                'save': '4+',
                'control': '2',
                'wardSave': '6+',
                'referenceKeywords': 'Hero, Wizard (2), Priest (1), Infantry',
                'lore': 'The unit lore.',
              },
              'abilities': [
                {
                  'name': 'Heroic action',
                  'phaseDetails': 'Your hero phase',
                  'effect': 'The hero acts.',
                  'keywords': [
                    {'name': 'Hero'},
                  ],
                },
              ],
              'weapons': [
                {
                  'name': 'Blade',
                  'type': 'melee',
                  'attacks': '3',
                  'hit': '3+',
                  'wound': '3+',
                  'rend': '1',
                  'damage': '2',
                  'abilities': [
                    {'name': 'Piercing', 'rules': 'Add 1 to Rend.'},
                  ],
                },
              ],
              'components': [
                {
                  'contentType': 'ability',
                  'ability': {
                    'name': 'Tactics ability',
                    'effect': 'Tactics effect.',
                  },
                },
                {
                  'contentType': 'battleTactic',
                  'battleTactic': {
                    'name': 'Claim the Field',
                    'battleTacticType': 'domination',
                    'victoryPoints': 5,
                    'rulesText': 'Control the objective.',
                  },
                },
              ],
            },
          ),
        ),
      ),
    );

    expect(find.text('Heroic action'), findsOneWidget);
    expect(find.textContaining('The hero acts.'), findsOneWidget);
    final weaponTop = tester.getTopLeft(find.text('Blade')).dy;
    final abilityTop = tester.getTopLeft(find.text('Heroic action')).dy;
    final otherDetailsTop = tester.getTopLeft(find.text('The unit lore.')).dy;
    for (final statistic in [
      'Move: 5"',
      'Health: 5',
      'Save: 4+',
      'Control: 2',
      'Ward: 6+',
      'Wizard: 2',
      'Priest: 1',
    ]) {
      expect(find.text(statistic), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(statistic)).dy,
        lessThan(weaponTop),
      );
    }
    expect(weaponTop, lessThan(abilityTop));
    expect(abilityTop, lessThan(otherDetailsTop));
    expect(
      tester.getTopLeft(find.text('Claim the Field')).dy,
      lessThan(tester.getTopLeft(find.text('Keywords')).dy),
    );
    expect(
      find.text('Hero, Wizard (2), Priest (1), Infantry'),
      findsOneWidget,
    );
    expect(find.text('Atk'), findsOneWidget);
    expect(find.text('Hit'), findsOneWidget);
    expect(find.text('Dmg'), findsOneWidget);
    expect(find.text('Piercing'), findsOneWidget);
    await tester.tap(find.text('Piercing'));
    await tester.pumpAndSettle();
    expect(find.text('Add 1 to Rend.'), findsOneWidget);
    expect(find.text('Tactics ability'), findsOneWidget);
    expect(find.textContaining('Tactics effect.'), findsOneWidget);
    expect(find.text('Claim the Field'), findsOneWidget);
    expect(find.textContaining('Control the objective.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving an army closes its name dialog without errors', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _SaveDialogHarness()));
    await tester.tap(find.text('Open save dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My army');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('My army'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SaveDialogHarness extends StatefulWidget {
  const _SaveDialogHarness();

  @override
  State<_SaveDialogHarness> createState() => _SaveDialogHarnessState();
}

class _RulesApiClient extends ApiClient {
  _RulesApiClient() : super(baseUrl: 'http://localhost:3000');

  @override
  Future<List<JsonMap>> builderAlliances() async => [
        {'id': 'alliance', 'name': 'Order'},
      ];

  @override
  Future<JsonMap> builderFactions(String allianceId) async => {
        'factions': [
          {'id': 'faction', 'name': 'Stormcast Eternals'},
        ],
        'armies_of_renown': [
          {
            'id': 'army-of-renown',
            'name': 'Test Army of Renown',
            'parentFactionKeywordId': 'faction',
            'parentFactionName': 'Stormcast Eternals',
            'armyOfRenown': true,
          },
        ],
      };

  @override
  Future<List<JsonMap>> builderTactics() async => [];

  @override
  Future<List<JsonMap>> builderHeroes(
    String factionId, {
    String search = '',
    bool showLegends = false,
  }) async =>
      [
        {
          'id': 'test-hero',
          'name': 'Test Hero',
          'points': 100,
          'referenceKeywords': 'Hero, Order',
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
              'id': 'eligible-unit',
              'name': 'Eligible Infantry',
              'points': 100,
              'referenceKeywords': 'Infantry, Skaven',
            },
          },
          {
            'unit': {
              'id': 'second-eligible-unit',
              'name': 'Second Eligible Infantry',
              'points': 100,
              'referenceKeywords': 'Infantry, Skaven',
            },
          },
          {
            'unit': {
              'id': 'hero-unit',
              'name': 'Hero Infantry',
              'points': 100,
              'referenceKeywords': 'Hero, Infantry, Skaven',
            },
          },
          {
            'unit': {
              'id': 'war-machine',
              'name': 'War Machine',
              'points': 100,
              'referenceKeywords': 'War Machine, Skaven',
            },
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
  Future<JsonMap> rulesCatalog() async => {
        'publications': [
          {'id': 'core', 'name': 'Core Rulebook'},
        ],
        'publicationGroupLinks': [
          {
            'publicationId': 'core',
            'publicationGroupId': 'e918110c-418e-4a50-90bc-484581a0fa5c',
          },
        ],
        'sections': [
          {
            'id': 'core-section',
            'name': 'Core Rules',
            'publicationId': 'core',
            'parentId': null,
            'displayOrder': 1,
          },
          {
            'id': 'general-rules',
            'name': 'General Rules',
            'publicationId': 'core',
            'parentId': 'core-section',
            'displayOrder': 1,
          },
        ],
        'factions': [
          {
            'id': 'alliance',
            'name': 'Grand Alliance Order',
            'parentFactionKeywordId': null,
          },
          {
            'id': 'faction',
            'name': 'Stormcast Eternals',
            'parentFactionKeywordId': 'alliance',
          },
          {
            'id': 'army-of-renown',
            'name': 'Test Army of Renown',
            'parentFactionKeywordId': 'faction',
            'armyOfRenown': true,
          },
        ],
        'regimentsOfRenown': [],
        'manifestationLores': [],
        'warscrolls': [],
      };

  @override
  Future<JsonMap> builderConfiguration(String factionId) async => {
        'battle_traits': [
          {
            'id': 'battle-traits',
            'name': 'Test Battle Traits',
            'abilities': [
              {
                'id': 'trait-ability',
                'name': factionId == 'enemy-faction'
                    ? 'Enemy Faction Ability'
                    : 'Test Faction Ability',
                'phaseDetails': 'Any hero phase',
                'effect': factionId == 'enemy-faction'
                    ? 'Enemy faction effect.'
                    : 'Test faction effect.',
              },
            ],
          },
        ],
        'battle_formations': [
          {'id': 'formation', 'name': 'Test Formation'},
        ],
        'spell_lores': [
          {'id': 'spell-lore', 'name': 'Test Spell Lore'},
        ],
        'prayer_lores': [
          {'id': 'prayer-lore', 'name': 'Test Prayer Lore'},
        ],
        'manifestation_lores': [
          {'id': 'manifestation-lore', 'name': 'Test Manifestation Lore'},
        ],
        'regiments_of_renown': [],
        'enhancements': {
          'artefacts': [
            {'id': 'artefact', 'name': 'Test Artefact'},
          ],
          'heroic_traits': [
            {'id': 'trait', 'name': 'Test Heroic Trait'},
          ],
          'other': [
            {
              'id': 'moulder-mutations',
              'name': 'Moulder Mutations',
              'restrictionText':
                  'Give to non-HERO non-WAR MACHINE SKAVEN units.',
              'rosterLevelLimit': 3,
              'unitLevelLimit': 1,
              'uniqueAbilitySelections': true,
              'required_keywords': [],
              'excluded_keywords': [
                'Hero',
                'War Machine',
                'Faction Terrain',
              ],
              'required_warscroll_ids': [],
              'abilities': [
                {
                  'id': 'moulder-mutation',
                  'name': 'Mutation',
                  'points': 0,
                  'effect': 'A test mutation.',
                },
                {
                  'id': 'second-moulder-mutation',
                  'name': 'Second Mutation',
                  'points': 0,
                  'effect': 'Another test mutation.',
                },
              ],
            },
          ],
        },
      };

  @override
  Future<List<JsonMap>> rulesFactionWarscrolls(String factionId) async => [
        {
          'id': 'test-warrior',
          'name': 'Test Warrior',
          'points': 100,
          'referenceKeywords': 'Infantry',
          'rowImage': 'https://images.example/warrior.jpg',
        },
      ];

  @override
  Future<JsonMap> builderWarscrollDetails(String warscrollId) async => {
        'unit': {
          'id': warscrollId,
          'name':
              warscrollId == 'enemy-cavalry' ? 'Enemy Cavalry' : 'Test Warrior',
          'points': 100,
          'referenceKeywords': 'Infantry',
          'lore': 'A faction warscroll description.',
        },
        'abilities': [
          {
            'name': 'Rapid Assault',
            'phaseDetails': 'Charge phase',
            'effect': 'Enemy cavalry can make a powerful charge.',
          },
        ],
        'weapons': [],
        'additional_characteristics': [],
        'regiment_options': [],
      };

  @override
  Future<JsonMap> rulesSection(String sectionId) async => {
        'rules': [
          {
            'id': 'rule',
            'title': 'General Rule',
            'components': [
              {
                'contentType': 'text',
                'textContent': 'A rule description.',
              },
            ],
          },
        ],
      };
}

class _SaveDialogHarnessState extends State<_SaveDialogHarness> {
  String? _savedName;

  Future<void> _openDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const SaveArmyNameDialog(title: 'Save army'),
    );
    if (!mounted || name == null) return;
    setState(() => _savedName = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_savedName != null) Text(_savedName!),
            FilledButton(
              onPressed: _openDialog,
              child: const Text('Open save dialog'),
            ),
          ],
        ),
      ),
    );
  }
}

JsonMap _opponentArmyData() => {
      'alliance': {'id': 'enemy-alliance', 'name': 'Order'},
      'faction': {'id': 'enemy-faction', 'name': 'Enemy Faction'},
      'faction_name': 'Enemy Faction',
      'total_points': 1800,
      'points_limit': 2000,
      'general_index': 0,
      'regiments': [
        {
          'hero': {
            'id': 'enemy-general',
            'name': 'Enemy General',
            'points': 200,
          },
          'units': [
            {
              'warscroll': {
                'id': 'enemy-cavalry',
                'name': 'Enemy Cavalry',
                'modelCount': 3,
                'points': 300,
                'referenceKeywords': 'Cavalry, Order',
                'rowImage': 'https://images.example/enemy-cavalry.jpg',
              },
              'reinforced': true,
            },
          ],
          'artefact': null,
          'heroic_trait': null,
          'other_enhancements': [],
        },
      ],
      'auxiliary_units': [],
      'selected_options': {
        'battle_formation': {
          'id': 'enemy-formation',
          'name': 'Enemy Formation'
        },
        'tactics': [],
      },
    };

Future<void> _chooseOpponentFromBuilder(
  WidgetTester tester,
  ApiClient api,
) async {
  await tester.pumpWidget(
    MaterialApp(home: ArmyBuilderPage(apiClient: api)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Order'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Stormcast Eternals').first);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Choose Opponent Army'));
  await tester.tap(find.text('Choose Opponent Army'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Opponent List'));
  await tester.pumpAndSettle();
}
