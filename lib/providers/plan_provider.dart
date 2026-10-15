/// 计划状态层（对应旧版 plan.js）：reactive 单例 + 持久化 + 提醒联动 + 当日快照同步
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/plan_data.dart';
import '../models/records.dart';
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
    if (src.targetProtein != null) target.targetProtein = src.targetProtein;
    if (src.targetCarbs != null) target.targetCarbs = src.targetCarbs;
    if (src.targetFat != null) target.targetFat = src.targetFat;
  }

  /// 更新计划的 meta 目标（如设置页重算目标/身高体重目标同步）
  Future<void> updateMeta({
    int? dailyCalorieTarget,
    int? tdee,
    double? baseWeight,
    int? targetProtein,
    int? targetCarbs,
    int? targetFat,
  }) async {
    var dirty = false;
    if (dailyCalorieTarget != null && dailyCalorieTarget > 0) {
      plan.meta.dailyCalorieTarget = dailyCalorieTarget.toDouble();
      dirty = true;
    }
    if (tdee != null && tdee > 0) {
      plan.meta.tdee = tdee.toDouble();
      dirty = true;
    }
    if (baseWeight != null && baseWeight > 0) {
      plan.meta.baseWeight = baseWeight;
      dirty = true;
    }
    if (targetProtein != null && targetProtein > 0) {
      plan.meta.targetProtein = targetProtein;
      dirty = true;
    }
    if (targetCarbs != null && targetCarbs > 0) {
      plan.meta.targetCarbs = targetCarbs;
      dirty = true;
    }
    if (targetFat != null && targetFat > 0) {
      plan.meta.targetFat = targetFat;
      dirty = true;
    }
    if (dirty) {
      notifyListeners();
      await _persist();
    }
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

  /// 当日快照修改反向同步回长期计划模板（用户勾选「同步更新回长期计划」）
  Future<void> syncMealItemFromSnapshot({
    required String mealId,
    required String newName,
    required int? newCalories,
    int? protein,
    int? carbs,
    int? fat,
    String? note,
  }) async {
    final i = plan.meals.indexWhere((x) => x.id == mealId);
    if (i < 0) return;
    final old = plan.meals[i];
    final updated = MealItem(
      id: old.id,
      type: old.type,
      name: newName,
      time: old.time,
      calories: newCalories,
      protein: protein ?? old.protein,
      carbs: carbs ?? old.carbs,
      fat: fat ?? old.fat,
      days: old.days,
      reminder: old.reminder,
      note: note ?? old.note,
      details: old.details,
      steps: old.steps,
      dates: old.dates,
      startDate: old.startDate,
      endDate: old.endDate,
    );
    plan.meals[i] = updated;
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
  }

  /// 整项替换（导入预览/详情页「编辑」落盘用）：按 id 定位原位替换；
  /// 名称/时间/内容等变化会影响当日快照与提醒，故联动重调度 + 同步今天
  Future<void> replaceItem(String type, Object item) async {
    if (type == 'meal') {
      if (item is! MealItem) return;
      final i = plan.meals.indexWhere((x) => x.id == item.id);
      if (i < 0) return;
      plan.meals[i] = item;
    } else if (type == 'exercise') {
      if (item is! ExerciseItem) return;
      final i = plan.exercises.indexWhere((x) => x.id == item.id);
      if (i < 0) return;
      plan.exercises[i] = item;
    } else {
      return;
    }
    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
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

  /// 检测同一餐次类型下，选中的执行周期是否与已有日常计划存在星期冲突
  List<MealPlanConflict> checkMealConflicts({
    required String type, // 'breakfast' | 'lunch' | 'dinner'
    required List<int> days, // 用户选中的周几 (1..7)
  }) {
    final conflicts = <MealPlanConflict>[];
    final targetMeals = plan.meals.where((m) => m.type == type).toList();
    for (final m in targetMeals) {
      final oldDays = m.days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : m.days;
      final overlap = oldDays.where((d) => days.contains(d)).toList()..sort();
      if (overlap.isNotEmpty) {
        conflicts.add(MealPlanConflict(existingMeal: m, conflictDays: overlap));
      }
    }
    return conflicts;
  }

  /// 将当日某餐条目一键转为长期日常计划
  /// 如果存在冲突项，会对冲突项执行裁剪（移除冲突周几）；若冲突项执行天数完全被覆盖，则彻底删除旧项
  Future<MealItem> convertSnapshotToPlan({
    required String type, // 'breakfast' | 'lunch' | 'dinner'
    required String name,
    required String time,
    required int? calories,
    int? protein,
    int? carbs,
    int? fat,
    required List<int> days,
    bool reminder = true,
    String note = '',
    String? sourceSnapshotDate,
    String? sourceSnapshotEntryId,
  }) async {
    final selectedDays = [...days]..sort();

    // 1. 查找冲突项并执行覆盖裁剪
    final conflicts = checkMealConflicts(type: type, days: selectedDays);
    for (final c in conflicts) {
      final old = c.existingMeal;
      final oldDays = old.days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : old.days;
      final remainDays = oldDays.where((d) => !selectedDays.contains(d)).toList()..sort();
      if (remainDays.isEmpty) {
        plan.meals.removeWhere((m) => m.id == old.id);
      } else {
        final idx = plan.meals.indexWhere((m) => m.id == old.id);
        if (idx >= 0) {
          plan.meals[idx] = MealItem(
            id: old.id,
            type: old.type,
            name: old.name,
            time: old.time,
            calories: old.calories,
            protein: old.protein,
            carbs: old.carbs,
            fat: old.fat,
            days: remainDays.length == 7 ? [] : remainDays,
            reminder: old.reminder,
            note: old.note,
            details: old.details,
            steps: old.steps,
            dates: old.dates,
            startDate: old.startDate,
            endDate: old.endDate,
          );
        }
      }
    }

    // 2. 创建新计划项
    final newMeal = MealItem(
      id: genId('m'),
      type: type,
      name: name,
      time: time,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      days: selectedDays.length == 7 ? [] : selectedDays,
      reminder: reminder,
      note: note,
    );
    plan.meals.add(newMeal);

    // 3. 首次添加计划初始化 startedAt
    if (plan.meta.startedAt.isEmpty) {
      plan.meta.startedAt = todayStr();
    }

    // 4. 源快照就地原子升级绑定：在触发 _syncToday 前，必须把当天的该快照条目直接就地升级关联为 newMeal，
    // 这样当 _syncToday 运行时，就绝不会把 newMeal 当成未实例化的新计划而追加一条重复快照！
    if (sourceSnapshotDate != null &&
        sourceSnapshotEntryId != null &&
        sourceSnapshotDate.isNotEmpty &&
        sourceSnapshotEntryId.isNotEmpty) {
      final dayList = _records.getDayEntries(sourceSnapshotDate);
      final entryIdx = dayList.indexWhere((e) => e.id == sourceSnapshotEntryId);
      if (entryIdx >= 0) {
        final oldEntry = dayList[entryIdx];
        final oldCheckKey = _records.checkKeyOf(oldEntry);

        final updated = DayEntry(
          id: oldEntry.id,
          kind: 'meal',
          slot: type,
          time: time.isNotEmpty ? time : oldEntry.time,
          content: name,
          calories: calories,
          protein: protein ?? oldEntry.protein,
          carbs: carbs ?? oldEntry.carbs,
          fat: fat ?? oldEntry.fat,
          note: note.isNotEmpty ? note : oldEntry.note,
          source: 'plan',
          planItemId: newMeal.id,
          detached: false,
          caloriesDirty: oldEntry.caloriesDirty,
          detail: oldEntry.detail,
          items: oldEntry.items,
        );
        await _records.updateDayEntry(sourceSnapshotDate, updated);

        // 平滑迁移打卡状态（若原条目已有打卡，迁移到 meal:${newMeal.id}）
        final newCheckKey = _records.checkKeyOf(updated);
        await _records.migrateEntryCheck(
          date: sourceSnapshotDate,
          oldCheckKey: oldCheckKey,
          newCheckKey: newCheckKey,
        );
      }
    }

    notifyListeners();
    await _persist();
    await _reminder.fullReschedule(plan, _settings.settings);
    await _syncToday();
    return newMeal;
  }
}

/// 餐食计划冲突描述
class MealPlanConflict {
  final MealItem existingMeal;
  final List<int> conflictDays; // 冲突的星期数字 1=周一...7=周日
  const MealPlanConflict({required this.existingMeal, required this.conflictDays});
}
