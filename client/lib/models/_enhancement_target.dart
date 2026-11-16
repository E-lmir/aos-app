part of '../army_builder_page.dart';

class _EnhancementTarget {
  const _EnhancementTarget({
    required this.warscroll,
    this.regimentIndex,
    this.unitIndex,
    this.auxiliaryIndex,
  });

  final JsonMap warscroll;
  final int? regimentIndex;
  final int? unitIndex;
  final int? auxiliaryIndex;

  String get label {
    final regiment = regimentIndex;
    if (auxiliaryIndex != null) return 'Auxiliary unit';
    if (unitIndex == null) return 'Regiment ${regiment! + 1} · Hero';
    return 'Regiment ${regiment! + 1}';
  }
}
