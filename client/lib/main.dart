import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api_client.dart';
import 'army_builder_page.dart';
import 'army_list_text.dart';
import 'data_image_cache.dart';
import 'offline_database.dart';
import 'rules_page.dart';
import 'saved_army_store.dart';
import 'save_army_name_dialog.dart';

void main() {
  runApp(const AosApp());
}

class AosApp extends StatelessWidget {
  const AosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Age of Sigmar',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7c2638)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  int _selectedIndex = 0;
  JsonMap? _selectedArmy;

  @override
  void initState() {
    super.initState();
    unawaited(_api.checkApiAvailability());
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  void _openArmy(JsonMap army) {
    setState(() {
      _selectedArmy = army;
      _selectedIndex = 0;
    });
  }

  void _closeArmy() {
    setState(() {
      _selectedArmy = null;
      _selectedIndex = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _selectedArmy == null || _selectedIndex != 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedArmy != null && _selectedIndex == 0) {
          _closeArmy();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            ArmyBuilderPage(
              key: ValueKey(_selectedArmy?['id'] ?? 'new-builder'),
              savedArmy: _selectedArmy,
              apiClient: _api,
              onClose: _selectedArmy == null ? null : _closeArmy,
            ),
            RulesPage(apiClient: _api),
            SavedArmiesPage(
              isActive: _selectedIndex == 2,
              onOpen: _openArmy,
              apiClient: _api,
            ),
            OfflineSettingsPage(apiClient: _api),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield),
              label: 'Builder',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Rules',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks),
              label: 'Armies',
            ),
            NavigationDestination(
              icon: Icon(Icons.offline_bolt_outlined),
              selectedIcon: Icon(Icons.offline_bolt),
              label: 'Offline',
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineSettingsPage extends StatefulWidget {
  const OfflineSettingsPage({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<OfflineSettingsPage> createState() => _OfflineSettingsPageState();
}

class _OfflineSettingsPageState extends State<OfflineSettingsPage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _store = OfflineDatabaseStore();
  bool? _enabled;
  bool _working = false;
  int? _dataVersion;
  String? _errorMessage;
  bool _imagesCached = false;
  bool _imageStatusLoading = true;
  bool _imageDownloadWorking = false;
  bool _cancelImageDownload = false;
  int _cachedImageCount = 0;
  int _imageProgress = 0;
  int _imageTotal = 0;
  String? _imageErrorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _load();
    await _loadImageCacheStatus();
  }

  Future<void> _loadImageCacheStatus() async {
    try {
      final status = await DataImageCache.status();
      final isCurrent = !status.isComplete ||
          _dataVersion == null ||
          status.dataVersion == null ||
          status.dataVersion == _dataVersion;
      if (!mounted) return;
      setState(() {
        _imagesCached = status.isComplete && isCurrent;
        _cachedImageCount = status.imageCount;
        _imageStatusLoading = false;
        _imageErrorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _imageStatusLoading = false;
        _imageErrorMessage = 'Could not read the image cache status: $error';
      });
    }
  }

  Future<void> _load() async {
    try {
      final enabled = await _store.isEnabled();
      if (!enabled) {
        if (!mounted) return;
        setState(() {
          _enabled = false;
          _dataVersion = null;
        });
        return;
      }

      int? cachedVersion;
      Object? cacheReadError;
      try {
        cachedVersion = await _store.cachedDataVersion();
      } catch (error) {
        cacheReadError = error;
      }
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _dataVersion = cachedVersion;
        _working = true;
      });

      try {
        final metadata = await _api.metadata();
        final remoteVersion = metadata['data_version'];
        if (remoteVersion is! int) {
          throw const FormatException('API returned an invalid data version.');
        }
        if (remoteVersion == cachedVersion) return;

        final database = await _api.downloadDatabase();
        await _store.cacheAndEnable(database);
        ApiClient.clearMemoryCache();
        if (mounted) {
          setState(() {
            _dataVersion = remoteVersion;
            _errorMessage = null;
          });
        }
      } catch (error) {
        final cacheNote = cacheReadError == null
            ? ''
            : ' The existing offline database could not be read: $cacheReadError';
        _showMessage('Offline database update failed: $error.$cacheNote');
      } finally {
        if (mounted) setState(() => _working = false);
      }
    } catch (error) {
      _showMessage(error.toString());
      if (mounted) setState(() => _enabled = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _working = true);
    try {
      if (enabled) {
        final database = await _api.downloadDatabase();
        await _store.cacheAndEnable(database);
        ApiClient.clearMemoryCache();
        _dataVersion = database['metadata'] is Map<String, dynamic>
            ? (database['metadata'] as Map<String, dynamic>)['data_version']
                as int?
            : null;
      } else {
        await _store.disableAndRemove();
        ApiClient.clearMemoryCache();
        _dataVersion = null;
      }
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _errorMessage = null;
        });
      }
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _working = false);
        await _loadImageCacheStatus();
      }
    }
  }

  Future<void> _setImagesCached(bool enabled) async {
    setState(() {
      _imageDownloadWorking = true;
      _imageErrorMessage = null;
      _cancelImageDownload = false;
      if (enabled) {
        _imagesCached = true;
        _imageProgress = 0;
        _imageTotal = 0;
      }
    });

    try {
      if (!enabled) {
        await DataImageCache.clearAll();
        if (mounted) {
          setState(() {
            _imagesCached = false;
            _cachedImageCount = 0;
            _imageProgress = 0;
            _imageTotal = 0;
          });
        }
        return;
      }

      final database =
          await _store.readIfEnabled() ?? await _api.downloadDatabase();
      final urls = DataImageCache.imageUrlsFrom(database);
      if (urls.isEmpty) {
        throw StateError('No image URLs were found in the database.');
      }
      final metadata = database['metadata'];
      final dataVersion = metadata is Map && metadata['data_version'] is int
          ? metadata['data_version'] as int
          : null;
      if (mounted) {
        setState(() {
          _imageTotal = urls.length;
          _imageProgress = 0;
        });
      }

      final result = await DataImageCache.cacheAll(
        urls,
        shouldCancel: () => _cancelImageDownload,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _imageProgress = completed;
            _imageTotal = total;
          });
        },
      );
      if (result.cancelled) {
        if (mounted) {
          setState(() {
            _imagesCached = false;
            _imageErrorMessage =
                'Image download cancelled after processing '
                '${result.completed} of ${result.total} images. '
                'Cached files are kept, so you can resume later.';
          });
        }
        return;
      }
      if (result.failed > 0) {
        if (mounted) {
          setState(() {
            _imagesCached = false;
            _imageErrorMessage =
                'Could not download ${result.failed} of ${result.total} '
                'images. Check the connection and try again.';
          });
        }
        return;
      }

      await DataImageCache.markComplete(
        imageCount: result.total,
        dataVersion: dataVersion,
      );
      if (mounted) {
        setState(() {
          _imagesCached = true;
          _cachedImageCount = result.total;
          _imageErrorMessage = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _imagesCached = false;
          _imageErrorMessage = 'Image download failed: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _imageDownloadWorking = false;
          _cancelImageDownload = false;
        });
      }
    }
  }

  void _cancelImageDownloadNow() {
    setState(() => _cancelImageDownload = true);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline data')),
      body: enabled == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Download the entire database'),
                  subtitle: Text(
                    enabled
                        ? 'Stored on this device · version ${_dataVersion ?? 'unknown'}'
                        : 'Downloads rules and army-builder data for offline use.',
                  ),
                  value: enabled,
                  onChanged: _working || _imageDownloadWorking
                      ? null
                      : _setEnabled,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Download all images'),
                  subtitle: Text(
                    _imageStatusLoading
                        ? 'Checking image cache status…'
                        : _imagesCached
                            ? '$_cachedImageCount images stored on this device. '
                                'Switch off to remove them.'
                            : 'Downloads catalog images for offline use. '
                                'Uses network data and device storage.',
                  ),
                  value: _imagesCached,
                  onChanged: _imageStatusLoading ||
                          _working ||
                          _imageDownloadWorking
                      ? null
                      : _setImagesCached,
                ),
                if (_imageDownloadWorking) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _imageTotal == 0
                        ? null
                        : _imageProgress / _imageTotal,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _imageTotal == 0
                              ? 'Preparing image download…'
                              : 'Processed $_imageProgress of '
                                  '$_imageTotal images',
                        ),
                      ),
                      TextButton(
                        onPressed: _cancelImageDownload
                            ? null
                            : _cancelImageDownloadNow,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
                if (_imageErrorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _imageErrorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_working) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Downloading or removing offline data…'),
                ],
                const SizedBox(height: 16),
                const Text(
                  'When enabled, the builder uses this database if the API is '
                  'unavailable. The download can use significant storage and '
                  'network data.',
                ),
              ],
            ),
    );
  }
}

