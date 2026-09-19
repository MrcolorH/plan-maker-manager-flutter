/// 常用食物预设方案状态管理
library;

import 'package:flutter/foundation.dart';

import '../models/preset_food.dart';
import '../services/preset_service.dart';
import '../services/storage_service.dart';

class PresetProvider extends ChangeNotifier {
  final PresetService service;
  List<PresetFood> _presets = const [];

  PresetProvider([PresetService? s])
      : service = s ?? PresetService(StorageService.instance) {
    refresh();
  }

  List<PresetFood> get presets => _presets;

  void refresh() {
    _presets = service.getPresets();
    notifyListeners();
  }

  Future<PresetFood> savePreset({
    String? id,
    required String name,
    required int calories,
    int? protein,
    int? carbs,
    int? fat,
    String note = '',
  }) async {
    final res = await service.savePreset(
      id: id,
      name: name,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      note: note,
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
}
