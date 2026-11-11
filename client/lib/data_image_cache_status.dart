class DataImageCacheStatus {
  const DataImageCacheStatus({
    required this.isComplete,
    required this.imageCount,
    required this.dataVersion,
  });

  final bool isComplete;
  final int imageCount;
  final int? dataVersion;
}