class SavedArmiesPage extends StatefulWidget {
  const SavedArmiesPage({
    super.key,
    this.isActive = true,
    this.onOpen,
    this.apiClient,
  });

  final bool isActive;
  final ValueChanged<JsonMap>? onOpen;
  final ApiClient? apiClient;

  @override
  State<SavedArmiesPage> createState() => _SavedArmiesPageState();
}

class _SavedArmiesPageState extends State<SavedArmiesPage> {
  final _store = SavedArmyStore();
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  List<JsonMap> _armies = [];
  bool _loading = true;
  bool _syncing = false;
  bool _pasting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant SavedArmiesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    if (widget.apiClient == null) _api.close();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final armies = await _store.load();
      if (!mounted) return;
      setState(() {
        _armies = armies;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final count = await _store.sync(_api);
      await _reload();
      _showMessage('Synced $count armies for this device.');
    } catch (error) {
      _showMessage('Sync failed: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _delete(JsonMap army) async {
    final id = army['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved army?'),
        content: Text(army['name']?.toString() ?? 'Army'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _store.delete(id);
      await _reload();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  Future<void> _copyArmy(JsonMap army) async {
    try {
      await Clipboard.setData(
        ClipboardData(text: ArmyListText.formatSavedArmy(army)),
      );
      _showMessage('Army list copied.');
    } catch (error) {
      _showMessage('Could not copy army: $error');
    }
  }

  Future<void> _pasteArmy() async {
    if (_pasting) return;
    setState(() => _pasting = true);
    try {
      final text =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
      if (text == null || text.isEmpty) {
        throw const FormatException('The clipboard does not contain a list.');
      }

      final army = await ArmyListText.importText(text, _api);
      if (!mounted) return;
      final factionName = army['faction_name']?.toString() ?? 'Army';
      final name = await showDialog<String>(
        context: context,
        builder: (context) => SaveArmyNameDialog(
          title: 'Import army list',
          initialName: '$factionName list',
        ),
      );
      if (!mounted || name == null) return;
      await _store.save(name: name, army: army);

      await _reload();
      _showMessage('Army list imported.');
    } catch (error) {
      _showMessage('Could not import army list: $error');
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _armySummary(JsonMap record) {
    final army = record['army'];
    if (army is! Map<String, dynamic>) return 'Saved army';
    final faction = army['faction'];
    final factionName = army['faction_name'] ??
        (faction is Map<String, dynamic> ? faction['name'] : null) ??
        'Unknown faction';
    return '$factionName · ${army['total_points'] ?? 0} pts';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved armies'),
        actions: [
          IconButton(
            tooltip: 'Paste army list',
            onPressed: _pasting ? null : _pasteArmy,
            icon: _pasting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.content_paste),
          ),
          IconButton(
            tooltip: 'Sync with API',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _reload)
              : _armies.isEmpty
                  ? const Center(child: Text('No saved armies on this device.'))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final army in _armies)
                          Card(
                            child: ListTile(
                              title: Text(army['name']?.toString() ?? 'Army'),
                              subtitle: Text(_armySummary(army)),
                              onTap: () {
                                final onOpen = widget.onOpen;
                                if (onOpen != null) {
                                  onOpen(army);
                                  return;
                                }
                                Navigator.of(context)
                                    .push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ArmyBuilderPage(
                                          savedArmy: army,
                                        ),
                                      ),
                                    )
                                    .then((_) => _reload());
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Copy army list',
                                    onPressed: () => _copyArmy(army),
                                    icon: const Icon(Icons.copy_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete army',
                                    onPressed: () => _delete(army),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
