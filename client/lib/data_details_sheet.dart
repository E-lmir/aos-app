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
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: _detailWidgets(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final unit = _asMap((details ?? item)['unit']) ?? item;
    final name = item['name']?.toString() ??
        item['title']?.toString() ??
        unit['name']?.toString() ??
        'Details';
    return Padding(
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
    );
  }

  List<Widget> _detailWidgets(BuildContext context) {
    final displayData = details ?? item;
    final unit = _asMap(displayData['unit']) ?? item;
    final abilities = _asMaps(displayData['abilities'] ?? item['abilities']);
    final weapons = _asMaps(displayData['weapons']);
    final components = _asMaps(displayData['components'] ?? item['components']);
    final characteristics = _asMaps(displayData['additional_characteristics']);
    final regimentOptions = _asMaps(displayData['regiment_options']);
    final regimentUnits = _asMaps(displayData['units'] ?? item['units']);
    final summonAbility = _asMap(item['summonAbility']);
    final image = dataPreviewImageUrl(unit) ?? dataPreviewImageUrl(item);
    return [
      if (image != null) _bannerImage(image),
      _statistics(unit),
      ..._weaponWidgets(context, weapons),
      ..._abilityWidgets(context, abilities),
      ..._summoningWidgets(context, unit, summonAbility),
      ..._descriptionWidgets(unit, characteristics),
      ..._regimentWidgets(context, regimentOptions, regimentUnits),
      ..._componentWidgets(context, components),
      ..._emptyDescriptionWidgets(unit, abilities, weapons, components, image),
      if (unit['referenceKeywords'] != null) _keywordSection(unit),
    ];
  }

  List<Widget> _emptyDescriptionWidgets(
    JsonMap unit,
    List<JsonMap> abilities,
    List<JsonMap> weapons,
    List<JsonMap> components,
    String? image,
  ) {
    if (abilities.isNotEmpty ||
        weapons.isNotEmpty ||
        components.isNotEmpty ||
        _text(unit['lore']) != null ||
        image != null) {
      return [];
    }
    return [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('No additional description is available.'),
      ),
    ];
  }

  Widget _keywordSection(JsonMap unit) =>
      _section('Keywords', unit['referenceKeywords'].toString());

  List<Widget> _weaponWidgets(
    BuildContext context,
    List<JsonMap> weapons,
  ) =>
      [
        if (weapons.isNotEmpty) _heading('Weapon profiles'),
        for (final weapon in weapons) _weapon(context, weapon),
      ];

  List<Widget> _abilityWidgets(
    BuildContext context,
    List<JsonMap> abilities,
  ) {
    final hasDirectAbility = details == null && _isAbility(item);
    if (abilities.isEmpty && !hasDirectAbility) return [];
    final containsOnlyWarscrolls =
        abilities.isNotEmpty && abilities.every(_isWarscroll);
    return [
      _heading(containsOnlyWarscrolls ? 'Manifestations' : 'Abilities'),
      if (hasDirectAbility) _ability(context, item),
      for (final ability in abilities)
        if (_isAbility(ability))
          _ability(context, ability)
        else
          _relatedUnit(context, ability),
    ];
  }

  List<Widget> _summoningWidgets(
    BuildContext context,
    JsonMap unit,
    JsonMap? summonAbility,
  ) {
    final widgets = <Widget>[];
    if (summonAbility != null) {
      widgets
        ..add(_heading('Summoning spell'))
        ..add(_ability(context, summonAbility));
    }
    if (_isManifestation(unit) ||
        _isManifestation(item) ||
        summonAbility != null) {
      widgets.add(_banishmentSection(summonAbility));
    }
    return widgets;
  }

  Widget _banishmentSection(JsonMap? summonAbility) {
    final castingValue = summonAbility?['castingValue'];
    final banishmentValue = _banishmentValue(summonAbility);
    final description = banishmentValue != null
        ? 'Banishment value: $banishmentValue (Cast $castingValue + 1).'
        : "The banishment value is 1 higher than the manifestation's casting "
            'value. The casting value is not available in the source data.';
    return _section('Banishment', description);
  }

  List<Widget> _descriptionWidgets(
    JsonMap unit,
    List<JsonMap> characteristics,
  ) {
    final widgets = <Widget>[];
    if (unit['subname'] is String && (unit['subname'] as String).isNotEmpty) {
      widgets.add(_paragraph(unit['subname'].toString()));
    }
    widgets.addAll(_unitTextSections(unit));
    widgets.addAll(_unitFactSections(unit, characteristics));
    return widgets;
  }

  List<Widget> _unitTextSections(JsonMap unit) => [
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
          if (_text(unit[field.$1]) case final text?) _section(field.$2, text),
      ];

  List<Widget> _unitFactSections(
    JsonMap unit,
    List<JsonMap> characteristics,
  ) =>
      [
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
      ];

  List<Widget> _regimentWidgets(
    BuildContext context,
    List<JsonMap> options,
    List<JsonMap> units,
  ) =>
      [
        if (options.isNotEmpty) _heading('Regiment options'),
        for (final option in options) _regimentOption(option),
        if (units.isNotEmpty) _heading('Regiment composition'),
        for (final linkedUnit in units)
          if (_asMap(linkedUnit['warscroll']) case final warscroll?)
            _relatedUnit(context, {
              ...warscroll,
              'name': regimentOfRenownUnitLabel(linkedUnit, warscroll),
            }),
      ];

  List<Widget> _componentWidgets(
    BuildContext context,
    List<JsonMap> components,
  ) =>
      [
        for (final component in components) _component(context, component),
      ];

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
    final values = _statValues(unit);
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _statChips(values),
      ),
    );
  }

  List<(String, String)> _statValues(JsonMap unit) {
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
    return values;
  }

  List<Widget> _statChips(List<(String, String)> values) => [
        for (final field in values)
          Chip(label: Text('${field.$1}: ${field.$2}')),
      ];

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
    final abilities = _asMaps(weapon['abilities']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _weaponHeader(context, name, weapon['type']),
          _weaponCharacteristics(context, weapon),
          if (abilities.isNotEmpty) const Divider(height: 1),
          for (final ability in abilities) _weaponAbility(ability),
        ],
      ),
    );
  }

  Widget _weaponHeader(BuildContext context, String name, Object? type) =>
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
                label: Text(_capitalize(type.toString())),
              ),
          ],
        ),
      );

  Widget _weaponCharacteristics(BuildContext context, JsonMap weapon) {
    final characteristics = _weaponCharacteristicValues(weapon);
    if (characteristics.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        children: [
          for (final stat in characteristics)
            Expanded(child: _weaponCharacteristic(context, stat)),
        ],
      ),
    );
  }

  List<(String, String)> _weaponCharacteristicValues(JsonMap weapon) => [
        if (weapon['range'] != null) ('Rng', weapon['range'].toString()),
        if (weapon['attacks'] != null) ('Atk', weapon['attacks'].toString()),
        if (weapon['hit'] != null) ('Hit', weapon['hit'].toString()),
        if (weapon['wound'] != null) ('Wnd', weapon['wound'].toString()),
        if (weapon['rend'] != null) ('Rend', weapon['rend'].toString()),
        if (weapon['damage'] != null) ('Dmg', weapon['damage'].toString()),
      ];

  Widget _weaponCharacteristic(BuildContext context, (String, String) stat) =>
      Column(
        children: [
          Text(stat.$1, style: Theme.of(context).textTheme.labelSmall),
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
      );

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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_text(ability['phaseDetails']) case final phase?)
            _abilityPhase(context, phase),
          _abilityBody(context, ability),
        ],
      ),
    );
  }

  Widget _abilityPhase(BuildContext context, String phase) => Container(
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
      );

  Widget _abilityBody(BuildContext context, JsonMap ability) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _abilityTitle(context, ability),
            ..._abilityMetadataWidgets(ability),
            if (_text(ability['lore']) case final lore?)
              _abilityLore(context, lore),
            ..._abilityDescriptions(context, ability),
            ..._abilityKeywords(ability),
          ],
        ),
      );

  Widget _abilityTitle(BuildContext context, JsonMap ability) => Text(
        ability['name']?.toString() ?? 'Ability',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      );

  List<Widget> _abilityMetadataWidgets(JsonMap ability) {
    final metadata = [
      if (ability['castingValue'] != null) 'Casting ${ability['castingValue']}',
      if (ability['chantingValue'] != null)
        'Chanting ${ability['chantingValue']}',
      if (ability['cost'] != null) 'Cost ${ability['cost']}',
      if (ability['cpCost'] != null) '${ability['cpCost']} CP',
      if (ability['points'] != null) '${ability['points']} pts',
    ];
    if (metadata.isEmpty) return [];
    return [
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
    ];
  }

  Widget _abilityLore(BuildContext context, String lore) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _plainText(lore),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
        ),
      );

  List<Widget> _abilityDescriptions(
    BuildContext context,
    JsonMap ability,
  ) {
    const labels = [
      ('Declare', 'declare'),
      ('Used by', 'usedBy'),
      ('Effect', 'effect'),
      ('Additional details', 'altText'),
      ('Additional rules', 'additionalRulesText'),
      ('Rules', 'rules'),
    ];
    return [
      for (final field in labels)
        if (_text(ability[field.$2]) case final text?)
          _abilityDescription(context, field.$1, text),
    ];
  }

  List<Widget> _abilityKeywords(JsonMap ability) {
    final keywords = _asMaps(ability['keywords'])
        .map((keyword) => keyword['name']?.toString())
        .whereType<String>()
        .toList();
    if (keywords.isEmpty) return [];
    return [
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
    ];
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
    final details = _componentDetails(component);
    if (details == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _componentContent(context, component, details),
        ),
      ),
    );
  }

  ({
    String? image,
    String? title,
    String? text,
    JsonMap? ability,
    JsonMap? battleTactic,
    List<JsonMap> bullets,
  })? _componentDetails(JsonMap component) {
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
      return null;
    }
    return (
      image: image,
      title: title,
      text: text,
      ability: ability,
      battleTactic: battleTactic,
      bullets: bullets,
    );
  }

  List<Widget> _componentContent(
    BuildContext context,
    JsonMap component,
    ({
      String? image,
      String? title,
      String? text,
      JsonMap? ability,
      JsonMap? battleTactic,
      List<JsonMap> bullets,
    }) details,
  ) =>
      [
        if (details.title != null)
          Text(
            details.title!,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        if (details.image != null) ...[
          const SizedBox(height: 8),
          _bannerImage(details.image!),
        ],
        if (details.text != null) _componentText(component, details.text!),
        for (final bullet in details.bullets) _componentBullet(bullet),
        if (details.ability != null) _ability(context, details.ability!),
        if (details.battleTactic != null)
          _battleTactic(context, details.battleTactic!),
      ];

  Widget _componentText(JsonMap component, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _plainText(text),
          style: component['contentType'] == 'textItalic' ||
                  component['contentType'] == 'loreAccordion'
              ? const TextStyle(fontStyle: FontStyle.italic)
              : null,
        ),
      );

  Widget _componentBullet(JsonMap bullet) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('• ${_plainText(bullet['text']?.toString() ?? '')}'),
      );

  Widget _battleTactic(BuildContext context, JsonMap tactic) {
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
          _battleTacticHeader(context, tactic),
          const SizedBox(height: 4),
          Text(
            tactic['name']?.toString() ?? 'Battle tactic',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (lore != null) _battleTacticLore(context, lore),
          _battleTacticRules(context, rules),
        ],
      ),
    );
  }

  Widget _battleTacticHeader(BuildContext context, JsonMap tactic) {
    final type = tactic['battleTacticType']?.toString();
    final points = tactic['victoryPoints'];
    return Row(
      children: [
        Expanded(
          child: Text(
            type == null ? 'Battle tactic' : _capitalize(type),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
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
    );
  }

  Widget _battleTacticLore(BuildContext context, String lore) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _plainText(lore),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
        ),
      );

  Widget _battleTacticRules(BuildContext context, String? rules) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text.rich(
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
      );

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
