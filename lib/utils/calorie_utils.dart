/// 热量缺口计算与统计聚合（与旧版 uni-app calorie.js 1:1 对齐）
/// 口径：当日消耗 = 基础消耗（BMR × 生活系数，不含刻意运动）+ 当日实际运动（打卡的计划运动 + 临时/补录运动）
/// 已摄入 = 已打卡计划餐(实际值) + 临时加餐(全计) + 旧加餐记录(兼容)
library;

import '../models/plan_data.dart';
import '../models/records.dart';
import '../models/settings.dart';
import 'date_utils.dart';
import 'plan_utils.dart';

/// 生活基础系数：日常起居消耗（不含刻意运动；运动打卡/补录后另计入）
const double kLifeFactor = 1.2;

num _sum(Iterable<num?> arr) => arr.fold<num>(0, (a, b) => a + (b ?? 0));

/// 基础消耗（不含运动）：优先用已存的 BMR × 生活系数；未存 BMR 时沿用 tdee（旧数据兼容）
int baseBurn(AppSettings settings) {
  final bmr = settings.bmr;
  if (bmr > 0) return (bmr * kLifeFactor).round();
  return settings.tdee;
}

/// 计划餐计入热量的值：优先当日覆盖，其次计划值；自由餐(null)无覆盖时为 0
int _mealCal(MealItem m, RecordStore records, String dateStr) {
  final adj = records.getAdjust(dateStr, 'meal', m.id);
  if (adj != null) return adj.calories;
  return m.calories ?? 0;
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
  });

  /// 是否有记录（供趋势/月历判断）
  bool get hasData => doneCount > 0 || tempIntake > 0 || tempBurn > 0 || extraIntake > 0;
}

DailySummary dailySummary(
  PlanData plan,
  AppSettings settings,
  RecordStore records,
  String dateStr,
) {
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
  final burn = baseBurn(settings) + exerciseBurn;
  final deficit = burn - intake;

  // 完成度只看计划任务（临时加餐不打卡，不影响完成率）
  final taskCount = tasks.total;
  final doneCount = tasks.meals.where(doneMeal).length + tasks.exercises.where(doneEx).length;

  return DailySummary(
    plannedIntake: plannedIntake,
    mealIntake: mealIntake,
    tempIntake: tempIntake,
    tempBurn: tempBurn,
    extraIntake: extraIntake,
    planBurn: planBurn,
    exerciseBurn: exerciseBurn,
    baseBurn: baseBurn(settings),
    burn: burn,
    intake: intake,
    tdee: baseBurn(settings),
    deficit: deficit,
    taskCount: taskCount,
    doneCount: doneCount,
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
/// 「打卡天」= 当天存在任一记录就算：打卡/临时任务/旧加餐/实际热量覆盖
bool dayActive(RecordStore records, String dateStr) {
  final rec = records.checkRecords[dateStr];
  if (rec != null && rec.isNotEmpty) return true;
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

/// 累计打卡天数：有记录以来所有「打卡天」的总数
int totalDoneDays(RecordStore records) {
  final dates = <String>{};
  void collect(Map<String, dynamic> obj) {
    for (final k in obj.keys) {
      dates.add(k);
    }
  }

  collect(records.checkRecords.map((k, v) => MapEntry(k, v)));
  collect(records.tempTasks.map((k, v) => MapEntry(k, v)));
  collect(records.extraFoods.map((k, v) => MapEntry(k, v)));
  collect(records.mealAdjust.map((k, v) => MapEntry(k, v)));

  var n = 0;
  for (final d in dates) {
    if (dayActive(records, d)) n++;
  }
  return n;
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
  final String note;
  final bool checked;
  DayDetailItem(this.id, this.name, this.type, this.time, this.plannedCal, this.actualCal, this.note, this.checked);
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
  DaySnack(this.id, this.name, this.time, this.calories);
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

DayDetail dayDetail(PlanData plan, AppSettings settings, RecordStore records, String dateStr) {
  final tasks = getTasksForDate(plan, dateStr);
  final temps = records.getTempTasks(dateStr);
  final rec = records.checkRecords[dateStr] ?? {};
  final s = dailySummary(plan, settings, records, dateStr);
  final start = plan.meta.startedAt;

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
    final tasks = getTasksForDate(plan, date);
    final total = tasks.total;
    final rec = records.checkRecords[date] ?? {};
    final done = total != 0
        ? tasks.meals.where((m) => rec.containsKey('meal:${m.id}')).length +
            tasks.exercises.where((e) => rec.containsKey('exercise:${e.id}')).length
        : 0;
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
    final tasks = getTasksForDate(plan, date);
    final total = tasks.total;
    final rec = records.checkRecords[date] ?? {};
    final done = total != 0
        ? tasks.meals.where((m) => rec.containsKey('meal:${m.id}')).length +
            tasks.exercises.where((e) => rec.containsKey('exercise:${e.id}')).length
        : 0;
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
