class ImageCacheDownloadResult {
  const ImageCacheDownloadResult({
    required this.total,
    required this.completed,
    required this.failed,
    required this.cancelled,
  });

  final int total;
  final int completed;
  final int failed;
  final bool cancelled;
}
