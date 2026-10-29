import 'package:material_ui/material_ui.dart';

import 'api_client.dart';
import 'data_image_cache.dart';

class DataThumbnail extends StatelessWidget {
  const DataThumbnail({
    super.key,
    required this.imageUrl,
    this.size = 56,
  });

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedDataImage(
        imageUrl: url,
        width: size,
        height: size * 1.35,
        fit: BoxFit.cover,
        placeholder: _placeholder(),
        errorWidget: _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size * 1.35,
      decoration: BoxDecoration(
        color: const Color(0xffece8e6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}

class DataDetailsSheet extends StatelessWidget {
  const DataDetailsSheet({
    super.key,
    required this.item,
    this.details,
    this.onOpenDetails,
  });

  final JsonMap item;
  final JsonMap? details;
  final Future<void> Function(JsonMap item)? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final displayData = details ?? item;
    final unit = _asMap(displayData['unit']) ?? item;
    final abilities = _asMaps(displayData['abilities'] ?? item['abilities']);
    final weapons = _asMaps(displayData['weapons']);
    final components = _asMaps(displayData['components'] ?? item['components']);
    final characteristics = _asMaps(displayData['additional_characteristics']);
    final regimentOptions = _asMaps(displayData['regiment_options']);
    final regimentUnits = _asMaps(displayData['units'] ?? item['units']);
    final summonAbility = _asMap(item['summonAbility']);
    final castingValue = summonAbility?['castingValue'];
    final banishmentValue = _banishmentValue(summonAbility);
    final isManifestation = _isManifestation(unit) ||
        _isManifestation(item) ||
        summonAbility != null;
    final hasDirectAbility = details == null && _isAbility(item);
    final containsOnlyWarscrolls = abilities.isNotEmpty &&
        abilities.every((ability) => _isWarscroll(ability));
    final image = dataPreviewImageUrl(unit) ?? dataPreviewImageUrl(item);
    final name = item['name']?.toString() ??
        item['title']?.toString() ??
        unit['name']?.toString() ??
        'Details';

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (image != null) _bannerImage(image),
                    _statistics(unit),
                    if (weapons.isNotEmpty) ...[
                      _heading('Weapon profiles'),
                      for (final weapon in weapons) _weapon(context, weapon),
                    ],
                    if (abilities.isNotEmpty || hasDirectAbility) ...[
                      _heading(
                        containsOnlyWarscrolls ? 'Manifestations' : 'Abilities',
                      ),
                      if (hasDirectAbility) _ability(context, item),
                      for (final ability in abilities)
                        if (_isAbility(ability))
                          _ability(context, ability)
                        else
                          _relatedUnit(context, ability),
                    ],
                    if (summonAbility != null) ...[
                      _heading('Summoning spell'),
                      _ability(context, summonAbility),
                    ],
                    if (isManifestation)
                      _section(
                        'Banishment',
                        banishmentValue != null
                            ? 'Banishment value: $banishmentValue (Cast '
                                '$castingValue + 1).'
                            : "The banishment value is 1 higher than the "
                                "manifestation's casting value. The casting "
                                'value is not available in the source data.',
                      ),
                    if (unit['subname'] is String &&
                        (unit['subname'] as String).isNotEmpty)
                      _paragraph(unit['subname'].toString()),
                    for (final field in const [
                      ('lore', 'Description'),
                      ('subsectionLore', 'Description'),
                      ('subtitle', 'Description'),
                      ('subsectionRulesText', 'Rules'),
                      ('restrictionText', 'Restrictions'),
                      ('optionText', 'Option'),
                      ('wargearOptionsText', 'Wargear options'),
                      ('notes', 'Notes'),
                      ('altText', 'Additional details'),
                      ('rules', 'Rules'),
                    ])
                      if (_text(unit[field.$1]) != null)
                        _section(field.$2, _text(unit[field.$1])!),
                    if (unit['points'] != null)
                      _section('Points', '${unit['points']} pts')
                    else if (unit['regimentOfRenownPointsCost'] != null)
                      _section(
                        'Points',
                        '${unit['regimentOfRenownPointsCost']} pts',
                      ),
                    if (unit['modelCount'] != null)
                      _section('Models', '${unit['modelCount']}'),
                    if (unit['baseSize'] != null)
                      _section('Base size', unit['baseSize'].toString()),
                    for (final characteristic in characteristics)
                      _section(
                        characteristic['name']?.toString() ?? 'Characteristic',
                        characteristic['value']?.toString() ?? '',
                      ),
                    if (regimentOptions.isNotEmpty) ...[
                      _heading('Regiment options'),
                      for (final option in regimentOptions)
                        _regimentOption(option),
                    ],
                    if (regimentUnits.isNotEmpty) ...[
                      _heading('Regiment composition'),
                      for (final linkedUnit in regimentUnits)
                        if (_asMap(linkedUnit['warscroll'])
                            case final warscroll?)
                          _relatedUnit(context, {
                            ...warscroll,
                            'name': regimentOfRenownUnitLabel(
                              linkedUnit,
                              warscroll,
                            ),
                          }),
                    ],
                    for (final component in components)
                      _component(context, component),
                    if (abilities.isEmpty &&
                        weapons.isEmpty &&
                        components.isEmpty &&
                        _text(unit['lore']) == null &&
                        image == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('No additional description is available.'),
                      ),
                    if (unit['referenceKeywords'] != null)
                      _section(
                        'Keywords',
                        unit['referenceKeywords'].toString(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bannerImage(String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedDataImage(
          imageUrl: url,
          height: 190,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: const SizedBox(
            height: 100,
            child: Center(child: Icon(Icons.image_not_supported_outlined)),
          ),
          errorWidget: const SizedBox(
            height: 100,
            child: Center(child: Icon(Icons.image_not_supported_outlined)),
          ),
        ),
      ),
    );
  }

  Widget _statistics(JsonMap unit) {
    const fields = [
      ('move', 'Move'),
      ('health', 'Health'),
      ('save', 'Save'),
      ('control', 'Control'),
      ('wardSave', 'Ward'),
    ];
    final values = <(String, String)>[];
    for (final field in fields) {
      final value = _text(unit[field.$1]);
      if (value != null) values.add((field.$2, value));
    }
    for (final keyword in const ['Wizard', 'Priest']) {
      final value = _keywordValue(unit, keyword);
      if (value != null) values.add((keyword, value));
    }
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final field in values)
            Chip(
              label: Text('${field.$1}: ${field.$2}'),
            ),
        ],
      ),
    );
  }

  String? _keywordValue(JsonMap unit, String keyword) {
    final referenceKeywords = _text(unit['referenceKeywords']);
    if (referenceKeywords == null) return null;
    final pattern = RegExp(
      '^${RegExp.escape(keyword)}\\s*\\(([^)]+)\\)' r'$',
      caseSensitive: false,
    );
    for (final value in referenceKeywords.split(',')) {
      final match = pattern.firstMatch(value.trim());
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  Widget _weapon(BuildContext context, JsonMap weapon) {
    final name = weapon['name']?.toString() ?? 'Weapon';
    final type = weapon['type']?.toString();
    final abilities = _asMaps(weapon['abilities']);
    final characteristics = [
      if (weapon['range'] != null) ('Rng', weapon['range'].toString()),
      if (weapon['attacks'] != null) ('Atk', weapon['attacks'].toString()),
      if (weapon['hit'] != null) ('Hit', weapon['hit'].toString()),
      if (weapon['wound'] != null) ('Wnd', weapon['wound'].toString()),
      if (weapon['rend'] != null) ('Rend', weapon['rend'].toString()),
      if (weapon['damage'] != null) ('Dmg', weapon['damage'].toString()),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (type != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_capitalize(type)),
                  ),
              ],
            ),
          ),
          if (characteristics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Row(
                children: [
                  for (final stat in characteristics)
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            stat.$1,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              stat.$2,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (abilities.isNotEmpty) const Divider(height: 1),
          for (final ability in abilities) _weaponAbility(ability),
        ],
      ),
    );
  }

  Widget _weaponAbility(JsonMap ability) {
    final rules = _text(ability['rules']);
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      leading: const Icon(Icons.auto_awesome_outlined, size: 18),
      title: Text(ability['name']?.toString() ?? 'Weapon ability'),
      children: [
        if (rules != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_plainText(rules)),
          )
        else
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('No additional description is available.'),
          ),
      ],
    );
  }

  Widget _ability(BuildContext context, JsonMap ability) {
    final phase = _text(ability['phaseDetails']);
    final descriptionFields = [
      ('Declare', _text(ability['declare'])),
      ('Used by', _text(ability['usedBy'])),
      ('Effect', _text(ability['effect'])),
      ('Additional details', _text(ability['altText'])),
      ('Additional rules', _text(ability['additionalRulesText'])),
      ('Rules', _text(ability['rules'])),
    ].where((field) => field.$2 != null);
    final keywords = _asMaps(ability['keywords'])
        .map((keyword) => keyword['name']?.toString())
        .whereType<String>()
        .toList();
    final castingValue = ability['castingValue'];
    final chantingValue = ability['chantingValue'];
    final cost = ability['cost'];
    final metadata = [
      if (castingValue != null) 'Casting $castingValue',
      if (chantingValue != null) 'Chanting $chantingValue',
      if (cost != null) 'Cost $cost',
      if (ability['cpCost'] != null) '${ability['cpCost']} CP',
      if (ability['points'] != null) '${ability['points']} pts',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phase != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.secondaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                _plainText(phase),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        ability['name']?.toString() ?? 'Ability',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final value in metadata)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(value),
                        ),
                    ],
                  ),
                ],
                if (_text(ability['lore']) case final lore?) ...[
                  const SizedBox(height: 8),
                  Text(
                    _plainText(lore),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
                for (final field in descriptionFields)
                  _abilityDescription(context, field.$1, field.$2!),
                if (keywords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final keyword in keywords)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(keyword),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _abilityDescription(
    BuildContext context,
    String label,
    String text,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: _plainText(text)),
          ],
        ),
      ),
    );
  }

  Widget _regimentOption(JsonMap option) {
    final required = _asMaps(option['required_keywords'])
        .map((item) => item['name']?.toString())
        .whereType<String>()
        .toList();
    final excluded = _asMaps(option['excluded_keywords'])
        .map((item) => item['name']?.toString())
        .whereType<String>()
        .toList();
    final lines = [
      if (_text(option['optionText']) != null) _text(option['optionText'])!,
      if (required.isNotEmpty) 'Requires: ${required.join(', ')}',
      if (excluded.isNotEmpty) 'Excludes: ${excluded.join(', ')}',
    ];
    return _section(
      'Regiment option',
      lines.isEmpty ? 'Additional unit option.' : lines.join('\n'),
    );
  }

  Widget _component(BuildContext context, JsonMap component) {
    final image = _imageUrl(component['imageUrl']);
    final title = component['title']?.toString();
    final text = _text(component['textContent']);
    final ability = _asMap(component['ability']);
    final battleTactic = _asMap(component['battleTactic']);
    final bullets = _asMaps(component['bullets']);
    if (image == null &&
        text == null &&
        title == null &&
        ability == null &&
        battleTactic == null &&
        bullets.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (image != null) ...[
              const SizedBox(height: 8),
              _bannerImage(image),
            ],
            if (text != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _plainText(text),
                  style: component['contentType'] == 'textItalic' ||
                          component['contentType'] == 'loreAccordion'
                      ? const TextStyle(fontStyle: FontStyle.italic)
                      : null,
                ),
              ),
            if (bullets.isNotEmpty)
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child:
                      Text('• ${_plainText(bullet['text']?.toString() ?? '')}'),
                ),
            if (ability != null) _ability(context, ability),
            if (battleTactic != null) _battleTactic(context, battleTactic),
          ],
        ),
      ),
    );
  }

  Widget _battleTactic(BuildContext context, JsonMap tactic) {
    final type = tactic['battleTacticType']?.toString();
    final points = tactic['victoryPoints'];
    final lore = _text(tactic['lore']);
    final rules = _text(tactic['rulesText']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  type == null ? 'Battle tactic' : _capitalize(type),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (points != null)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('$points VP'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            tactic['name']?.toString() ?? 'Battle tactic',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (lore != null) ...[
            const SizedBox(height: 6),
            Text(
              _plainText(lore),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                const TextSpan(
                  text: 'Tactics: ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: rules == null
                      ? 'No description is available.'
                      : _plainText(rules),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _relatedUnit(BuildContext context, JsonMap unit) {
    final summonAbility = _asMap(unit['summonAbility']);
    final castingValue = summonAbility?['castingValue'];
    final banishmentValue = _banishmentValue(summonAbility);
    final subtitle = [
      if (castingValue != null) 'Cast $castingValue',
      if ((_isManifestation(unit) || summonAbility != null) &&
          banishmentValue != null)
        'Banish $banishmentValue',
      if (unit['points'] != null) '${unit['points']} pts',
    ].join(' · ');
    return ListTile(
      leading: DataThumbnail(imageUrl: dataImageUrl(unit), size: 40),
      title: Text(unit['name']?.toString() ?? 'Warscroll'),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      onTap: onOpenDetails == null ? null : () => onOpenDetails!(unit),
      trailing: onOpenDetails == null
          ? null
          : IconButton(
              tooltip: 'Show details',
              onPressed: () => onOpenDetails!(unit),
              icon: const Icon(Icons.info_outline),
            ),
    );
  }

  Widget _heading(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _section(String title, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            _paragraph(text),
          ],
        ),
      );

  Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_plainText(text)),
      );

  bool _isAbility(JsonMap item) {
    return item.containsKey('phaseDetails') ||
        item.containsKey('declare') ||
        item.containsKey('effect');
  }

  bool _isWarscroll(JsonMap item) {
    return item.containsKey('referenceKeywords') ||
        item.containsKey('rowImage') ||
        item.containsKey('bannerImage');
  }

  bool _isManifestation(JsonMap item) {
    return item['referenceKeywords']
            ?.toString()
            .split(',')
            .map((keyword) => keyword.trim().toLowerCase())
            .contains('manifestation') ??
        false;
  }

  num? _banishmentValue(JsonMap? summonAbility) {
    final castingValue = summonAbility?['castingValue'];
    return castingValue is num ? castingValue + 1 : null;
  }

  String? _text(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }

  String _plainText(String value) => value.replaceAll('**', '');

  String? _imageUrl(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

String? dataImageUrl(JsonMap item) {
  for (final field in const [
    'bannerImage',
    'rowImage',
    'imageUrl',
    'image',
    'backgroundImage',
  ]) {
    final value = item[field];
    if (value is String && value.trim().isNotEmpty) return value;
  }
  return null;
}

String regimentOfRenownUnitLabel(JsonMap link, JsonMap warscroll) {
  final minimum = (link['minCount'] as num?)?.toInt() ?? 1;
  final maximum = (link['maxCount'] as num?)?.toInt() ?? minimum;
  final count = minimum == maximum ? '$minimum' : '$minimum-$maximum';
  final modelCount = (warscroll['modelCount'] as num?)?.toInt();
  final models = modelCount == null ? '' : '$modelCount ';
  return '$count x $models${warscroll['name'] ?? 'Unit'}';
}

String? dataPreviewImageUrl(JsonMap item) {
  final directImage = dataImageUrl(item);
  if (directImage != null) return directImage;
  for (final relatedItem in _asMaps(item['abilities'])) {
    final image = dataImageUrl(relatedItem);
    if (image != null) return image;
  }
  return null;
}

List<JsonMap> _asMaps(Object? value) {
  if (value is! List) return [];
  return value.whereType<JsonMap>().toList(growable: false);
}

JsonMap? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  return null;
}
