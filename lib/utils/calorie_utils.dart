/// 热量缺口计算与统计聚合（与旧版 uni-app calorie.js 1:1 对齐）
/// 口径：当日消耗 = 基础消耗（BMR × 生活系数，不含刻意运动）+ 当日实际运动（打卡的计划运动 + 临时/补录运动）
/// 已摄入 = 已打卡计划餐(实际值) + 临时加餐(全计) + 旧加餐记录(兼容)
/// F11 快照路径：历史固化——该日已有当日条目快照（dayEntries）时只读快照统计，
/// 与当前计划无关（删除/清空/覆盖计划不影响历史）；无快照的日期走旧口径 fallback
library;

import 'dart:math';

import '../models/onboarding.dart';
import '../models/plan_data.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../models/weight.dart';
import 'date_utils.dart';
import 'plan_utils.dart';

/// 生活基础系数：日常起居消耗（不含刻意运动；运动打卡/补录后另计入）
const double kLifeFactor = 1.2;

num _sum(Iterable<num?> arr) => arr.fold<num>(0, (a, b) => a + (b ?? 0));

/// 快照条目打卡键（与 RecordProvider.checkKeyOf 同构）：计划沿用 meal:/exercise:，计划外 temp:
String entryCheckKey(DayEntry e) =>
    e.isPlan ? '${e.kind == 'meal' ? 'meal' : 'exercise'}:${e.planItemId}' : 'temp:${e.id}';

/// 某天计划任务进度（完成度口径：只统计计划来源条目，含脱钩）
/// 快照日走快照；无快照日按当前计划投影（fallback，用于未来/未生成快照的天）
(int, int) taskProgress(PlanData plan, RecordStore records, String dateStr) {
  final entries = records.dayEntries[dateStr];
  if (entries != null) {
    final planEs = entries.where((e) => e.isPlan).toList();
    final rec = records.checkRecords[dateStr] ?? {};
    final done = planEs.where((e) => rec.containsKey(entryCheckKey(e))).length;
    return (planEs.length, done);
  }
  final tasks = getTasksForDate(plan, dateStr);
  final rec = records.checkRecords[dateStr] ?? {};
  final done = tasks.meals.where((m) => rec.containsKey('meal:${m.id}')).length +
      tasks.exercises.where((e) => rec.containsKey('exercise:${e.id}')).length;
  return (tasks.total, done);
}

/// 基础消耗（不含运动）：优先用已存的 BMR × 生活系数；未存 BMR 时沿用 tdee（旧数据兼容）
/// F10 后仅作「沿用链兜底」与基线固化取值使用；逐日统计请用 [baseBurnForDate]
int baseBurn(AppSettings settings) {
  final bmr = settings.bmr;
  if (bmr > 0) return (bmr * kLifeFactor).round();
  return settings.tdee;
}

/// 按日基础消耗（F10 沿用链，历史固化）：
/// ① 最近 ≤date 且 bmr>0 的体重记录 → bmr×1.2；记录 bmr==0（录入时基础信息不全）跳过继续沿链
/// ② 历史基准 baseline：date < baseline.date → 固化值（历史缺口稳定锚点）
/// ③ 兜底现状口径 baseBurn(settings)
int baseBurnForDate(AppSettings settings, RecordStore records, String dateStr) {
  final w = records.weightRecords;
  WeightEntry? hit;
  String? hitDate;
  for (final e in w.records.entries) {
    if (e.key.compareTo(dateStr) <= 0 && e.value.bmr > 0) {
      if (hitDate == null || e.key.compareTo(hitDate) > 0) {
        hitDate = e.key;
        hit = e.value;
      }
    }
  }
  if (hit != null) return (hit.bmr * kLifeFactor).round();
  final b = w.baseline;
  if (b != null && b.base > 0 && b.date.isNotEmpty && dateStr.compareTo(b.date) < 0) {
    return b.base;
  }
  return baseBurn(settings);
}

/// 某天生效体重（展示用；与 [baseBurnForDate] 同一沿用链），无任何来源返回 null
double? weightForDate(RecordStore records, String dateStr) =>
    records.weightRecords.entryFor(dateStr)?.weight;

/// 某天生效体脂率（与 [weightForDate] 同一沿用链，向前回溯最近一次测量的有效体脂率），无任何来源返回 null
double? bodyFatForDate(RecordStore records, String dateStr) =>
    records.weightRecords.bodyFatFor(dateStr);

