import 'api_client.dart';
import 'army_list_formatter.dart';
import 'army_list_importer.dart';

class ArmyListText {
  static String formatSavedArmy(JsonMap record) =>
      ArmyListFormatter.formatSavedArmy(record);

  static Future<JsonMap> importText(String text, ApiClient api) =>
      ArmyListImporter(api).importText(text);
}
