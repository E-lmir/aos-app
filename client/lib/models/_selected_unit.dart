part of '../army_builder_page.dart';

class _SelectedUnit {
  _SelectedUnit(
    this.warscroll, {
    this.onlyOne = false,
    this.optionId,
    this.isRequired = false,
    this.reinforced = false,
  });

  final JsonMap warscroll;
  final bool onlyOne;
  final String? optionId;
  final bool isRequired;
  bool reinforced;
  final List<_SelectedEnhancement> enhancements = [];

  int get points => _points(warscroll) * (reinforced ? 2 : 1);
}