/// 计划餐计入热量的值：优先当日覆盖，其次计划值；自由餐(null)无覆盖时为 0
int _mealCal(MealItem m, RecordStore records, String dateStr) {
  final adj = records.getAdjust(dateStr, 'meal', m.id);
  if (adj != null) return adj.calories;
  return m.calories ?? 0;
}

/// 减脂期每日宏量营养目标（克数）
class DailyMacroTargets {
  final int protein;
  final int carbs;
  final int fat;
  const DailyMacroTargets({
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// 根据目标热量、体重、体脂率、性别、身高科学计算减脂期适中偏少的每日营养素目标标准：
/// 1. 蛋白质：适中偏高以保肌防分解（~2.0g/kg 瘦体重，或 ~1.6g/kg 总体重）
/// 2. 脂肪：适中偏少维持激素平衡（~0.75g/kg 总体重，约占总热量 20%~25%）
/// 3. 碳水：适中偏少控碳，由剩余目标热量补充（剩余热量 / 4）
DailyMacroTargets calculateFatLossMacroTargets({
  required int targetCalories,
  double? weight,
  double? bodyFat,
  String? gender,
  int? height,
  int? age,
}) {
  final target = targetCalories > 0 ? targetCalories : 1800;

  // 1. 体重预估或实测
  final double w = (weight != null && weight > 0)
      ? weight
      : ((height != null && height > 0)
          ? ((gender == 'female' ? height - 105 : height - 100) * 0.9).clamp(45.0, 120.0)
          : (gender == 'female' ? 55.0 : 70.0));

  // 2. 去脂体重（LBM）
  double lbm;
  if (bodyFat != null && bodyFat > 5 && bodyFat < 60) {
    lbm = w * (1.0 - bodyFat / 100.0);
  } else {
    lbm = gender == 'female' ? w * 0.75 : w * 0.82;
  }

  // 3. 蛋白质：减脂期 2.0g/kg 瘦体重（保肌防分解，产生食物热效应）
  int p = (lbm * 2.0).round();
  final minP = gender == 'female' ? 60 : 75;
  final maxP = (target * 0.35 / 4).round();
  p = p.clamp(minP, max(minP, maxP));

  // 4. 脂肪：减脂期适中偏少（0.75g/kg 体重），维持睾酮/雌激素等激素分泌
  int f = (w * 0.75).round();
  final minF = gender == 'female' ? 35 : 45;
  final maxF = (target * 0.28 / 9).round();
  f = f.clamp(minF, max(minF, maxF));

  // 5. 碳水：减脂期由剩余目标热量提供（控碳），不足保底 50g
  final remainCal = target - (p * 4) - (f * 9);
  int c = (remainCal / 4).round();
  if (c < 50) c = 50;

  return DailyMacroTargets(protein: p, carbs: c, fat: f);
}

/// 当日汇总：缺口 = (基础消耗 + 运动消耗) - 已摄入
class DailySummary {
  final num plannedIntake; // 计划摄入（按计划值，未打卡也计）
  final num mealIntake; // 已打卡餐食实际摄入
  final num tempIntake; // 临时加餐摄入
  final num tempBurn; // 临时运动消耗
  final num extraIntake; // 旧加餐摄入（兼容）
  final num planBurn; // 计划运动打卡消耗
  final num exerciseBurn; // 运动消耗合计（计划打卡 + 临时/补录）
  final int baseBurn;
  final num burn; // 当日总消耗
  final num intake; // 总摄入
  final num tdee; // = baseBurn
  final num deficit; // 缺口
  final int taskCount; // 计划任务数（完成度只看计划）
  final int doneCount; // 已完成计划任务数

  // 三大宏量元素（克数）
  final int intakeProtein;
  final int intakeCarbs;
  final int intakeFat;
  final int plannedProtein;
  final int plannedCarbs;
  final int plannedFat;

  const DailySummary({
    required this.plannedIntake,
    required this.mealIntake,
    required this.tempIntake,
    required this.tempBurn,
    required this.extraIntake,
    required this.planBurn,
    required this.exerciseBurn,
    required this.baseBurn,
    required this.burn,
    required this.intake,
    required this.tdee,
    required this.deficit,
    required this.taskCount,
    required this.doneCount,
    this.intakeProtein = 0,
    this.intakeCarbs = 0,
    this.intakeFat = 0,
    this.plannedProtein = 0,
    this.plannedCarbs = 0,
    this.plannedFat = 0,
  });

  /// 是否有记录（供趋势/月历判断）
  bool get hasData => doneCount > 0 || tempIntake != 0 || tempBurn > 0 || extraIntake != 0;
}

DailySummary dailySummary(
  PlanData plan,
  AppSettings settings,
  RecordStore records,
  String dateStr, {
  UserProfile? profile,
}) {
  // F11 快照路径：该日已有快照 → 只读快照（历史固化）
  final entries = records.dayEntries[dateStr];
  if (entries != null) return _snapshotSummary(plan, settings, records, dateStr, entries, profile: profile);
  // 旧口径 fallback（未来日 / 理论上的未迁移日）
  return _legacySummary(plan, settings, records, dateStr, profile: profile);
}

/// 快照路径：只读当日条目（计划=模板时实例化后的当天事实）
DailySummary _snapshotSummary(
    PlanData plan, AppSettings settings, RecordStore records, String dateStr, List<DayEntry> entries,
    {UserProfile? profile}) {
  final rec = records.checkRecords[dateStr] ?? {};
  bool checked(DayEntry e) => rec.containsKey(entryCheckKey(e));
  final planMeals = entries.where((e) => e.isPlan && e.kind == 'meal').toList();
  final planExs = entries.where((e) => e.isPlan && e.kind == 'exercise').toList();
  final extraSnacks = entries.where((e) => !e.isPlan && e.kind == 'meal').toList();
  final extraExs = entries.where((e) => !e.isPlan && e.kind == 'exercise').toList();

  final plannedIntake = _sum(planMeals.map((e) => e.calories ?? 0));
  final mealIntake = _sum(planMeals.where(checked).map((e) => e.calories ?? 0));
  final tempIntake = _sum(extraSnacks.map((e) => e.calories ?? 0)); // 加餐即计
  final planBurn = _sum(planExs.where(checked).map((e) => e.calories ?? 0));
  final tempBurn = _sum(extraExs.map((e) => e.calories ?? 0)); // 加练即计
  const extraIntake = 0; // 旧 extraFoods 已并入快照

  final intake = mealIntake + tempIntake;
  final exerciseBurn = planBurn + tempBurn;
  final base = baseBurnForDate(settings, records, dateStr);
  final burn = base + exerciseBurn;
  final deficit = burn - intake;

  final planEntries = [...planMeals, ...planExs];
  final taskCount = planEntries.length;
  final doneCount = planEntries.where(checked).length;

  // 计算宏量元素（已打卡计划餐 + 临时加餐，支持损耗扣减）
  int inP = 0;
  int inC = 0;
  int inF = 0;
  for (final m in planMeals.where(checked)) {
    inP += m.protein ?? 0;
    inC += m.carbs ?? 0;
    inF += m.fat ?? 0;
  }
  for (final s in extraSnacks) {
    inP += s.protein ?? 0;
    inC += s.carbs ?? 0;
    inF += s.fat ?? 0;
  }
  inP = max(0, inP);
  inC = max(0, inC);
  inF = max(0, inF);

  // 计划期望宏量元素：
  // 严格以「根据身高体重、体脂率科学估算出的每日营养素标准」为基准目标
  // 优先取 plan.meta 中保存的目标值；若未显式保存则动态通过 calculateFatLossMacroTargets 计算
  final targetCal = (plan.meta.dailyCalorieTarget != null && plan.meta.dailyCalorieTarget! > 0)
      ? plan.meta.dailyCalorieTarget!.round()
      : (settings.dailyCalorieTarget > 0
          ? settings.dailyCalorieTarget
          : (plannedIntake > 0 ? plannedIntake.round() : settings.tdee));

  final w = weightForDate(records, dateStr) ?? profile?.weight ?? plan.meta.baseWeight;
  final bf = bodyFatForDate(records, dateStr) ?? profile?.bodyFat;
  final targets = calculateFatLossMacroTargets(
    targetCalories: targetCal,
    weight: w,
    bodyFat: bf,
    gender: profile?.gender,
    height: profile?.height,
    age: profile?.age,
  );

  final planP = plan.meta.targetProtein ?? targets.protein;
  final planC = plan.meta.targetCarbs ?? targets.carbs;
  final planF = plan.meta.targetFat ?? targets.fat;

  return DailySummary(
    plannedIntake: plannedIntake,
    mealIntake: mealIntake,
    tempIntake: tempIntake,
    tempBurn: tempBurn,
    extraIntake: extraIntake,
    planBurn: planBurn,
    exerciseBurn: exerciseBurn,
    baseBurn: base,
    burn: burn,
    intake: intake,
    tdee: base,
    deficit: deficit,
    taskCount: taskCount,
    doneCount: doneCount,
    intakeProtein: inP,
    intakeCarbs: inC,
    intakeFat: inF,
    plannedProtein: planP,
    plannedCarbs: planC,
    plannedFat: planF,
  );
}

/// 旧口径（fallback）：实时按当前计划投影
DailySummary _legacySummary(
  PlanData plan,
  AppSettings settings,
  RecordStore records,
  String dateStr, {
  UserProfile? profile,
}) {
  final tasks = getTasksForDate(plan, dateStr);
  final temps = records.getTempTasks(dateStr);
  final rec = records.checkRecords[dateStr] ?? {};
  bool doneMeal(MealItem m) => rec.containsKey('meal:${m.id}');
  bool doneEx(ExerciseItem e) => rec.containsKey('exercise:${e.id}');

  final plannedIntake = _sum(tasks.meals.map((m) => m.calories ?? 0));
  final mealIntake = _sum(tasks.meals.where(doneMeal).map((m) => _mealCal(m, records, dateStr)));
  final tempIntake = _sum(temps.where((t) => !t.isExercise).map((t) => t.calories));
  final tempBurn = _sum(temps.where((t) => t.isExercise).map((t) => t.calories));
  final extraIntake = _sum((records.extraFoods[dateStr] ?? []).map((f) {
    if (f is Map) return (f['calories'] is num) ? (f['calories'] as num) : 0;
    return 0;
  }));
  final planBurn = _sum(tasks.exercises.where(doneEx).map((e) => e.caloriesBurned));

  final intake = mealIntake + tempIntake + extraIntake;
  final exerciseBurn = planBurn + tempBurn;
  final base = baseBurnForDate(settings, records, dateStr);
  final burn = base + exerciseBurn;
  final deficit = burn - intake;

  // 完成度只看计划任务（临时加餐不打卡，不影响完成率）
  final taskCount = tasks.total;
  final doneCount = tasks.meals.where(doneMeal).length + tasks.exercises.where(doneEx).length;

  int inP = 0;
  int inC = 0;
  int inF = 0;
  for (final m in tasks.meals.where(doneMeal)) {
    inP += m.protein ?? 0;
    inC += m.carbs ?? 0;
    inF += m.fat ?? 0;
  }

  final targetCal = (plan.meta.dailyCalorieTarget != null && plan.meta.dailyCalorieTarget! > 0)
      ? plan.meta.dailyCalorieTarget!.round()
      : (settings.dailyCalorieTarget > 0
          ? settings.dailyCalorieTarget
          : (plannedIntake > 0 ? plannedIntake.round() : settings.tdee));

  final w = weightForDate(records, dateStr) ?? profile?.weight ?? plan.meta.baseWeight;
  final bf = bodyFatForDate(records, dateStr) ?? profile?.bodyFat;
  final targets = calculateFatLossMacroTargets(
    targetCalories: targetCal,
    weight: w,
    bodyFat: bf,
    gender: profile?.gender,
    height: profile?.height,
    age: profile?.age,
  );

  final planP = plan.meta.targetProtein ?? targets.protein;
  final planC = plan.meta.targetCarbs ?? targets.carbs;
  final planF = plan.meta.targetFat ?? targets.fat;

  return DailySummary(
    plannedIntake: plannedIntake,
    mealIntake: mealIntake,
    tempIntake: tempIntake,
    tempBurn: tempBurn,
    extraIntake: extraIntake,
    planBurn: planBurn,
    exerciseBurn: exerciseBurn,
    baseBurn: base,
    burn: burn,
    intake: intake,
    tdee: base,
    deficit: deficit,
    taskCount: taskCount,
    doneCount: doneCount,
    intakeProtein: inP,
    intakeCarbs: inC,
    intakeFat: inF,
    plannedProtein: planP,
    plannedCarbs: planC,
    plannedFat: planF,
  );
}

/// 缺口着色：ok 绿 / warning 橙 / danger 红
String deficitLevel(num v) {
  if (v < 0) return 'danger';
  if (v <= 300) return 'warning';
  if (v <= 800) return 'ok';
  return 'warning';
}

// ---------- 打卡天口径（连续打卡 / 累计打卡共用）----------
/// 「打卡天」= 当天存在任一实质打卡或记录行为：打卡/加餐/加练/实际热量覆盖/快照中有记录
bool dayActive(RecordStore records, String dateStr) {
  final rec = records.checkRecords[dateStr];
  if (rec != null && rec.isNotEmpty) return true;
  final entries = records.dayEntries[dateStr];
  if (entries != null && entries.isNotEmpty) {
    if (entries.any((e) => !e.isPlan || e.detached || (rec != null && rec.containsKey(entryCheckKey(e))))) {
      return true;
    }
  }
  if (records.getTempTasks(dateStr).isNotEmpty) return true;
  if ((records.extraFoods[dateStr] ?? []).isNotEmpty) return true;
  final adj = records.mealAdjust[dateStr];
  if (adj != null && adj.isNotEmpty) return true;
  return false;
}

/// 连续打卡天数：从今天往回数连续的「打卡天」个数（今天还没记录不算断；上限 730 天防脏数据死循环）
int streakDays(RecordStore records) {
  var d = todayStr();
  if (!dayActive(records, d)) d = addDays(d, -1);
  var s = 0;
  for (var i = 0; i < 730; i++) {
    if (dayActive(records, d)) {
      s++;
      d = addDays(d, -1);
    } else {
      break;
    }
  }
  return s;
}

/// 累计打卡天数：有记录以来所有「打卡天」的总数（且必然 ≥ 连续打卡天数）
int totalDoneDays(RecordStore records) {
  final dates = <String>{};
  dates.addAll(records.checkRecords.keys);
  dates.addAll(records.dayEntries.keys);
  dates.addAll(records.tempTasks.keys);
  dates.addAll(records.extraFoods.keys);
  dates.addAll(records.mealAdjust.keys);

  var n = 0;
  for (final d in dates) {
    if (dayActive(records, d)) n++;
  }
  return max(n, streakDays(records));
}

/// 本周单日数据点
class WeekDay {
  final String date;
  final DailySummary summary;
  final bool future;
  final bool beforeStart;
  WeekDay(this.date, this.summary, this.future, this.beforeStart);
}

/// 本周（周一到今天）逐日数据
List<WeekDay> weekData(PlanData plan, AppSettings settings, RecordStore records) {
  final t = todayStr();
  final start = plan.meta.startedAt;
  final weekday = parseDate(t).weekday; // 1=周一 … 7=周日
  final monday = addDays(t, -(weekday - 1));
  final arr = <WeekDay>[];
  for (var i = 0; i < 7; i++) {
    final date = addDays(monday, i);
    final s = dailySummary(plan, settings, records, date);
    arr.add(WeekDay(
      date,
      s,
      date.compareTo(t) > 0,
      start.isNotEmpty ? date.compareTo(start) < 0 : false,
    ));
  }
  return arr;
}

/// 近 N 天趋势点（含今天）
class TrendPoint {
  final String date;
  final String label;
  final num deficit;
  final bool hasData;
  TrendPoint(this.date, this.label, this.deficit, this.hasData);
}

/// 近 N 天趋势（含今天）；hasData=false 的天（没打卡/没加餐/没临时锻炼）不算缺口
List<TrendPoint> trendData(PlanData plan, AppSettings settings, RecordStore records, int n) {
  final t = todayStr();
  final arr = <TrendPoint>[];
  for (var i = n - 1; i >= 0; i--) {
    final date = addDays(t, -i);
    final s = dailySummary(plan, settings, records, date);
    arr.add(TrendPoint(
      date,
      int.parse(date.substring(8)).toString(),
      s.deficit,
      s.hasData,
    ));
  }
  return arr;
}

/// 某日详情：逐项列出当日计划餐/运动/临时加餐及打卡状态与实际热量
class DayDetailItem {
  final String id;
  final String name;
  final String type;
  final String time;
  final int? plannedCal;
  final int? actualCal;
  final int? protein;
  final int? carbs;
  final int? fat;
  final String note;
  final bool checked;
  DayDetailItem(
    this.id,
    this.name,
    this.type,
    this.time,
    this.plannedCal,
    this.actualCal,
    this.note,
    this.checked, {
    this.protein,
    this.carbs,
    this.fat,
  });
}

class DayDetailExercise {
  final String id;
  final String name;
  final String time;
  final int duration;
  final int burn;
  final bool checked;
  DayDetailExercise(this.id, this.name, this.time, this.duration, this.burn, this.checked);
}

class DaySnack {
  final String id;
  final String name;
  final String time;
  final int calories;
  final int? protein;
  final int? carbs;
  final int? fat;
  DaySnack(this.id, this.name, this.time, this.calories, {this.protein, this.carbs, this.fat});
}

class DayDetail {
  final DailySummary summary;
  final bool future;
  final bool beforeStart;
  final List<DayDetailItem> meals;
  final List<DayDetailExercise> exercises;
  final List<DaySnack> snacks;
  final List<DaySnack> tempExercises;
  DayDetail({
    required this.summary,
    required this.future,
    required this.beforeStart,
    required this.meals,
    required this.exercises,
    required this.snacks,
    required this.tempExercises,
  });
}

DayDetail dayDetail(PlanData plan, AppSettings settings, RecordStore records, String dateStr, {UserProfile? profile}) {
  final rec = records.checkRecords[dateStr] ?? {};
  final s = dailySummary(plan, settings, records, dateStr, profile: profile);
  final start = plan.meta.startedAt;

  final entries = records.dayEntries[dateStr];
  if (entries != null) {
    // F11 快照路径：某日详情只读当日快照（历史固化；计划外条目即加餐/加练）
    final planMeals = entries.where((e) => e.isPlan && e.kind == 'meal').toList();
    final planExs = entries.where((e) => e.isPlan && e.kind == 'exercise').toList();
    final snacks = entries
        .where((e) => !e.isPlan && e.kind == 'meal')
        .map((e) => DaySnack(e.id, e.content, e.time, e.calories ?? 0,
            protein: e.protein, carbs: e.carbs, fat: e.fat))
        .toList();
    final tempExs = entries
        .where((e) => !e.isPlan && e.kind == 'exercise')
        .map((e) => DaySnack(e.id, e.content, e.time, e.calories ?? 0))
        .toList();
    return DayDetail(
      summary: s,
      future: dateStr.compareTo(todayStr()) > 0,
      beforeStart: start.isNotEmpty ? dateStr.compareTo(start) < 0 : false,
      meals: planMeals
          .map((e) => DayDetailItem(
                e.id,
                e.content,
                e.slot,
                e.time,
                null,
                e.calories,
                e.note,
                rec.containsKey(entryCheckKey(e)),
                protein: e.protein,
                carbs: e.carbs,
                fat: e.fat,
              ))
          .toList(),
      exercises: planExs
          .map((e) => DayDetailExercise(
                e.id,
                e.content,
                e.time,
                0,
                e.calories ?? 0,
                rec.containsKey(entryCheckKey(e)),
              ))
          .toList(),
      snacks: snacks,
      tempExercises: tempExs,
    );
  }

  // 旧口径 fallback（未来日 / 理论上的未迁移日）
  final tasks = getTasksForDate(plan, dateStr);
  final temps = records.getTempTasks(dateStr);

  final meals = tasks.meals.map((m) {
    final adj = records.getAdjust(dateStr, 'meal', m.id);
    return DayDetailItem(
      m.id,
      m.name,
      m.type,
      m.time,
      m.calories,
      adj?.calories,
      adj?.note ?? '',
      rec.containsKey('meal:${m.id}'),
    );
  }).toList();

  final exercises = tasks.exercises
      .map((e) => DayDetailExercise(
            e.id,
            e.name,
            e.time,
            e.duration,
            e.caloriesBurned,
            rec.containsKey('exercise:${e.id}'),
          ))
      .toList();

  final snacks = temps
      .where((t) => !t.isExercise)
      .map((t) => DaySnack(t.id, t.name, t.time, t.calories))
      .toList();
  final tempExercises = temps
      .where((t) => t.isExercise)
      .map((t) => DaySnack(t.id, t.name, t.time, t.calories))
      .toList();

  return DayDetail(
    summary: s,
    future: dateStr.compareTo(todayStr()) > 0,
    beforeStart: start.isNotEmpty ? dateStr.compareTo(start) < 0 : false,
    meals: meals,
    exercises: exercises,
    snacks: snacks,
    tempExercises: tempExercises,
  );
}

/// 月回顾结果
class MonthReview {
  final int doneDays; // 计划完成天数
  final int activeDays; // 有记录天数
  final num totalDeficit; // 总缺口
  final int avgDeficit; // 日均缺口
  final MaxDay? maxBurnDay;
  final MaxDay? maxIntakeDay;

  const MonthReview({
    required this.doneDays,
    required this.activeDays,
    required this.totalDeficit,
    required this.avgDeficit,
    this.maxBurnDay,
    this.maxIntakeDay,
  });
}

class MaxDay {
  final String date;
  final num burn;
  final int base;
  final num exercise;
  final num intake;
  final num deficit;
  const MaxDay({required this.date, required this.burn, required this.base, required this.exercise, required this.intake, required this.deficit});
}

/// 当月回顾：只统计开始日之后、今天之前有记录的日子；未来与开始前不参与
MonthReview monthReview(PlanData plan, AppSettings settings, RecordStore records, int year, int month) {
  final t = todayStr();
  final start = plan.meta.startedAt;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  var doneDays = 0;
  var activeDays = 0;
  num totalDeficit = 0;
  MaxDay? maxBurnDay;
  MaxDay? maxIntakeDay;

  for (var d = 1; d <= daysInMonth; d++) {
    final date = fmtDate(DateTime(year, month, d));
    if (date.compareTo(t) > 0) break;
    if (start.isNotEmpty && date.compareTo(start) < 0) continue;
    final (total, done) = taskProgress(plan, records, date);
    if (total > 0 && done >= total) doneDays++;
    final s = dailySummary(plan, settings, records, date);
    if (!s.hasData) continue;
    activeDays++;
    totalDeficit += s.deficit;
    if (maxBurnDay == null || s.burn > maxBurnDay.burn) {
      maxBurnDay = MaxDay(
        date: date,
        burn: s.burn,
        base: s.baseBurn,
        exercise: s.exerciseBurn,
        intake: s.intake,
        deficit: s.deficit,
      );
    }
    if (maxIntakeDay == null || s.intake > maxIntakeDay.intake) {
      maxIntakeDay = MaxDay(
        date: date,
        burn: s.burn,
        base: s.baseBurn,
        exercise: s.exerciseBurn,
        intake: s.intake,
        deficit: s.deficit,
      );
    }
  }
  return MonthReview(
    doneDays: doneDays,
    activeDays: activeDays,
    totalDeficit: totalDeficit,
    avgDeficit: activeDays != 0 ? (totalDeficit / activeDays).round() : 0,
    maxBurnDay: maxBurnDay,
    maxIntakeDay: maxIntakeDay,
  );
}

/// 月历单元格
class MonthCell {
  final String date;
  final int day;
  final int total;
  final int done;
  final double rate;
  final bool complete;
  final bool future;
  final bool beforeStart;
  final bool isStart;
  const MonthCell({
    required this.date,
    required this.day,
    required this.total,
    required this.done,
    required this.rate,
    required this.complete,
    required this.future,
    required this.beforeStart,
    required this.isStart,
  });
}

class MonthData {
  final List<MonthCell?> cells; // 前 lead 个为 null（占位）
  final int lead;
  MonthData(this.cells, this.lead);
}

/// 月历数据：当月每天完成率（仅计划任务）；周一开头
MonthData monthData(PlanData plan, RecordStore records, int year, int month) {
  final first = DateTime(year, month, 1);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final lead = first.weekday - 1; // 周一开头：周一(1)→0 … 周日(7)→6（对应 JS getDay()-1）
  final cells = <MonthCell?>[];
  for (var i = 0; i < lead; i++) {
    cells.add(null);
  }
  final t = todayStr();
  final start = plan.meta.startedAt;
  for (var d = 1; d <= daysInMonth; d++) {
    final date = fmtDate(DateTime(year, month, d));
    final (total, done) = taskProgress(plan, records, date);
    cells.add(MonthCell(
      date: date,
      day: d,
      total: total,
      done: done,
      rate: total != 0 ? done / total : 0,
      complete: total > 0 && done >= total,
      future: date.compareTo(t) > 0,
      beforeStart: start.isNotEmpty ? date.compareTo(start) < 0 : false,
      isStart: start.isNotEmpty && date == start,
    ));
  }
  return MonthData(cells, lead);
}
