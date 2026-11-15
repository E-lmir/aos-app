import 'package:material_ui/material_ui.dart';

import 'api_client.dart';
import 'data_details_sheet.dart';
import 'data_image_cache.dart';
import 'unit_type_grouping.dart';

part 'models/_rules_data.dart';

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
        onGenerateRoute: _rulesRoute,
      ),
    );
  }

  MaterialPageRoute<void> _rulesRoute(RouteSettings settings) =>
      MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _rulesHome(),
      );

  Widget _rulesHome() => Scaffold(
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
          builder: _catalogContent,
        ),
      );

  Widget _catalogContent(
    BuildContext context,
    AsyncSnapshot<JsonMap> snapshot,
  ) {
    if (snapshot.hasError) {
      return _RulesErrorView(
        message: snapshot.error.toString(),
        onRetry: _refresh,
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    return _RulesLanding(data: _RulesData(snapshot.data!), api: _api);
  }
}

class _RulesLanding extends StatelessWidget {
  const _RulesLanding({required this.data, required this.api});

  final _RulesData data;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: _entries(context),
    );
  }

  List<Widget> _entries(BuildContext context) => [
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
            ),
          ),
        ),
        ..._allianceEntries(context),
        ..._specialRuleEntries(context),
      ];

  List<Widget> _allianceEntries(BuildContext context) {
    final alliances = data.factions
        .where((faction) => faction['parentFactionKeywordId'] == null)
        .toList()
      ..sort(_compareNames);
    return [
      for (final alliance in alliances)
        _RulesEntry(
          title: _allianceName(alliance),
          icon: Icons.shield_outlined,
          onTap: () => _push(
            context,
            _AllianceFactionsPage(alliance: alliance, data: data, api: api),
          ),
        ),
    ];
  }

  List<Widget> _specialRuleEntries(BuildContext context) => [
        _RulesEntry(
          title: 'Regiments of Renown',
          icon: Icons.groups_outlined,
          onTap: () => _push(context, _RegimentsPage(data: data, api: api)),
        ),
        _RulesEntry(
          title: 'Armies of Renown',
          icon: Icons.shield_outlined,
          onTap: () =>
              _push(context, _ArmiesOfRenownPage(data: data, api: api)),
        ),
        _RulesEntry(
          title: 'Manifestations',
          icon: Icons.auto_awesome_outlined,
          onTap: () =>
              _push(context, _ManifestationsPage(data: data, api: api)),
        ),
        _RulesEntry(
          title: 'Legends',
          icon: Icons.history_edu_outlined,
          onTap: () => _push(context, _LegendsPage(data: data, api: api)),
        ),
      ];
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
    final factions = _allianceFactions();
    return Scaffold(
      appBar: AppBar(title: Text(_allianceName(alliance))),
      body: factions.isEmpty
          ? const Center(child: Text('No factions are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final faction in factions) _factionCard(context, faction),
              ],
            ),
    );
  }

  List<JsonMap> _allianceFactions() {
    final factions = data.factions
        .where((faction) => faction['parentFactionKeywordId'] == alliance['id'])
        .toList();
    if (_allianceName(alliance) == 'Destruction') {
      _replaceOrrukFaction(factions);
    }
    return factions..sort(_compareNames);
  }

  void _replaceOrrukFaction(List<JsonMap> factions) {
    final orruks = factions
        .where((faction) => faction['name'] == 'Orruk Warclans')
        .firstOrNull;
    if (orruks == null) return;
    factions
      ..remove(orruks)
      ..addAll(data.factions.where((faction) =>
          faction['parentFactionKeywordId'] == orruks['id'] &&
          faction['armyOfRenown'] != true));
  }

  Widget _factionCard(BuildContext context, JsonMap faction) => Card(
        child: ListTile(
          title: Text(faction['name']?.toString() ?? 'Faction'),
          subtitle: _factionSubtitle(faction),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(
            context,
            _FactionRulesPage(faction: faction, data: data, api: api),
          ),
        ),
      );

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
    final entries = <Widget>[
      ..._factionHeaderEntries(context, faction),
      ..._configurationStatusEntries(configurationLoading, configurationError),
    ];
    entries.addAll(_configurationSections(context, faction, configuration));
    entries.addAll(_publicationEntries(context, faction));
    entries.addAll(_renownEntries(context, faction));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: entries,
    );
  }

  List<Widget> _factionHeaderEntries(
    BuildContext context,
    JsonMap faction,
  ) =>
      [
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
            _FactionWarscrollsPage(faction: faction, api: widget.api),
          ),
        ),
      ];

  List<Widget> _configurationStatusEntries(bool loading, String? error) => [
        if (loading)
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
        if (error != null) _configurationErrorCard(error),
      ];

  Widget _configurationErrorCard(String error) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Faction rules could not be loaded.'),
              const SizedBox(height: 4),
              Text(error),
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
      );

  List<Widget> _configurationSections(
    BuildContext context,
    JsonMap faction,
    JsonMap configuration,
  ) {
    final enhancements =
        _asMap(configuration['enhancements']) ?? const <String, dynamic>{};
    return [
      ..._ruleSection(context, 'Battle Traits', configuration['battle_traits'],
          icon: Icons.military_tech_outlined),
      ..._ruleSection(
          context, 'Battle Formations', configuration['battle_formations']),
      ..._ruleSection(context, 'Artefacts of Power', enhancements['artefacts'],
          icon: Icons.auto_awesome_outlined),
      ..._ruleSection(context, 'Heroic Traits', enhancements['heroic_traits'],
          icon: Icons.star_outline),
      ..._ruleSection(context, 'Spell Lores', configuration['spell_lores']),
      ..._ruleSection(context, 'Prayer Lores', configuration['prayer_lores']),
      ..._ruleSection(context, 'Other Enhancements', enhancements['other'],
          icon: Icons.build_outlined),
      ..._ruleSection(
          context, 'Regiments of Renown', configuration['regiments_of_renown']),
      ..._unitKeywordEntries(context, faction),
    ];
  }

  List<Widget> _ruleSection(
    BuildContext context,
    String title,
    Object? value, {
    IconData? icon,
  }) {
    final items = _asMaps(value);
    if (items.isEmpty) return [];
    return [_buildFactionRulesSection(context, title, items, icon)];
  }

  Widget _buildFactionRulesSection(
    BuildContext context,
    String title,
    List<JsonMap> items,
    IconData? icon,
  ) =>
      _FactionRulesSection(
        title: title,
        items: items,
        icon: icon,
        onSelected: (item) => _showFactionItem(context, item),
      );

  List<Widget> _unitKeywordEntries(
    BuildContext context,
    JsonMap faction,
  ) {
    final keywords =
        _factionUnitKeywords[faction['name']?.toString()] ?? const <String>[];
    if (keywords.isEmpty) return [];
    return [
      _FactionRulesSection(
        title: 'Units Keywords',
        icon: Icons.label_outline,
        items: [
          for (final keyword in keywords) {'id': keyword, 'name': keyword},
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
    ];
  }

  List<Widget> _publicationEntries(
    BuildContext context,
    JsonMap faction,
  ) {
    final publications = _factionPublications(faction);
    if (publications.isEmpty) return [];
    return [
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
    ];
  }

  List<JsonMap> _factionPublications(JsonMap faction) {
    final publicationsFactionId = faction['armyOfRenown'] == true
        ? faction['parentFactionKeywordId']
        : faction['id'];
    var publications = widget.data.publications
        .where((publication) =>
            publication['factionKeywordId'] == publicationsFactionId &&
            publication['hiddenFromSearch'] != true)
        .toList();
    if (faction['armyOfRenown'] == true) {
      publications = _armyOfRenownPublications(faction, publications);
    }
    return publications..sort(_compareNames);
  }

  List<JsonMap> _armyOfRenownPublications(
    JsonMap faction,
    List<JsonMap> publications,
  ) {
    publications = publications
        .where((publication) =>
            (publication['name']?.toString() ?? '').contains('Army of Renown'))
        .toList();
    if (publications.length <= 1) return publications;
    final matching = publications
        .where((publication) => (publication['name']?.toString() ?? '')
            .contains(faction['name']?.toString() ?? ''))
        .toList();
    return matching.isNotEmpty ? matching : publications;
  }

  List<Widget> _renownEntries(
    BuildContext context,
    JsonMap faction,
  ) {
    final factionId = faction['id'];
    final armies = widget.data.factions
        .where((candidate) =>
            candidate['parentFactionKeywordId'] == factionId &&
            candidate['armyOfRenown'] == true)
        .toList()
      ..sort(_compareNames);
    if (armies.isEmpty) return [];
    return [
      _FactionRulesSection(
        title: 'Armies of Renown',
        icon: Icons.groups_outlined,
        items: armies,
        onSelected: (army) => _push(
          context,
          _FactionRulesPage(
            faction: army,
            data: widget.data,
            api: widget.api,
          ),
        ),
      ),
    ];
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
    return Card(
      child: ExpansionTile(
        title: _sectionTitle(context),
        children: _itemTiles(),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context) => Row(
        children: [
          Icon(
            icon ?? Icons.shield_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
        ],
      );

  List<Widget> _itemTiles() => [
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
      ];
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
        builder: _buildWarscrollState,
      ),
    );
  }

  Widget _buildWarscrollState(
    BuildContext context,
    AsyncSnapshot<List<JsonMap>> snapshot,
  ) {
    if (snapshot.hasError) {
      return _RulesErrorView(
        message: snapshot.error.toString(),
        onRetry: _retry,
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    return _warscrollResults(context, snapshot.data!);
  }

  Widget _warscrollResults(BuildContext context, List<JsonMap> units) {
    final warscrolls = units.where(_matchesKeyword).toList();
    if (warscrolls.isEmpty) {
      return const Center(child: Text('No warscrolls are available.'));
    }
    final groups = groupBuilderUnitsByType(warscrolls);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final group in groups) _warscrollGroupCard(context, group),
      ],
    );
  }

  bool _matchesKeyword(JsonMap unit) {
    final keyword = widget.keyword;
    if (keyword == null) return true;
    return (unit['referenceKeywords']?.toString() ?? '')
        .split(',')
        .map((value) => value.trim())
        .contains(keyword);
  }

  Widget _warscrollGroupCard(
    BuildContext context,
    BuilderUnitTypeGroup group,
  ) =>
      Card(
        child: ExpansionTile(
          title: Text(group.title),
          children: [
            for (final unit in group.items) _warscrollTile(context, unit),
          ],
        ),
      );

  Widget _warscrollTile(BuildContext context, JsonMap unit) => ListTile(
        leading: DataThumbnail(imageUrl: dataImageUrl(unit), size: 38),
        title: Text(unit['name']?.toString() ?? 'Warscroll'),
        subtitle: unit['points'] == null ? null : Text('${unit['points']} pts'),
        onTap: () => _openWarscrollDetails(context, widget.api, unit),
      );
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
      body: _publicationList(context),
    );
  }

  Widget _publicationList(BuildContext context) {
    if (publications.isEmpty) {
      return const Center(child: Text('No rules publications are available.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final publication in publications)
          _publicationTile(context, publication),
      ],
    );
  }

  Widget _publicationTile(BuildContext context, JsonMap publication) => Card(
        child: ListTile(
          leading: DataThumbnail(
            imageUrl: publication['backgroundImage']?.toString(),
            size: 42,
          ),
          title: Text(publication['name']?.toString() ?? 'Publication'),
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
      );
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
    return _children.isEmpty ? _rulesPage(title) : _subsectionsPage(title);
  }

  Widget _subsectionsPage(String title) => Scaffold(
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

  Widget _rulesPage(String title) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<JsonMap>(
          future: _rules,
          builder: _rulesContent,
        ),
      );

  Widget _rulesContent(BuildContext context, AsyncSnapshot<JsonMap> snapshot) {
    if (snapshot.hasError) {
      return _RulesErrorView(
        message: snapshot.error.toString(),
        onRetry: _retryRules,
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    return _rulesList(_asMaps(snapshot.data!['rules']));
  }

  Widget _rulesList(List<JsonMap> rules) {
    if (rules.isEmpty) {
      return const Center(child: Text('No rules are available.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final rule in rules) _RuleContainerCard(rule: rule),
      ],
    );
  }

  Future<void> _retryRules() async {
    ApiClient.clearMemoryCache();
    setState(() {
      _rules = widget.api.rulesSection(widget.section['id'].toString());
    });
    await _rules;
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
    if (type == 'ability') {
      return _abilityView();
    }
    if (type == 'battleTactic') return _battleTacticView();
    if (type == 'bullets') return _bulletListView();
    if (type == 'image') return _imageView();
    if (type == 'accordion') return _accordionView();
    return _textView(type);
  }

  Widget _abilityView() => _RuleAbilityView(
        ability: _asMap(component['ability']) ?? const <String, dynamic>{},
      );

  Widget _battleTacticView() {
    final tactic = _asMap(component['battleTactic']);
    if (tactic == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tactic['name']?.toString() ?? 'Battle tactic',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (tactic['rulesText'] is String)
            Text(_plainText(tactic['rulesText'].toString())),
        ],
      ),
    );
  }

  Widget _bulletListView() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final bullet in _asMaps(component['bullets']))
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child:
                    Text('• ${_plainText(bullet['text']?.toString() ?? '')}'),
              ),
          ],
        ),
      );

  Widget _imageView() {
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

  Widget _accordionView() {
    final text = component['textContent']?.toString();
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

  Widget _textView(String? type) {
    final text = component['textContent']?.toString();
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
                  _regimentTile(context, regiment),
              ],
            ),
    );
  }

  Widget _regimentTile(BuildContext context, JsonMap regiment) {
    final units = data.regimentUnits(regiment);
    final image = regiment['image'] ??
        data.warscrollById(
            regiment['regimentOfRenownRowImageWarscrollId'])?['rowImage'];
    return Card(
      child: ListTile(
        leading: DataThumbnail(imageUrl: image?.toString(), size: 40),
        title: Text(regiment['name']?.toString() ?? 'Regiment'),
        subtitle: regiment['regimentOfRenownPointsCost'] == null
            ? null
            : Text('${regiment['regimentOfRenownPointsCost']} pts'),
        onTap: () => _showRegimentDetails(context, regiment, image, units),
      ),
    );
  }

  Future<void> _showRegimentDetails(
    BuildContext context,
    JsonMap regiment,
    Object? image,
    List<JsonMap> units,
  ) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => DataDetailsSheet(
          item: {
            ...regiment,
            if (image != null) 'image': image,
            'units': units,
          },
          onOpenDetails: (unit) => _openWarscrollDetails(context, api, unit),
        ),
      );
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
    final grouped = _groupArmies(armies);
    return Scaffold(
      appBar: AppBar(title: const Text('Armies of Renown')),
      body: armies.isEmpty
          ? const Center(child: Text('No Armies of Renown are available.'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children:
                  _armyGroupWidgets(context, grouped.groups, grouped.names),
            ),
    );
  }

  ({
    Map<String, List<JsonMap>> groups,
    Map<String, String> names,
  }) _groupArmies(List<JsonMap> armies) {
    final groups = <String, List<JsonMap>>{};
    final names = <String, String>{};
    for (final army in armies) {
      final parent = _armyParent(army);
      final groupId = parent?['id']?.toString() ?? 'unassigned';
      groups.putIfAbsent(groupId, () => []).add(army);
      names[groupId] = parent?['name']?.toString() ?? 'Other Factions';
    }
    for (final group in groups.values) {
      group.sort(_compareNames);
    }
    return (groups: groups, names: names);
  }

  JsonMap? _armyParent(JsonMap army) {
    final parentId = army['parentFactionKeywordId'];
    return data.factions
        .where((faction) => faction['id'] == parentId)
        .firstOrNull;
  }

  List<Widget> _armyGroupWidgets(
    BuildContext context,
    Map<String, List<JsonMap>> groups,
    Map<String, String> names,
  ) {
    final groupIds = groups.keys.toList()
      ..sort((first, second) => names[first]!.compareTo(names[second]!));
    return [
      for (final id in groupIds) ...[
        _armyGroupHeading(context, names[id]!),
        for (final army in groups[id]!) _armyCard(context, army),
      ],
    ];
  }

  Widget _armyGroupHeading(BuildContext context, String name) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4, right: 4, bottom: 4),
        child: Text(name, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _armyCard(BuildContext context, JsonMap army) => Card(
        child: ListTile(
          leading: const Icon(Icons.groups_outlined),
          title: Text(army['name']?.toString() ?? 'Army'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _push(
            context,
            _FactionRulesPage(faction: army, data: data, api: api),
          ),
        ),
      );
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
                for (final lore in lores) _manifestationCard(context, lore),
              ],
            ),
    );
  }

  Widget _manifestationCard(BuildContext context, JsonMap lore) {
    final units = data.manifestationsFor(lore);
    return Card(
      child: ExpansionTile(
        title: Text(lore['name']?.toString() ?? 'Lore'),
        subtitle: lore['points'] == null ? null : Text('${lore['points']} pts'),
        children: [
          for (final unit in units) _manifestationTile(context, unit),
        ],
      ),
    );
  }

  Widget _manifestationTile(BuildContext context, JsonMap unit) => ListTile(
        leading: DataThumbnail(imageUrl: dataImageUrl(unit), size: 38),
        title: Text(unit['name']?.toString() ?? 'Manifestation'),
        subtitle: _manifestationSubtitle(unit),
        onTap: () => _openWarscrollDetails(context, api, unit),
      );

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
          for (final alliance in alliances) _allianceCard(context, alliance),
        ],
      ),
    );
  }

  Widget _allianceCard(BuildContext context, JsonMap alliance) {
    final name = _allianceName(alliance);
    final units = _allianceLegends(name);
    return Card(
      child: ExpansionTile(
        title: Text(name),
        children: [
          for (final unit in units) _legendTile(context, unit),
        ],
      ),
    );
  }

  List<JsonMap> _allianceLegends(String allianceName) {
    final units = data.warscrolls
        .where((unit) =>
            unit['isLegends'] == true &&
            (unit['referenceKeywords']?.toString() ?? '')
                .contains(allianceName))
        .toList();
    return units..sort(_compareNames);
  }

  Widget _legendTile(BuildContext context, JsonMap unit) => ListTile(
        leading: DataThumbnail(imageUrl: dataImageUrl(unit), size: 38),
        title: Text(unit['name']?.toString() ?? 'Warscroll'),
        subtitle: unit['points'] == null ? null : Text('${unit['points']} pts'),
        onTap: () => _openWarscrollDetails(context, api, unit),
      );
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
