import 'package:flutter/foundation.dart';
import '../../../data/db/database_helper.dart';

class ItemDescriptionNotifier extends ChangeNotifier {
  List<Map<String, dynamic>> items = [];

  Future<void> load() async {
    items = await DatabaseHelper.instance.getItemDescriptions();
    notifyListeners();
  }

  Future<void> add(String text) async {
    if (text.trim().isEmpty) return;
    await DatabaseHelper.instance.insertItemDescription(text.trim());
    await load();
  }

  Future<void> delete(int id) async {
    await DatabaseHelper.instance.deleteItemDescription(id);
    await load();
  }
}
