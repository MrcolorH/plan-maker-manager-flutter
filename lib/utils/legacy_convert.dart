/// 旧格式数据 → 当日条目快照 的转换核心（F11 §6.1）
/// 两个触发点共用同一套逻辑：①升级首启迁移本机存量 ②导入 v1 老备份（管线内直接转换）
/// 规则详见 spec/day-snapshot-design.md §6：
///  - 计划餐 → kind=meal 快照（mealAdjust 覆盖值→条目热量/备注、caloriesDirty=true）
///  - 计划运动 → kind=exercise 快照（消耗=计划 caloriesBurned）
///  - tempTasks + extraFoods → 计划外快照（source 保留、detached=true）
///  - 打卡状态不转换（checkRecords 在 v1/v2 中同构，仍为打卡唯一事实源）
///  - 只在有记录的历史日期生成；同 date 内按 time 升序
library;

import '../models/plan_data.dart';
import '../models/records.dart';
import 'date_utils.dart';
import 'plan_utils.dart';

/// 同 kind 内按 time 升序；同 time 保持追加顺序
void sortDayEntries(List<DayEntry> list) {
  list.sort((a, b) {
    final ta = timeToMin(a.time);
    final tb = timeToMin(b.time);
    return ta == tb ? a.id.compareTo(b.id) : ta.compareTo(tb);
  });
}

/// 旧格式 → 快照（转换核心）
/// [plan] 投影源：启动迁移传本机 plan；v1 备份导入传备份内 planData
/// [checkRecords] 仅用于遍历日期集合（打卡状态本身不转换）；可为空
Map<String, List<DayEntry>> convertLegacyToEntries({
  required PlanData plan,
  Map<String, dynamic>? checkRecords,
  Map<String, dynamic>? mealAdjust,
  Map<String, dynamic>? tempTasks,
  Map<String, dynamic>? extraFoods,
}) {
  final out = <String, List<DayEntry>>{};
  final dates = <String>{};
  checkRecords?.forEach((d, _) => dates.add(d.toString()));
  mealAdjust?.forEach((d, _) => dates.add(d.toString()));
  tempTasks?.forEach((d, _) => dates.add(d.toString()));
  extraFoods?.forEach((d, _) => dates.add(d.toString()));
  final sorted = dates.toList()..sort();
  for (final date in sorted) {
    if (!isValidDateStr(date)) continue;
    final entries = <DayEntry>[];
    final adjusts = (mealAdjust?[date] is Map) ? Map<String, dynamic>.from(mealAdjust![date] as Map) : <String, dynamic>{};

    // ① 计划餐 → 快照（含未打卡项，保留 mealAdjust 覆盖值）
    for (final m in getTasksForDate(plan, date).meals) {
      final adj = adjusts['meal:${m.id}'];
      final overridden = adj is Map;
      final cal = (overridden && adj['calories'] is num) ? (adj['calories'] as num).round() : m.calories;
      final note = (overridden && adj['note'] is String) ? adj['note'] as String : '';
      entries.add(DayEntry(
        id: m.id,
        kind: 'meal',
        slot: m.type,
        time: m.time,
        content: m.name,
        calories: cal,
        note: note,
        source: 'plan',
        planItemId: m.id,
        detached: false,
        caloriesDirty: overridden,
      ));
    }

    // ② 计划运动 → 快照
    for (final e in getTasksForDate(plan, date).exercises) {
      entries.add(DayEntry(
        id: e.id,
        kind: 'exercise',
        slot: '',
        time: e.time,
        content: e.name,
        calories: e.caloriesBurned,
        note: '',
        source: 'plan',
        planItemId: e.id,
        detached: false,
        caloriesDirty: false,
      ));
    }

    // ③ tempTasks + extraFoods → 计划外快照
    final temps = <TempTask>[];
    final rawTemps = tempTasks?[date];
    if (rawTemps is List) {
      for (final t in rawTemps) {
        if (t is Map) {
          try {
            temps.add(TempTask.fromJson(Map<String, dynamic>.from(t)));
          } catch (_) {}
        }
      }
    }
    final rawFoods = extraFoods?[date];
    if (rawFoods is List) {
      for (final f in rawFoods) {
        if (f is! Map) continue;
        final name = f['name'];
        final at = f['at'];
        final cal = f['calories'];
        temps.add(TempTask(
          id: f['id'] is String ? f['id'] as String : genId('t'),
          type: 'snack',
          name: name is String ? name : '加餐',
          time: at is String && at.isNotEmpty ? at : '12:00',
          calories: cal is num ? cal.round() : 0,
          source: f['source'] is String ? f['source'] as String : 'manual',
        ));
      }
    }
    for (final t in temps) {
      if (t.id.isEmpty) continue;
      entries.add(DayEntry(
        id: t.id,
        kind: t.isExercise ? 'exercise' : 'meal',
        slot: t.isExercise ? '' : 'snack',
        time: t.time.isNotEmpty ? t.time : '12:00',
        content: t.name,
        calories: t.calories,
        note: '',
        source: t.source,
        planItemId: '',
        detached: true,
        caloriesDirty: true,
      ));
    }

    if (entries.isNotEmpty) {
      sortDayEntries(entries);
      out[date] = entries;
    }
  }
  return out;
}
