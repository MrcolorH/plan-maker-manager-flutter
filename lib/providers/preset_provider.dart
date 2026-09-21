/// 常用食物预设方案状态管理
library;

import 'package:flutter/foundation.dart';

import '../data/food_db.dart';
import '../models/preset_food.dart';
import '../services/preset_service.dart';
import '../services/storage_service.dart';

class PresetProvider extends ChangeNotifier {
  final PresetService service;
  List<PresetFood> _presets = const [];
  List<FoodItem> _userFoods = const [];

  PresetProvider([PresetService? s])
      : service = s ?? PresetService(StorageService.instance) {
    refresh();
  }

  List<PresetFood> get presets => _presets;
  List<FoodItem> get userFoods => _userFoods;

  void refresh() {
    _presets = service.getPresets();
    _userFoods = service.getUserFoods();
    notifyListeners();
  }

  Future<PresetFood> savePreset({
    String? id,
    required String name,
    required int calories,
    int? protein,
    int? carbs,
    int? fat,
    String unit = '份',
    double amount = 1.0,
    String note = '',
    bool syncToFoodDb = true,
  }) async {
    final res = await service.savePreset(
      id: id,
      name: name,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      unit: unit,
      amount: amount,
      note: note,
      syncToFoodDb: syncToFoodDb,
    );
    refresh();
    return res;
  }

  Future<void> recordUsed(String id) async {
    await service.recordPresetUsed(id);
    refresh();
  }

  Future<void> deletePreset(String id) async {
    await service.deletePreset(id);
    refresh();
  }

  Future<void> saveUserFood(FoodItem food) async {
    await service.saveUserFood(food);
    refresh();
  }

  Future<void> deleteUserFood(String id) async {
    await service.deleteUserFood(id);
    refresh();
  }
}

