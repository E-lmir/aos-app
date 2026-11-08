class CommunityUnit {
  CommunityUnit({
    required this.name,
    required this.count,
    required this.reinforcedSuffix,
    List<String>? enhancements,
  }) : enhancements = enhancements ?? [];

  final String name;
  final int? count;
  final bool reinforcedSuffix;
  final List<String> enhancements;
}
