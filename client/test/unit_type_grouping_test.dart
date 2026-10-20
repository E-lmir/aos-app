import 'package:aos_client/unit_type_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups builder choices by reference keywords in original order', () {
    final choices = <Map<String, dynamic>>[
      {
        'id': 'infantry',
        'name': 'Spearmen',
        'referenceKeywords': 'Infantry, Order'
      },
      {
        'option_id': 'cavalry-option',
        'unit': {
          'id': 'cavalry',
          'name': 'Riders',
          'referenceKeywords': 'Cavalry, Order',
        },
      },
      {'id': 'beast', 'name': 'Beast', 'referenceKeywords': 'Beast, Order'},
      {
        'id': 'monster',
        'name': 'Monster',
        'referenceKeywords': 'Monster, Order'
      },
      {
        'id': 'machine',
        'name': 'War machine',
        'referenceKeywords': 'War Machine, Order',
      },
      {
        'id': 'hero',
        'name': 'Heroic infantry',
        'referenceKeywords': 'Hero, Infantry, Order',
      },
      {
        'id': 'manifestation',
        'name': 'Manifestation',
        'referenceKeywords': 'Manifestation, Hero',
      },
      {
        'id': 'terrain',
        'name': 'Terrain',
        'referenceKeywords': 'Faction Terrain, Order',
      },
      {'id': 'other', 'name': 'Unclassified', 'referenceKeywords': 'Order'},
    ];

    final groups = groupBuilderUnitsByType(choices);

    expect(
      groups.map((group) => group.title),
      [
        'Hero',
        'Infantry',
        'Cavalry',
        'Beast',
        'Monster',
        'War Machine',
        'Manifestation',
        'Faction Terrain',
        'Other',
      ],
    );
    expect(groups[0].items.single['id'], 'hero');
    expect(groups[1].items.single['id'], 'infantry');
    expect(groups[2].items.single['unit']['id'], 'cavalry');
    expect(groups.last.items.single['id'], 'other');
  });
}
