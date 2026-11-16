part of '../army_builder_page.dart';

class _BuilderRegiment {
  JsonMap? hero;
  List<_SelectedUnit> units = [];
  List<JsonMap> unitChoices = [];
  JsonMap? artefact;
  JsonMap? heroicTrait;
  final List<_SelectedEnhancement> otherEnhancements = [];
}
