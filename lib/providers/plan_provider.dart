/// 计划状态层（对应旧版 plan.js）：reactive 单例 + 持久化 + 提醒联动 + 当日快照同步
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/plan_data.dart';
import '../services/reminder_service.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';
import '../utils/plan_utils.dart';
import 'record_provider.dart';
import 'settings_provider.dart';

class PlanProvider extends ChangeNotifier {
  final StorageService _storage;
  final ReminderService _reminder;
  final SettingsProvider _settings;
  final RecordProvider _records;

  PlanData plan;

  PlanProvider(this._storage, this._reminder, this._settings, this._records)
      : plan = PlanData.empty() {
    _load();
    // F11：启动即确保旧数据已迁移为快照、今天快照与计划一致
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _records.migrateIfNeeded(plan);
    await _records.syncDayEntries(todayStr(), plan);
  }

  /// 计划结构性变更后：仅同步今天的快照（历史快照永不触碰）
  Future<void> _syncToday() => _records.syncDayEntries(todayStr(), plan);

  void _load() {
    final d = _storage.readMap(StorageService.kPlan);
    if (!(d.containsKey('meals') && d['meals'] is List)) {
      plan = PlanData.empty();
      return;
    }
    plan = PlanData.fromJson(d);
    // 一次性迁移：老数据没有「计划开始日」，用最早打卡日期回填（更早的日子没打卡即视为无数据），没有打卡则用今天
    if ((plan.meals.isNotEmpty || plan.exercises.isNotEmpty) && plan.meta.startedAt.isEmpty) {
      plan.meta.startedAt = earliestCheckDate();
      _persist();
    }
  }

  /// 最早打卡日期；无打卡记录返回今天（即首次导入当天）
  String earliestCheckDate() {
    final recs = _storage.readMap(StorageService.kCheckRecords);
    if (recs.isNotEmpty) {
      final dates = recs.keys.where((k) => k.isNotEmpty).toList()..sort();
      if (dates.isNotEmpty) return dates.first;
    }
    return todayStr();
  }

  Future<void> _persist() async {
    await _storage.writeMap(StorageService.kPlan, plan.toJson());
  }

  bool get hasPlan => plan.hasPlan;

  /// 导入（校验已在导入页完成）：增量合并——JSON 含 meals 才合并餐食，含 exercises 才合并运动，
  /// 按 id 去重（相同 id 视为更新该项，新 id 追加到列表末尾）；单独导入其一不影响另一模块；
  /// meta 增量合并（新值存在才覆盖，避免单独导运动时清掉餐食的体重目标）
  Future<void> importPlan(Map<String, dynamic> raw) async {
    final np = normalizePlan(raw);
    // 首次导入记录开始日（= 导入当天）：之前的日子不算「未完成」
    if (plan.meta.startedAt.isEmpty) plan.meta.startedAt = todayStr();
    if (raw['meals'] is List) {
      plan.meals = _mergeById(plan.meals, np.meals);
      _mergeMeta(plan.meta, np.meta);
    }
    if (raw['exercises'] is List) {
      plan.exercises = _mergeById(plan.exercises, np.exercises);
      _mergeMeta(plan.meta, np.meta);
    }
    notifyListeners();
    await _persist();
    await _settings.applyMeta(np.meta);
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }

  /// 增量合并：已有 id 覆盖更新（保留原位置），新 id 追加
  List<T> _mergeById<T>(List<T> oldList, List<T> newList) {
    final map = <String, T>{};
    for (final it in oldList) {
      map[_idOf(it)] = it;
    }
    for (final it in newList) {
      map[_idOf(it)] = it;
    }
    return map.values.toList();
  }

  String _idOf(dynamic it) => it is MealItem ? it.id : (it as ExerciseItem).id;

  /// meta 增量合并：仅用新 meta 中有值的字段覆盖
  void _mergeMeta(PlanMeta target, PlanMeta src) {
    if (src.planName.isNotEmpty) target.planName = src.planName;
    if (src.startDate.isNotEmpty) target.startDate = src.startDate;
    if (src.endDate.isNotEmpty) target.endDate = src.endDate;
    if (src.baseWeight != null) target.baseWeight = src.baseWeight;
    if (src.targetWeight != null) target.targetWeight = src.targetWeight;
    if (src.dailyCalorieTarget != null) target.dailyCalorieTarget = src.dailyCalorieTarget;
    if (src.tdee != null) target.tdee = src.tdee;
  }

  /// 更新单个计划项字段（如提醒开关）
  Future<void> updateItem(String type, String id, Map<String, dynamic> patch) async {
    if (type == 'meal') {
      final it = plan.meals.where((x) => x.id == id).toList();
      if (it.isEmpty) return;
      final m = it.first;
      if (patch['reminder'] is bool) m.reminder = patch['reminder'] as bool;
      if (patch['note'] is String) m.note = patch['note'] as String;
    } else {
      final it = plan.exercises.where((x) => x.id == id).toList();
      if (it.isEmpty) return;
      final e = it.first;
      if (patch['reminder'] is bool) e.reminder = patch['reminder'] as bool;
      if (patch['note'] is String) e.note = patch['note'] as String;
    }
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
  }

  /// 删除单个计划项
  Future<void> removeItem(String type, String id) async {
    if (type == 'meal') {
      plan.meals.removeWhere((x) => x.id == id);
    } else {
      plan.exercises.removeWhere((x) => x.id == id);
    }
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }

  /// 批量删除计划项（多选删除用）
  Future<void> removeItems(String type, List<String> ids) async {
    final set = ids.toSet();
    if (type == 'meal') {
      plan.meals.removeWhere((x) => set.contains(x.id));
    } else {
      plan.exercises.removeWhere((x) => set.contains(x.id));
    }
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }

  /// 分模块清空（打卡与加餐记录保留）；清空后若计划整体为空则重置开始日，下次导入重新记
  Future<void> clearMeals() async {
    plan.meals = [];
    if (plan.exercises.isEmpty) plan.meta.startedAt = '';
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }

  Future<void> clearExercises() async {
    plan.exercises = [];
    if (plan.meals.isEmpty) plan.meta.startedAt = '';
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }

  /// 清除全部计划（仅「清空全部数据」使用）
  Future<void> clearPlan() async {
    plan = PlanData.empty();
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }

  /// 覆盖替换整个计划（历史备份「覆盖导入」使用；data 为导出时的 planData 快照）
  Future<void> replacePlan(PlanData data) async {
    plan = PlanData(
      version: data.version,
      meta: data.meta,
      meals: data.meals,
      exercises: data.exercises,
      deletedIds: data.deletedIds,
    );
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
  }
}
