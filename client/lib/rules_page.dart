import 'package:material_ui/material_ui.dart';

import 'api_client.dart';
import 'data_details_sheet.dart';
import 'data_image_cache.dart';
import 'unit_type_grouping.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  late Future<JsonMap> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = _api.rulesCatalog();
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    ApiClient.clearMemoryCache();
    setState(() => _catalog = _api.rulesCatalog());
    await _catalog;
  }

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler<void>(
      onPop: () => _navigatorKey.currentState?.pop(),
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('Rules'),
              actions: [
                IconButton(
                  tooltip: 'Refresh rules',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: FutureBuilder<JsonMap>(
              future: _catalog,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _RulesErrorView(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _RulesLanding(
                  data: _RulesData(snapshot.data!),
                  api: _api,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RulesLanding extends StatelessWidget {
  const _RulesLanding({required this.data, required this.api});

  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final alliances = data.factions
        .where((faction) => faction['parentFactionKeywordId'] == null)
        .toList()
      ..sort(_compareNames);
    final entries = <Widget>[
      _RulesEntry(
        title: 'Core Documents',
        icon: Icons.menu_book_outlined,
        onTap: () => _push(
            context,
            _RulePublicationsPage(
              title: 'Core Documents',
              publications: data.coreDocuments,
              data: data,
              api: api,
            )),
      ),
      for (final alliance in alliances)
        _RulesEntry(
          title: _allianceName(alliance),
          icon: Icons.shield_outlined,
          onTap: () => _push(
            context,
            _AllianceFactionsPage(alliance: alliance, data: data, api: api),
          ),
        ),
      _RulesEntry(
        title: 'Regiments of Renown',
        icon: Icons.groups_outlined,
        onTap: () => _push(context, _RegimentsPage(data: data, api: api)),
      ),
      _RulesEntry(
        title: 'Armies of Renown',
        icon: Icons.shield_outlined,
        onTap: () => _push(context, _ArmiesOfRenownPage(data: data, api: api)),
      ),
      _RulesEntry(
        title: 'Manifestations',
        icon: Icons.auto_awesome_outlined,
        onTap: () => _push(context, _ManifestationsPage(data: data, api: api)),
      ),
      _RulesEntry(
        title: 'Legends',
        icon: Icons.history_edu_outlined,
        onTap: () => _push(context, _LegendsPage(data: data, api: api)),
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: entries,
    );
  }
}

class _RulesEntry extends StatelessWidget {
  const _RulesEntry({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _AllianceFactionsPage extends StatelessWidget {
  const _AllianceFactionsPage({
    required this.alliance,
    required this.data,
    required this.api,
  });

  final JsonMap alliance;
  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final factions = data.factions
        .where((faction) => faction['parentFactionKeywordId'] == alliance['id'])
        .toList();
    if (_allianceName(alliance) == 'Destruction') {
      final orruks = factions
          .where((faction) => faction['name'] == 'Orruk Warclans')
          .firstOrNull;
      if (orruks != null) {
        factions
          ..remove(orruks)
          ..addAll(data.factions.where((faction) =>
              faction['parentFactionKeywordId'] == orruks['id'] &&
              faction['armyOfRenown'] != true));
      }
    }
    factions.sort(_compareNames);
    return Scaffold(
      appBar: AppBar(title: Text(_allianceName(alliance))),
      body: factions.isEmpty
          ? const Center(child: Text('No factions are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final faction in factions)
                  Card(
                    child: ListTile(
                      title: Text(faction['name']?.toString() ?? 'Faction'),
                      subtitle: _factionSubtitle(faction),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _push(
                          context,
                          _FactionRulesPage(
                            faction: faction,
                            data: data,
                            api: api,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Widget? _factionSubtitle(JsonMap faction) {
    return faction['armyOfRenown'] == true
        ? const Text('Army of Renown')
        : null;
  }
}

class _FactionRulesPage extends StatefulWidget {
  const _FactionRulesPage({
    required this.faction,
    required this.data,
    required this.api,
  });

  final JsonMap faction;
  final _RulesData data;
  final ApiClient api;

  @override
  State<_FactionRulesPage> createState() => _FactionRulesPageState();
}

class _FactionRulesPageState extends State<_FactionRulesPage> {
  late Future<JsonMap> _configuration;

  @override
  void initState() {
    super.initState();
    _configuration = _loadConfiguration();
  }

  Future<JsonMap> _loadConfiguration() => widget.api.builderConfiguration(
        widget.faction['id'].toString(),
      );

  Future<void> _retry() async {
    ApiClient.clearMemoryCache();
    setState(() => _configuration = _loadConfiguration());
    await _configuration;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.faction['name']?.toString() ?? 'Faction';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<JsonMap>(
        future: _configuration,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildContent(
              context,
              const {},
              configurationError: snapshot.error.toString(),
            );
          }
          if (!snapshot.hasData) {
            return _buildContent(
              context,
              const {},
              configurationLoading: true,
            );
          }
          return _buildContent(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    JsonMap configuration, {
    bool configurationLoading = false,
    String? configurationError,
  }) {
    final faction = widget.faction;
    final factionId = faction['id'];
    final publicationsFactionId = faction['armyOfRenown'] == true
        ? faction['parentFactionKeywordId']
        : factionId;
    var publications = widget.data.publications
        .where((publication) =>
            publication['factionKeywordId'] == publicationsFactionId &&
            publication['hiddenFromSearch'] != true)
        .toList();
    if (faction['armyOfRenown'] == true) {
      publications = publications
          .where((publication) => (publication['name']?.toString() ?? '')
              .contains('Army of Renown'))
          .toList();
      if (publications.length > 1) {
        final matching = publications
            .where((publication) => (publication['name']?.toString() ?? '')
                .contains(faction['name']?.toString() ?? ''))
            .toList();
        if (matching.isNotEmpty) publications = matching;
      }
    }
    publications.sort(_compareNames);
    final armiesOfRenown = widget.data.factions
        .where((candidate) =>
            candidate['parentFactionKeywordId'] == factionId &&
            candidate['armyOfRenown'] == true)
        .toList()
      ..sort(_compareNames);
    final enhancements =
        _asMap(configuration['enhancements']) ?? const <String, dynamic>{};
    final entries = <Widget>[
      if (_factionHeaderImage(faction) case final image?)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedDataImage(
              imageUrl: image,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
            ),
          ),
        ),
      _RulesEntry(
        title: 'Warscrolls',
        icon: Icons.shield_outlined,
        onTap: () => _push(
          context,
          _FactionWarscrollsPage(
            faction: faction,
            api: widget.api,
          ),
        ),
      ),
    ];
    if (configurationLoading) {
      entries.add(
        const Card(
          child: ListTile(
            leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Loading faction rules…'),
          ),
        ),
      );
    }
    if (configurationError != null) {
      entries.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Faction rules could not be loaded.'),
                const SizedBox(height: 4),
                Text(configurationError),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _retry,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    void addSection(String title, Object? value, {IconData? icon}) {
      final items = _asMaps(value);
      if (items.isEmpty) return;
      entries.add(
        _FactionRulesSection(
          title: title,
          items: items,
          icon: icon,
          onSelected: (item) => _showFactionItem(context, item),
        ),
      );
    }

    addSection(
      'Battle Traits',
      configuration['battle_traits'],
      icon: Icons.military_tech_outlined,
    );
    addSection('Battle Formations', configuration['battle_formations']);
    addSection(
      'Artefacts of Power',
      enhancements['artefacts'],
      icon: Icons.auto_awesome_outlined,
    );
    addSection(
      'Heroic Traits',
      enhancements['heroic_traits'],
      icon: Icons.star_outline,
    );
    addSection('Spell Lores', configuration['spell_lores']);
    addSection('Prayer Lores', configuration['prayer_lores']);
    addSection(
      'Other Enhancements',
      enhancements['other'],
      icon: Icons.build_outlined,
    );
    addSection('Regiments of Renown', configuration['regiments_of_renown']);
    final unitKeywords =
        _factionUnitKeywords[faction['name']?.toString()] ?? const <String>[];
    if (unitKeywords.isNotEmpty) {
      entries.add(
        _FactionRulesSection(
          title: 'Units Keywords',
          icon: Icons.label_outline,
          items: [
            for (final keyword in unitKeywords)
              {'id': keyword, 'name': keyword},
          ],
          onSelected: (item) => _push(
            context,
            _FactionWarscrollsPage(
              faction: faction,
              api: widget.api,
              keyword: item['name']?.toString(),
            ),
          ),
        ),
      );
    }
    if (publications.isNotEmpty) {
      entries.add(
        _RulesEntry(
          title: 'Faction Publications',
          icon: Icons.menu_book_outlined,
          onTap: () => _push(
            context,
            _RulePublicationsPage(
              title: faction['name']?.toString() ?? 'Faction',
              publications: publications,
              data: widget.data,
              api: widget.api,
            ),
          ),
        ),
      );
    }
    if (armiesOfRenown.isNotEmpty) {
      entries.add(
        _FactionRulesSection(
          title: 'Armies of Renown',
          icon: Icons.groups_outlined,
          items: armiesOfRenown,
          onSelected: (army) => _push(
            context,
            _FactionRulesPage(
              faction: army,
              data: widget.data,
              api: widget.api,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: entries,
    );
  }

  Future<void> _showFactionItem(BuildContext context, JsonMap item) async {
    if (item['referenceKeywords'] is String) {
      await _openWarscrollDetails(context, widget.api, item);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DataDetailsSheet(
        item: item,
        onOpenDetails: (unit) =>
            _openWarscrollDetails(context, widget.api, unit),
      ),
    );
  }
}

class _FactionRulesSection extends StatelessWidget {
  const _FactionRulesSection({
    required this.title,
    required this.items,
    required this.onSelected,
    this.icon,
  });

  final String title;
  final List<JsonMap> items;
  final ValueChanged<JsonMap> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final sectionIcon = icon ?? Icons.shield_outlined;
    return Card(
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(
              sectionIcon,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        children: [
          for (final item in items)
            ListTile(
              leading: DataThumbnail(
                imageUrl: dataPreviewImageUrl(item),
                size: 36,
              ),
              title: Text(item['name']?.toString() ?? title),
              subtitle:
                  item['points'] == null ? null : Text('${item['points']} pts'),
              onTap: () => onSelected(item),
            ),
        ],
      ),
    );
  }
}

class _FactionWarscrollsPage extends StatefulWidget {
  const _FactionWarscrollsPage({
    required this.faction,
    required this.api,
    this.keyword,
  });

  final JsonMap faction;
  final ApiClient api;
  final String? keyword;

  @override
  State<_FactionWarscrollsPage> createState() => _FactionWarscrollsPageState();
}

class _FactionWarscrollsPageState extends State<_FactionWarscrollsPage> {
  late Future<List<JsonMap>> _warscrolls;

  @override
  void initState() {
    super.initState();
    _warscrolls =
        widget.api.rulesFactionWarscrolls(widget.faction['id'].toString());
  }

  Future<void> _retry() async {
    ApiClient.clearMemoryCache();
    setState(() {
      _warscrolls =
          widget.api.rulesFactionWarscrolls(widget.faction['id'].toString());
    });
    await _warscrolls;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.keyword == null
              ? '${widget.faction['name'] ?? 'Faction'} Warscrolls'
              : '${widget.keyword} Warscrolls',
        ),
      ),
      body: FutureBuilder<List<JsonMap>>(
        future: _warscrolls,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _RulesErrorView(
              message: snapshot.error.toString(),
              onRetry: _retry,
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final warscrolls = snapshot.data!.where((unit) {
            final keyword = widget.keyword;
            if (keyword == null) return true;
            return (unit['referenceKeywords']?.toString() ?? '')
                .split(',')
                .map((value) => value.trim())
                .contains(keyword);
          }).toList();
          if (warscrolls.isEmpty) {
            return const Center(child: Text('No warscrolls are available.'));
          }
          final groups = groupBuilderUnitsByType(warscrolls);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final group in groups)
                Card(
                  child: ExpansionTile(
                    title: Text(group.title),
                    children: [
                      for (final unit in group.items)
                        ListTile(
                          leading: DataThumbnail(
                            imageUrl: dataImageUrl(unit),
                            size: 38,
                          ),
                          title: Text(unit['name']?.toString() ?? 'Warscroll'),
                          subtitle: unit['points'] == null
                              ? null
                              : Text('${unit['points']} pts'),
                          onTap: () =>
                              _openWarscrollDetails(context, widget.api, unit),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RulePublicationsPage extends StatelessWidget {
  const _RulePublicationsPage({
    required this.title,
    required this.publications,
    required this.data,
    required this.api,
  });

  final String title;
  final List<JsonMap> publications;
  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: publications.isEmpty
          ? const Center(child: Text('No rules publications are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final publication in publications)
                  Card(
                    child: ListTile(
                      leading: DataThumbnail(
                        imageUrl: publication['backgroundImage']?.toString(),
                        size: 42,
                      ),
                      title: Text(
                        publication['name']?.toString() ?? 'Publication',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(
                        context,
                        _PublicationSectionsPage(
                          publication: publication,
                          data: data,
                          api: api,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PublicationSectionsPage extends StatelessWidget {
  const _PublicationSectionsPage({
    required this.publication,
    required this.data,
    required this.api,
  });

  final JsonMap publication;
  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final sections = data.sections
        .where((section) =>
            section['publicationId'] == publication['id'] &&
            section['parentId'] == null)
        .toList()
      ..sort(_compareOrders);
    return Scaffold(
      appBar: AppBar(
        title: Text(publication['name']?.toString() ?? 'Rules'),
      ),
      body: sections.isEmpty
          ? const Center(child: Text('No sections are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final section in sections)
                  _SectionTile(
                    section: section,
                    data: data,
                    api: api,
                  ),
              ],
            ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.data,
    required this.api,
  });

  final JsonMap section;
  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(section['name']?.toString() ?? 'Section'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _push(
          context,
          _RuleSectionPage(section: section, data: data, api: api),
        ),
      ),
    );
  }
}

class _RuleSectionPage extends StatefulWidget {
  const _RuleSectionPage({
    required this.section,
    required this.data,
    required this.api,
  });

  final JsonMap section;
  final _RulesData data;
  final ApiClient api;

  @override
  State<_RuleSectionPage> createState() => _RuleSectionPageState();
}

class _RuleSectionPageState extends State<_RuleSectionPage> {
  late final List<JsonMap> _children;
  late Future<JsonMap> _rules;

  @override
  void initState() {
    super.initState();
    _children = widget.data.sections
        .where((section) => section['parentId'] == widget.section['id'])
        .toList()
      ..sort(_compareOrders);
    _rules = _children.isEmpty
        ? widget.api.rulesSection(widget.section['id'].toString())
        : Future<JsonMap>.value(const {});
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.section['name']?.toString() ?? 'Rules';
    if (_children.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final child in _children)
              _SectionTile(
                section: child,
                data: widget.data,
                api: widget.api,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<JsonMap>(
        future: _rules,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _RulesErrorView(
              message: snapshot.error.toString(),
              onRetry: () async {
                ApiClient.clearMemoryCache();
                setState(() {
                  _rules = widget.api.rulesSection(
                    widget.section['id'].toString(),
                  );
                });
                await _rules;
              },
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = _asMaps(snapshot.data!['rules']);
          if (rules.isEmpty) {
            return const Center(child: Text('No rules are available.'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final rule in rules) _RuleContainerCard(rule: rule),
            ],
          );
        },
      ),
    );
  }
}

class _RuleContainerCard extends StatelessWidget {
  const _RuleContainerCard({required this.rule});

  final JsonMap rule;

  @override
  Widget build(BuildContext context) {
    final components = _asMaps(rule['components']);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rule['title'] is String)
              Text(
                rule['title'].toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            if (rule['subtitle'] is String) ...[
              const SizedBox(height: 4),
              Text(rule['subtitle'].toString()),
            ],
            for (final component in components)
              _RuleComponentView(component: component),
          ],
        ),
      ),
    );
  }
}

class _RuleComponentView extends StatelessWidget {
  const _RuleComponentView({required this.component});

  final JsonMap component;

  @override
  Widget build(BuildContext context) {
    final type = component['contentType']?.toString();
    final text = component['textContent']?.toString();
    if (type == 'ability') {
      return _RuleAbilityView(
        ability: _asMap(component['ability']) ?? const <String, dynamic>{},
      );
    }
    if (type == 'battleTactic') {
      final tactic = _asMap(component['battleTactic']);
      if (tactic == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tactic['name']?.toString() ?? 'Battle tactic',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (tactic['rulesText'] is String)
              Text(_plainText(tactic['rulesText'].toString())),
          ],
        ),
      );
    }
    if (type == 'bullets') {
      final bullets = _asMaps(component['bullets']);
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final bullet in bullets)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child:
                    Text('• ${_plainText(bullet['text']?.toString() ?? '')}'),
              ),
          ],
        ),
      );
    }
    if (type == 'image') {
      final imageUrl = component['imageUrl']?.toString();
      if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: CachedDataImage(
          imageUrl: imageUrl,
          width: double.infinity,
          fit: BoxFit.contain,
          placeholder: const SizedBox.shrink(),
          errorWidget: const Text('Rule image could not be loaded.'),
        ),
      );
    }
    if (type == 'accordion') {
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(component['title']?.toString() ?? 'Additional rule'),
        children: [
          if (text != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_plainText(text)),
            ),
        ],
      );
    }
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final style = switch (type) {
      'header' || 'textBold' => const TextStyle(fontWeight: FontWeight.bold),
      'textItalic' || 'loreAccordion' => const TextStyle(
          fontStyle: FontStyle.italic,
        ),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _plainText(text),
        style: style,
      ),
    );
  }
}

class _RuleAbilityView extends StatelessWidget {
  const _RuleAbilityView({required this.ability});

  final JsonMap ability;

  @override
  Widget build(BuildContext context) {
    final fields = [
      ('Declare', ability['declare']),
      ('Used by', ability['usedBy']),
      ('Effect', ability['effect']),
      ('Additional details', ability['altText']),
      ('Additional rules', ability['additionalRulesText']),
      ('Rules', ability['rules']),
    ].where((field) => field.$2 is String && (field.$2 as String).isNotEmpty);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(ability['name']?.toString() ?? 'Ability'),
      subtitle: ability['phaseDetails'] is String
          ? Text(_plainText(ability['phaseDetails'].toString()))
          : null,
      children: [
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${field.$1}: ${_plainText(field.$2.toString())}',
              ),
            ),
          ),
      ],
    );
  }
}

class _RegimentsPage extends StatelessWidget {
  const _RegimentsPage({required this.data, required this.api});

  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final regiments = [...data.regiments]..sort(_compareNames);
    return Scaffold(
      appBar: AppBar(title: const Text('Regiments of Renown')),
      body: regiments.isEmpty
          ? const Center(child: Text('No Regiments of Renown are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final regiment in regiments)
                  Builder(
                    builder: (context) {
                      final units = data.regimentUnits(regiment);
                      final image = regiment['image'] ??
                          data.warscrollById(
                            regiment['regimentOfRenownRowImageWarscrollId'],
                          )?['rowImage'];
                      return Card(
                        child: ListTile(
                          leading: DataThumbnail(
                            imageUrl: image?.toString(),
                            size: 40,
                          ),
                          title: Text(
                            regiment['name']?.toString() ?? 'Regiment',
                          ),
                          subtitle:
                              regiment['regimentOfRenownPointsCost'] == null
                                  ? null
                                  : Text(
                                      '${regiment['regimentOfRenownPointsCost']} pts',
                                    ),
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) => DataDetailsSheet(
                              item: {
                                ...regiment,
                                if (image != null) 'image': image,
                                'units': units,
                              },
                              onOpenDetails: (unit) =>
                                  _openWarscrollDetails(context, api, unit),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _ArmiesOfRenownPage extends StatelessWidget {
  const _ArmiesOfRenownPage({required this.data, required this.api});

  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final armies = data.factions
        .where((faction) => faction['armyOfRenown'] == true)
        .toList();
    final groups = <String, List<JsonMap>>{};
    final factionNames = <String, String>{};
    for (final army in armies) {
      final parentId = army['parentFactionKeywordId'];
      final parent = data.factions
          .where((faction) => faction['id'] == parentId)
          .firstOrNull;
      final groupId = parent?['id']?.toString() ?? 'unassigned';
      groups.putIfAbsent(groupId, () => []).add(army);
      factionNames[groupId] = parent?['name']?.toString() ?? 'Other Factions';
    }

    final groupIds = groups.keys.toList()
      ..sort((first, second) =>
          factionNames[first]!.compareTo(factionNames[second]!));
    for (final group in groups.values) {
      group.sort(_compareNames);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Armies of Renown')),
      body: armies.isEmpty
          ? const Center(child: Text('No Armies of Renown are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final groupId in groupIds) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8,
                      left: 4,
                      right: 4,
                      bottom: 4,
                    ),
                    child: Text(
                      factionNames[groupId]!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final army in groups[groupId]!)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(army['name']?.toString() ?? 'Army'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _push(
                          context,
                          _FactionRulesPage(
                            faction: army,
                            data: data,
                            api: api,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _ManifestationsPage extends StatelessWidget {
  const _ManifestationsPage({required this.data, required this.api});

  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final lores = [...data.manifestationLores]..sort(_compareNames);
    return Scaffold(
      appBar: AppBar(title: const Text('Manifestations')),
      body: lores.isEmpty
          ? const Center(child: Text('No manifestations are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final lore in lores)
                  Builder(
                    builder: (context) {
                      final units = data.manifestationsFor(lore);
                      return Card(
                        child: ExpansionTile(
                          title: Text(lore['name']?.toString() ?? 'Lore'),
                          subtitle: lore['points'] == null
                              ? null
                              : Text('${lore['points']} pts'),
                          children: [
                            for (final unit in units)
                              ListTile(
                                leading: DataThumbnail(
                                  imageUrl: dataImageUrl(unit),
                                  size: 38,
                                ),
                                title: Text(
                                  unit['name']?.toString() ?? 'Manifestation',
                                ),
                                subtitle: _manifestationSubtitle(unit),
                                onTap: () =>
                                    _openWarscrollDetails(context, api, unit),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }

  Widget? _manifestationSubtitle(JsonMap unit) {
    final ability = _asMap(unit['summonAbility']);
    final cast = ability?['castingValue'];
    if (cast is! num) return null;
    return Text('Cast $cast · Banish ${cast + 1}');
  }
}

class _LegendsPage extends StatelessWidget {
  const _LegendsPage({required this.data, required this.api});

  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final alliances = data.factions
        .where((faction) => faction['parentFactionKeywordId'] == null)
        .toList()
      ..sort(_compareNames);
    return Scaffold(
      appBar: AppBar(title: const Text('Legends')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final alliance in alliances)
            Builder(
              builder: (context) {
                final name = _allianceName(alliance);
                final units = data.warscrolls
                    .where((unit) =>
                        unit['isLegends'] == true &&
                        (unit['referenceKeywords']?.toString() ?? '')
                            .contains(name))
                    .toList()
                  ..sort(_compareNames);
                return Card(
                  child: ExpansionTile(
                    title: Text(name),
                    children: [
                      for (final unit in units)
                        ListTile(
                          leading: DataThumbnail(
                            imageUrl: dataImageUrl(unit),
                            size: 38,
                          ),
                          title: Text(unit['name']?.toString() ?? 'Warscroll'),
                          subtitle: unit['points'] == null
                              ? null
                              : Text('${unit['points']} pts'),
                          onTap: () =>
                              _openWarscrollDetails(context, api, unit),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

const _factionUnitKeywords = <String, List<String>>{
  'Blades of Khorne': ['Daemon', 'Bloodbound'],
  'Disciples of Tzeentch': ['Daemon', 'Arcanite', 'Warflock'],
  'Hedonites of Slaanesh': ['Daemon', 'Sybarite'],
  'Helsmiths of Hashut': ['Duardin', 'Automaton'],
  'Maggotkin of Nurgle': ['Rotbringers', 'Daemon'],
  'Skaven': [
    'Skryre',
    'Verminus',
    'Eshin',
    'Masterclan',
    'Moulder',
    'Pestilens',
    'Daemon'
  ],
  'Slaves to Darkness': [
    'Warriors of Chaos',
    'Daemon',
    'Darkoath',
    'Pledged to Tzeentch',
  ],
  'Flesh-eater Courts': ['Abhorrant', 'Noble', 'Knights', 'Serfs'],
  'Soulblight Gravelords': ['Vampire', 'Deadwalkers', 'Deathrattle'],
  'Gloomspite Gitz': ['Troggoth', 'Gitmob', 'Moonclan', 'Squig', 'Spiderfang'],
  'Ironjawz': ['Maw-krusha', 'Maw‑grunta', 'Brute'],
  'Ogor Mawtribes': ['Gutbusters', 'Beastclaw Raiders'],
  'Sons of Behemat': ['Big', 'Little'],
  'Cities of Sigmar': ['Aelf', 'Duardin', 'Sigmarite'],
  'Daughters of Khaine': ['Aelf'],
  'Fyreslayers': ['Magmadroth'],
  'Idoneth Deepkin': ['Akhelian', 'Eidolon', 'Isharann', 'Namarti'],
  'Kharadron Overlords': ['Skyfarer', 'Skyvessel', 'Auto-Endrin'],
  'Lumineth Realm-lords': [
    'Alarith',
    'Vanari',
    'Scinari',
    'Hurakan',
    'Ydrilan',
  ],
  'Seraphon': ['Slann', 'Skink', 'Saurus', 'Kroxigor'],
  'Stormcast Eternals': [
    'Extremis Chamber',
    'Warrior Chamber',
    'Ruination Chamber',
    'Vanguard Chamber',
  ],
  'Sylvaneth': ['Kurnothi', 'Forest Elder', 'Revenant'],
};

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

JsonMap? _asMap(Object? value) {
  return value is Map<String, dynamic> ? value : null;
}

Future<void> _openWarscrollDetails(
  BuildContext context,
  ApiClient api,
  JsonMap unit,
) async {
  final id = unit['id']?.toString();
  if (id == null || id.isEmpty) return;
  final details = api.builderWarscrollDetails(id);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FutureBuilder<JsonMap>(
      future: details,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child:
                  Text('Could not load warscroll details: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return DataDetailsSheet(
          item: unit,
          details: snapshot.data,
          onOpenDetails: (relatedUnit) =>
              _openWarscrollDetails(context, api, relatedUnit),
        );
      },
    ),
  );
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => page),
  );
}

List<JsonMap> _asMaps(Object? value) {
  if (value is! List) return [];
  return value.whereType<Map<String, dynamic>>().toList();
}

int _compareNames(JsonMap left, JsonMap right) {
  return (left['name']?.toString() ?? '')
      .compareTo(right['name']?.toString() ?? '');
}

int _compareOrders(JsonMap left, JsonMap right) {
  final order = ((left['displayOrder'] as num?)?.toInt() ?? 0)
      .compareTo((right['displayOrder'] as num?)?.toInt() ?? 0);
  return order != 0 ? order : _compareNames(left, right);
}

String _allianceName(JsonMap alliance) {
  final name = alliance['name']?.toString() ?? '';
  return name.startsWith('Grand Alliance ')
      ? name.substring('Grand Alliance '.length)
      : name;
}

String? _factionHeaderImage(JsonMap faction) {
  final image = faction['rosterHeaderImage'] ?? faction['factionHeaderImage'];
  return image is String && image.trim().isNotEmpty ? image : null;
}

String _plainText(String text) => text.replaceAll('**', '');

class _RulesErrorView extends StatelessWidget {
  const _RulesErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
