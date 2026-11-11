import 'dart:collection';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'
    as cache_manager;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'data_image_cache_status.dart';
export 'image_cache_download_result.dart';

import 'data_image_cache_status.dart';
import 'image_cache_download_result.dart';
import 'json_types.dart';

class DataImageCache {
  DataImageCache._();

  static const _cacheKey = 'aos_data_images';
  static const _completeKey = 'all_data_images_cached';
  static const _countKey = 'all_data_images_cached_count';
  static const _versionKey = 'all_data_images_cached_version';
  static const _downloadConcurrency = 4;
  static final _imageField =
      RegExp(r'image|picture|thumbnail', caseSensitive: false);
  static final cache_manager.CacheManager _manager = cache_manager.CacheManager(
    cache_manager.Config(
      _cacheKey,
      stalePeriod: const Duration(days: 3650),
      maxNrOfCacheObjects: 10000,
      fileSystem: _ApplicationSupportFileSystem(),
    ),
  );

  static Future<io.File> fileFor(String url) async {
    final cachedFile = await _manager.getFileFromCache(url);
    if (cachedFile != null) return io.File(cachedFile.file.path);
    final downloadedFile = await _manager.getSingleFile(url);
    return io.File(downloadedFile.path);
  }

  static List<String> imageUrlsFrom(JsonMap database) {
    final data = database['data'];
    if (data is! Map) {
      throw const FormatException('Image catalog has an invalid data section.');
    }
    final urls = <String>{};
    _collectImageUrls(data.values, urls);
    return urls.toList()..sort();
  }

  static void _collectImageUrls(Iterable<Object?> tables, Set<String> urls) {
    for (final table in tables) {
      if (table is! List) {
        throw const FormatException('Image catalog contains an invalid table.');
      }
      for (final row in table) {
        if (row is! Map) {
          throw const FormatException('Image catalog contains an invalid row.');
        }
        _collectRowUrls(row, urls);
      }
    }
  }

  static void _collectRowUrls(Map<dynamic, dynamic> row, Set<String> urls) {
    for (final entry in row.entries) {
      if (!_imageField.hasMatch(entry.key.toString()) ||
          entry.value is! String) {
        continue;
      }
      final value = (entry.value as String).trim();
      final uri = Uri.tryParse(value);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        urls.add(value);
      }
    }
  }

  static Future<ImageCacheDownloadResult> cacheAll(
    List<String> urls, {
    required bool Function() shouldCancel,
    required void Function(int completed, int total) onProgress,
  }) async {
    final pending = Queue<String>.from(urls);
    var completed = 0;
    var failed = 0;
    onProgress(0, urls.length);

    Future<void> downloadWorker() async {
      while (pending.isNotEmpty && !shouldCancel()) {
        final url = pending.removeFirst();
        try {
          final cachedFile = await _manager.getFileFromCache(url);
          if (cachedFile == null) await _manager.getSingleFile(url);
        } on Object {
          failed++;
        }
        completed++;
        if (completed % 10 == 0 || completed == urls.length) {
          onProgress(completed, urls.length);
        }
      }
    }

    final workers = math.min(_downloadConcurrency, urls.length);
    await Future.wait(List.generate(workers, (_) => downloadWorker()));
    return _finishDownload(
      urls.length,
      completed,
      failed,
      shouldCancel,
      onProgress,
    );
  }

  static ImageCacheDownloadResult _finishDownload(
    int total,
    int completed,
    int failed,
    bool Function() shouldCancel,
    void Function(int completed, int total) onProgress,
  ) {
    onProgress(completed, total);
    return ImageCacheDownloadResult(
      total: total,
      completed: completed,
      failed: failed,
      cancelled: shouldCancel() && completed < total,
    );
  }

  static Future<DataImageCacheStatus> status() async {
    final preferences = await SharedPreferences.getInstance();
    return DataImageCacheStatus(
      isComplete: preferences.getBool(_completeKey) ?? false,
      imageCount: preferences.getInt(_countKey) ?? 0,
      dataVersion: preferences.getInt(_versionKey),
    );
  }

  static Future<void> markComplete({
    required int imageCount,
    required int? dataVersion,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setInt(_countKey, imageCount)) {
      throw StateError('Could not save the cached image count.');
    }
    if (dataVersion != null &&
        !await preferences.setInt(_versionKey, dataVersion)) {
      throw StateError('Could not save the image catalog version.');
    }
    if (dataVersion == null) await preferences.remove(_versionKey);
    if (!await preferences.setBool(_completeKey, true)) {
      throw StateError('Could not save the image cache status.');
    }
  }

  static Future<void> clearAll() async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setBool(_completeKey, false)) {
      throw StateError('Could not update the image cache status.');
    }
    await preferences.remove(_countKey);
    await preferences.remove(_versionKey);
    await _manager.emptyCache();
  }
}

class CachedDataImage extends StatefulWidget {
  const CachedDataImage({
    super.key,
    required this.imageUrl,
    required this.placeholder,
    required this.errorWidget,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
  final Widget placeholder;
  final Widget errorWidget;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<CachedDataImage> createState() => _CachedDataImageState();
}

class _CachedDataImageState extends State<CachedDataImage> {
  late Future<io.File> _file;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void didUpdateWidget(covariant CachedDataImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _loadFile();
  }

  void _loadFile() {
    _file = DataImageCache.fileFor(widget.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<io.File>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.placeholder;
        }
        final file = snapshot.data;
        if (snapshot.hasError) return widget.errorWidget;
        if (file == null) return widget.placeholder;
        return Image.file(
          file,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) => widget.errorWidget,
        );
      },
    );
  }
}

class _ApplicationSupportFileSystem implements cache_manager.FileSystem {
  Future<file.Directory>? _directory;

  Future<file.Directory> get _cacheDirectory =>
      _directory ??= _createDirectory();

  Future<file.Directory> _createDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final path = [
      supportDirectory.path,
      'aos_data_images',
    ].join(io.Platform.pathSeparator);
    const localFileSystem = LocalFileSystem();
    final directory = localFileSystem.directory(path);
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<file.File> createFile(String name) async {
    return (await _cacheDirectory).childFile(name);
  }
}
