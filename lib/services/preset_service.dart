/// 本地常吃食物预设方案与 AI 估算知识沉淀缓存服务
library;

import '../data/food_db.dart';
import '../models/preset_food.dart';
import 'storage_service.dart';

class PresetService {
  final StorageService _storage;

  PresetService(this._storage);

  /// 规范化缓存检索 key：小写、去空格、去标点，确保相似描述能命中缓存
  static String normalizeKey(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[\s，,。\.、；;：:\(\)（）\-_~！!？\?]'), '')
        .trim();
  }

  // ---------- 常用预设方案管理 ----------

  /// 获取所有预设方案（按使用频次 useCount 降序，其次按更新时间 updatedAt 降序）
  List<PresetFood> getPresets() {
    final raw = _storage.readMap(StorageService.kUserPresets);
    final list = <PresetFood>[];
    for (final e in raw.values) {
      if (e is Map) {
        list.add(PresetFood.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    list.sort((a, b) {
      final cmp = b.useCount.compareTo(a.useCount);
      if (cmp != 0) return cmp;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// 保存或更新预设方案（按名称去重或匹配相同 id），同时归一化沉淀到用户自定义食物库
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
    final raw = _storage.readMap(StorageService.kUserPresets);
    final now = DateTime.now().millisecondsSinceEpoch;
    final trimmedName = name.trim();

    // 查找是否已存在同名或同 id 的方案
    String targetId = id ?? '';
    int existingCount = 1;
    if (targetId.isEmpty) {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          final item = PresetFood.fromJson(Map<String, dynamic>.from(entry.value as Map));
          if (item.name.trim() == trimmedName) {
            targetId = item.id;
            existingCount = item.useCount + 1;
            break;
          }
        }
      }
    }

    if (targetId.isEmpty) {
      targetId = 'preset_$now';
    }

    final preset = PresetFood(
      id: targetId,
      name: trimmedName,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      unit: unit,
      amount: amount,
      note: note.trim(),
      useCount: existingCount,
      updatedAt: now,
    );

    raw[targetId] = preset.toJson();
    await _storage.writeMap(StorageService.kUserPresets, raw);

    // 核心沉淀：用户采纳常用方案，自动归一化萃取为单位食物存入食物库
    if (syncToFoodDb) {
      try {
        final unitFood = extractUnitFood(
          name: trimmedName,
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
          unit: unit,
        );
        await saveUserFood(unitFood);
      } catch (_) {}
    }

    return preset;
  }

  /// 增加使用计数（当用户选用某个预设时调用，提升其排序）
  Future<void> recordPresetUsed(String id) async {
    final raw = _storage.readMap(StorageService.kUserPresets);
    if (!raw.containsKey(id) || raw[id] is! Map) return;
    final item = PresetFood.fromJson(Map<String, dynamic>.from(raw[id] as Map));
    final updated = item.copyWith(
      useCount: item.useCount + 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    raw[id] = updated.toJson();
    await _storage.writeMap(StorageService.kUserPresets, raw);
  }

  /// 删除预设方案
  Future<void> deletePreset(String id) async {
    final raw = _storage.readMap(StorageService.kUserPresets);
    if (raw.remove(id) != null) {
      await _storage.writeMap(StorageService.kUserPresets, raw);
    }
  }

  // ---------- 用户自定义食物库管理 ----------

  /// 获取用户自定义食物库
  List<FoodItem> getUserFoods() {
    final raw = _storage.readMap(StorageService.kUserFoods);
    final list = <FoodItem>[];
    for (final e in raw.values) {
      if (e is Map) {
        list.add(FoodItem.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return list;
  }

  /// 写入/更新用户自定义食物
  Future<void> saveUserFood(FoodItem food) async {
    final raw = _storage.readMap(StorageService.kUserFoods);
    raw[food.id] = food.toJson();
    await _storage.writeMap(StorageService.kUserFoods, raw);
  }

  /// 删除用户自定义食物
  Future<void> deleteUserFood(String id) async {
    final raw = _storage.readMap(StorageService.kUserFoods);
    if (raw.remove(id) != null) {
      await _storage.writeMap(StorageService.kUserFoods, raw);
    }
  }

  // ---------- AI 知识沉淀与本地缓存 ----------

  /// 获取本地沉淀的 AI 估算结果（若命中则 0 延迟秒出）
  Map<String, dynamic>? getCachedAiEstimate(String desc) {
    final key = normalizeKey(desc);
    if (key.isEmpty) return null;
    final raw = _storage.readMap(StorageService.kAiEstimateCache);
    if (raw.containsKey(key) && raw[key] is Map) {
      return Map<String, dynamic>.from(raw[key] as Map);
    }
    return null;
  }

  /// 缓存 AI 估算结果（沉淀知识，防止重复计算与深度思考耗时）
  Future<void> setCachedAiEstimate(String desc, Map<String, dynamic> result) async {
    final key = normalizeKey(desc);
    if (key.isEmpty) return;
    final raw = _storage.readMap(StorageService.kAiEstimateCache);
    // 只缓存有效结果
    raw[key] = {
      ...result,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    };
    // 控制缓存大小（最多沉淀 500 条）
    if (raw.length > 500) {
      final keys = raw.keys.toList();
      raw.remove(keys.first);
    }
    await _storage.writeMap(StorageService.kAiEstimateCache, raw);
  }
}
