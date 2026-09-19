/// 核心算法单元测试：与旧版 uni-app（calorie.js / plan.js / record.js）1:1 对照
/// 覆盖：日期工具 / getTasksForDate / dailySummary（缺口计算）/ streakDays（连续打卡）
///       monthData（月历）/ monthReview（月回顾）/ validateRaw / normalizePlan / estimateCost
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';
import 'package:jianfei_dazi/utils/plan_utils.dart';

void main() {
  // ---------- 日期工具 ----------

  group('date_utils', () {
    test('fmtDate/parseDate/addDays 往返一致', () {
      expect(fmtDate(DateTime(2026, 9, 2)), '2026-09-02');
      expect(parseDate('2026-09-02').y, 2026);
      expect(parseDate('2026-09-02').m, 9);
      expect(parseDate('2026-09-02').d, 2);
      expect(addDays('2026-09-02', 1), '2026-09-03');
      expect(addDays('2026-09-02', -1), '2026-09-01');
      expect(addDays('2026-08-31', 1), '2026-09-01'); // 跨月
      expect(addDays('2026-12-31', 1), '2027-01-01'); // 跨年
    });

    test('weekday 语义：1=周一 … 7=周日（与 JS getDay 的 0=周日 不同）', () {
      expect(parseDate('2026-09-02').weekday, 3); // 周三
      expect(parseDate('2026-09-06').weekday, 7); // 周日
      expect(parseDate('2026-09-07').weekday, 1); // 周一
      expect(weekCn(3), '三');
    });

    test('isValidDateStr 拒绝进位日期', () {
      expect(isValidDateStr('2026-02-28'), true);
      expect(isValidDateStr('2026-02-30'), false); // 2026 非闰年
      expect(isValidDateStr('2024-02-29'), true); // 闰年
      expect(isValidDateStr('2026-13-01'), false);
      expect(isValidDateStr('2026-9-2'), false);
      expect(isValidDateStr('abc'), false);
    });

    test('daysCn / datesCn 展示格式', () {
      expect(daysCn([1, 3, 5]), '一三五');
      expect(daysCn([]), '每天');
      expect(datesCn(['2026-09-05', '2026-09-19']), '9/5、9/19');
      expect(datesCn(['2026-09-05', '2026-09-06', '2026-09-07']), '9/5、9/6 等3天');
    });
  });

  // ---------- 当日任务 ----------

  group('getTasksForDate', () {
    // 2026-09-02 是周三（weekday=3）
    final plan = PlanData(
      meta: PlanMeta(startedAt: '2026-09-01'),
      meals: [
        MealItem(id: 'm1', type: 'breakfast', name: '包子', time: '07:30', calories: 300, days: [3]),
        MealItem(id: 'm2', type: 'lunch', name: '沙拉', time: '12:00', calories: 400, days: [1, 5]),
        MealItem(id: 'm3', type: 'dinner', name: '自由餐', time: '18:00', calories: null, days: [2, 3]),
      ],
      exercises: [
        ExerciseItem(id: 'e1', name: '慢跑', time: '18:30', duration: 30, caloriesBurned: 300, days: [3, 6]),
        ExerciseItem(id: 'e2', name: '深蹲', time: '06:00', duration: 15, caloriesBurned: 100, days: [1, 2]),
      ],
    );

    test('按 days 周几命中并按时序排列', () {
      final tasks = getTasksForDate(plan, '2026-09-02'); // 周三
      expect(tasks.meals.map((m) => m.id).toList(), ['m1', 'm3']); // 07:30 在前
      expect(tasks.exercises.map((e) => e.id).toList(), ['e1']);
    });

    test('不命中的天返回空任务', () {
      final tasks = getTasksForDate(plan, '2026-09-06'); // 周日：所有 days 均不包含 7
      expect(tasks.total, 0);
    });

    test('计划开始日之前不产生任务', () {
      final tasks = getTasksForDate(plan, '2026-08-31');
      expect(tasks.total, 0);
    });

    test('dates 指定日期优先于 days', () {
      final p = PlanData(
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [
          MealItem(id: 'm1', type: 'lunch', name: '特定餐', time: '12:00', calories: 500, dates: ['2026-09-02']),
        ],
      );
      expect(getTasksForDate(p, '2026-09-02').total, 1);
      expect(getTasksForDate(p, '2026-09-03').total, 0);
    });
  });

  // ---------- 缺口计算 ----------

  group('dailySummary（缺口 = 基础消耗 + 运动消耗 − 摄入）', () {
    // 计划：早 300 + 午 400；运动 30 分钟消耗 300
    PlanData buildPlan() => PlanData(
          meta: PlanMeta(startedAt: '2026-09-01'),
          meals: [
            MealItem(id: 'm1', type: 'breakfast', name: '早餐', time: '07:30', calories: 300, days: [3]),
            MealItem(id: 'm2', type: 'lunch', name: '午餐', time: '12:00', calories: 400, days: [3]),
          ],
          exercises: [
            ExerciseItem(id: 'e1', name: '慢跑', time: '18:30', duration: 30, caloriesBurned: 300, days: [3]),
          ],
        );

    RecordStore storeWith(Map<String, Map<String, CheckEntry>>? checks,
        {Map<String, List<dynamic>>? extraFoods,
        Map<String, Map<String, AdjustEntry>>? mealAdjust,
        Map<String, List<TempTask>>? tempTasks}) {
      return RecordStore(
        checkRecords: checks ?? {},
        extraFoods: extraFoods ?? {},
        mealAdjust: mealAdjust ?? {},
        tempTasks: tempTasks ?? {},
      );
    }

    test('基础消耗：bmr>0 用 bmr×1.2，否则沿用 tdee（旧数据兼容）', () {
      final plan = buildPlan();
      final s1 = dailySummary(plan, AppSettings(tdee: 2000, bmr: 1500), RecordStore.empty(), '2026-09-02');
      expect(s1.baseBurn, (1500 * 1.2).round());
      expect(s1.tdee, s1.baseBurn);
      final s2 = dailySummary(plan, AppSettings(tdee: 2000, bmr: 0), RecordStore.empty(), '2026-09-02');
      expect(s2.baseBurn, 2000);
    });

    test('无任何记录时：缺口 = 基础消耗 − 0，摄入为 0', () {
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), RecordStore.empty(), '2026-09-02');
      expect(s.baseBurn, 2000);
      expect(s.mealIntake, 0);
      expect(s.intake, 0);
      expect(s.burn, 2000);
      expect(s.deficit, 2000);
      expect(s.taskCount, 3);
      expect(s.doneCount, 0);
      expect(s.hasData, false);
    });

    test('打卡计划餐后：mealIntake 只计已打卡项', () {
      final store = storeWith({
        '2026-09-02': {'meal:m1': CheckEntry(checkedAt: 1)},
      });
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, '2026-09-02');
      expect(s.mealIntake, 300);
      expect(s.doneCount, 1);
      expect(s.intake, 300);
      expect(s.deficit, 2000 - 300);
    });

    test('当日覆盖(mealAdjust)优先于计划值', () {
      final store = storeWith({
        '2026-09-02': {'meal:m1': CheckEntry(checkedAt: 1)},
      }, mealAdjust: {
        '2026-09-02': {'meal:m1': AdjustEntry(calories: 500, note: '多喝了一杯奶')},
      });
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, '2026-09-02');
      expect(s.mealIntake, 500);
    });

    test('自由餐(null)未打卡计 0，打卡时按覆盖值', () {
      final plan = PlanData(
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [MealItem(id: 'm1', type: 'dinner', name: '自由餐', time: '18:00', calories: null, days: [3])],
      );
      final s0 = dailySummary(plan, AppSettings(tdee: 2000), RecordStore.empty(), '2026-09-02');
      expect(s0.plannedIntake, 0);
      final store = storeWith({
        '2026-09-02': {'meal:m1': CheckEntry(checkedAt: 1)},
      }, mealAdjust: {
        '2026-09-02': {'meal:m1': AdjustEntry(calories: 900)},
      });
      final s1 = dailySummary(plan, AppSettings(tdee: 2000), store, '2026-09-02');
      expect(s1.mealIntake, 900);
    });

    test('打卡运动后：exerciseBurn = planBurn + tempBurn，计入总消耗', () {
      final store = storeWith({
        '2026-09-02': {'exercise:e1': CheckEntry(checkedAt: 1)},
      });
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, '2026-09-02');
      expect(s.planBurn, 300);
      expect(s.exerciseBurn, 300);
      expect(s.burn, 2300);
    });

    test('临时加餐计入摄入、临时运动计入消耗', () {
      final store = storeWith({}, tempTasks: {
        '2026-09-02': [
          TempTask(id: 't1', type: 'snack', name: '奶茶', time: '15:00', calories: 400),
          TempTask(id: 't2', type: 'exercise', name: '爬楼梯', time: '20:00', calories: 120),
        ],
      });
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, '2026-09-02');
      expect(s.tempIntake, 400);
      expect(s.tempBurn, 120);
      expect(s.intake, 400);
      expect(s.burn, 2000 + 120);
      expect(s.hasData, true);
    });

    test('旧加餐记录(extraFoods)计入摄入（兼容）', () {
      final store = storeWith({}, extraFoods: {
        '2026-09-02': [
          {'id': 'f1', 'name': '苹果', 'calories': 80, 'at': '10:00', 'source': 'manual'},
        ],
      });
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, '2026-09-02');
      expect(s.extraIntake, 80);
      expect(s.intake, 80);
    });

    test('完整场景：打卡早午 + 运动 + 临时加餐，缺口正确', () {
      final store = storeWith({
        '2026-09-02': {
          'meal:m1': CheckEntry(checkedAt: 1),
          'meal:m2': CheckEntry(checkedAt: 1),
          'exercise:e1': CheckEntry(checkedAt: 1),
        },
      }, tempTasks: {
        '2026-09-02': [TempTask(id: 't1', type: 'snack', name: '奶茶', time: '15:00', calories: 400)],
      });
      final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, '2026-09-02');
      expect(s.mealIntake, 700);
      expect(s.tempIntake, 400);
      expect(s.intake, 1100);
      expect(s.exerciseBurn, 300);
      expect(s.burn, 2300);
      expect(s.deficit, 2300 - 1100); // 1200
      expect(s.doneCount, 3);
      expect(s.taskCount, 3);
    });

    test('deficitLevel 着色边界', () {
      expect(deficitLevel(-1), 'danger');
      expect(deficitLevel(0), 'warning');
      expect(deficitLevel(300), 'warning');
      expect(deficitLevel(301), 'ok');
      expect(deficitLevel(800), 'ok');
      expect(deficitLevel(801), 'warning');
    });
  });

  // ---------- 连续打卡 ----------

  group('streakDays（连续打卡天）', () {
    test('今天有记录：从今天往回数', () {
      final t = todayStr();
      final store = RecordStore(checkRecords: {
        t: {'meal:m1': CheckEntry(checkedAt: 1)},
        addDays(t, -1): {'meal:m1': CheckEntry(checkedAt: 1)},
        addDays(t, -2): {'meal:m1': CheckEntry(checkedAt: 1)},
      });
      expect(streakDays(store), 3);
    });

    test('今天没记录：从昨天往回数（今天不算断）', () {
      final t = todayStr();
      final store = RecordStore(checkRecords: {
        addDays(t, -1): {'meal:m1': CheckEntry(checkedAt: 1)},
        addDays(t, -2): {'meal:m1': CheckEntry(checkedAt: 1)},
      });
      expect(streakDays(store), 2);
    });

    test('中间断档则中断', () {
      final t = todayStr();
      final store = RecordStore(checkRecords: {
        t: {'meal:m1': CheckEntry(checkedAt: 1)},
        addDays(t, -1): {'meal:m1': CheckEntry(checkedAt: 1)},
        addDays(t, -3): {'meal:m1': CheckEntry(checkedAt: 1)}, // -2 缺失
      });
      expect(streakDays(store), 2);
    });

    test('无任何记录返回 0', () {
      expect(streakDays(RecordStore.empty()), 0);
    });

    test('临时加餐也算「打卡天」', () {
      final t = todayStr();
      final store = RecordStore(tempTasks: {
        t: [TempTask(id: 't1', type: 'snack', name: '奶茶', time: '15:00', calories: 400)],
        addDays(t, -1): [TempTask(id: 't2', type: 'snack', name: '饼干', time: '15:00', calories: 200)],
      });
      expect(streakDays(store), 2);
    });

    test('totalDoneDays 累计去重', () {
      final t = todayStr();
      final store = RecordStore(
        checkRecords: {
          t: {'meal:m1': CheckEntry(checkedAt: 1)},
          addDays(t, -1): {'meal:m1': CheckEntry(checkedAt: 1)},
          addDays(t, -2): {'meal:m1': CheckEntry(checkedAt: 1)},
        },
        tempTasks: {
          t: [TempTask(id: 't1', type: 'snack', name: 'x', time: '15:00', calories: 1)],
        },
      );
      expect(totalDoneDays(store), 3); // 同一日期不重复计
    });

    test('totalDoneDays 绝不小于 streakDays，且包含 dayEntries', () {
      final t = todayStr();
      final store = RecordStore(
        checkRecords: {
          t: {'meal:m1': CheckEntry(checkedAt: 1)},
        },
        dayEntries: {
          t: [DayEntry(id: 'm1', kind: 'meal', slot: 'lunch', content: '饭', calories: 400, source: 'plan', planItemId: 'm1')],
          addDays(t, -1): [DayEntry(id: 't1', kind: 'meal', slot: 'snack', content: '零食', calories: 100, source: 'ai')],
          addDays(t, -2): [DayEntry(id: 't2', kind: 'meal', slot: 'snack', content: '鸡胸肉', calories: 150, source: 'manual')],
        },
      );
      final streak = streakDays(store);
      final total = totalDoneDays(store);
      expect(streak, 3);
      expect(total >= streak, isTrue);
      expect(total, 3);
    });
  });

  group('calculateFatLossMacroTargets（减脂期宏量目标科学测算）', () {
    test('根据体重、体脂率与目标热量测算适中偏少宏量', () {
      final res = calculateFatLossMacroTargets(
        targetCalories: 2790,
        weight: 75.0,
        bodyFat: 20.0,
        gender: 'male',
        height: 175,
        age: 28,
      );
      // LBM = 60kg, P = 120g, F = 56g, C = (2790 - 480 - 504)/4 = 451g
      expect(res.protein, 120);
      expect(res.fat, 56);
      expect(res.carbs, 452);
      // 总能量守恒校验：P*4 + C*4 + F*9 接近 2790
      final totalCal = res.protein * 4 + res.carbs * 4 + res.fat * 9;
      expect((totalCal - 2790).abs() <= 5, isTrue);
    });

    test('无体脂率时按性别体脂常模估算', () {
      final res = calculateFatLossMacroTargets(
        targetCalories: 1800,
        weight: 60.0,
        gender: 'female',
        height: 165,
      );
      expect(res.protein >= 60, isTrue);
      expect(res.fat >= 35, isTrue);
      expect(res.carbs >= 50, isTrue);
      final totalCal = res.protein * 4 + res.carbs * 4 + res.fat * 9;
      expect((totalCal - 1800).abs() <= 5, isTrue);
    });
  });

  // ---------- 月历 / 月回顾 ----------

  group('monthData / monthReview', () {
    test('月历 lead：周一开头（2026-09-01 为周二 → lead=1）', () {
      final plan = PlanData(meta: PlanMeta(startedAt: '2026-09-01'));
      final md = monthData(plan, RecordStore.empty(), 2026, 9);
      expect(md.lead, 1);
      expect(md.cells.length, 1 + 30); // 9 月 30 天
      expect(md.cells[1]!.day, 1);
      expect(md.cells[0], isNull);
    });

    test('月历完成率只看计划任务', () {
      final plan = PlanData(
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [MealItem(id: 'm1', type: 'lunch', name: '午餐', time: '12:00', calories: 400, days: [2])],
      );
      final store = RecordStore(checkRecords: {
        '2026-09-01': {'meal:m1': CheckEntry(checkedAt: 1)},
      });
      final md = monthData(plan, store, 2026, 9);
      // 9/1 周二：当天有任务且已打卡 → complete
      final cell = md.cells.firstWhere((c) => c != null && c.date == '2026-09-01');
      expect(cell!.total, 1);
      expect(cell.done, 1);
      expect(cell.complete, true);
      // 9/8 周二：有任务未打卡
      final cell8 = md.cells.firstWhere((c) => c != null && c.date == '2026-09-08');
      expect(cell8!.complete, false);
    });

    test('monthReview：doneDays 全完成、activeDays 有记录、avgDeficit', () {
      final plan = PlanData(
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [MealItem(id: 'm1', type: 'lunch', name: '午餐', time: '12:00', calories: 400, days: [2, 3])],
      );
      final store = RecordStore(checkRecords: {
        '2026-09-01': {'meal:m1': CheckEntry(checkedAt: 1)}, // 周二
        '2026-09-02': {'meal:m1': CheckEntry(checkedAt: 1)}, // 周三
      });
      final r = monthReview(plan, AppSettings(tdee: 2000), store, 2026, 9);
      expect(r.doneDays, 2);
      expect(r.activeDays, 2);
      // 每天缺口 = 2000 - 400 = 1600
      expect(r.totalDeficit, 3200);
      expect(r.avgDeficit, 1600);
    });
  });

  // ---------- 校验 / 归一化 ----------

  group('validateRaw', () {
    test('根节点非对象', () {
      expect(validateRaw('[]'), ['JSON 根节点必须是对象 { }']);
    });

    test('version 必须 1.0', () {
      expect(validateRaw({'version': '2.0', 'meals': [], 'exercises': []}).first, contains('1.0'));
    });

    test('空计划报错', () {
      final errs = validateRaw({'version': '1.0', 'meals': [], 'exercises': []});
      expect(errs, contains('导入内容为空：meals 或 exercises 至少需要一项'));
    });

    test('时间格式错误 / 非法 type / 非法 days', () {
      final errs = validateRaw({
        'version': '1.0',
        'meals': [
          {'name': '早餐', 'time': '25:00', 'type': 'brunch', 'calories': 300, 'days': [8]},
        ],
      });
      expect(errs.any((e) => e.contains('时间格式错误')), true);
      expect(errs.any((e) => e.contains('type 无效')), true);
      expect(errs.any((e) => e.contains('days 含非法值')), true);
    });

    test('合法计划通过（数字字符串热量也接受）', () {
      final errs = validateRaw({
        'version': '1.0',
        'meta': {'planName': '我的计划'},
        'meals': [
          {'name': '早餐', 'time': '07:30', 'type': 'breakfast', 'calories': '300', 'days': [1, 2, 3, 4, 5]},
        ],
        'exercises': [
          {'name': '慢跑', 'time': '18:30', 'duration': 30, 'caloriesBurned': 300, 'days': [3, 5]},
        ],
      });
      expect(errs, isEmpty);
    });
  });

  group('normalizePlan（容错归一化）', () {
    test('数字字符串热量 / 中文 type / 带秒时间 / 单数字 days 均被纠正', () {
      final p = normalizePlan({
        'version': '1.0',
        'meals': [
          {'name': '早餐', 'time': '07:30:00', 'type': '早餐', 'calories': '300', 'days': '3'},
        ],
        'exercises': [
          {'name': '慢跑', 'time': '18:30', 'duration': '30', 'caloriesBurned': '300', 'days': [3]},
        ],
      });
      expect(p.meals.single.time, '07:30');
      expect(p.meals.single.type, 'breakfast');
      expect(p.meals.single.calories, 300);
      expect(p.meals.single.days, [3]);
      expect(p.exercises.single.duration, 30);
      expect(p.exercises.single.caloriesBurned, 300);
      expect(p.meals.single.id, isNotEmpty);
    });

    test('自由餐 calories=null 保留为 null', () {
      final p = normalizePlan({
        'version': '1.0',
        'meals': [
          {'name': '自由餐', 'time': '18:00', 'type': 'dinner', 'calories': null, 'days': [1]},
        ],
      });
      expect(p.meals.single.calories, isNull);
    });

    test('同 id 去重保留首个', () {
      final p = normalizePlan({
        'version': '1.0',
        'meals': [
          {'id': 'm1', 'name': '第一版', 'time': '07:30', 'type': 'breakfast', 'calories': 300, 'days': [1]},
          {'id': 'm1', 'name': '重复版', 'time': '12:00', 'type': 'lunch', 'calories': 500, 'days': [2]},
        ],
      });
      expect(p.meals.length, 1);
      expect(p.meals.single.name, '第一版');
    });

    test('details / steps / content 结构化字段', () {
      final p = normalizePlan({
        'version': '1.0',
        'meals': [
          {
            'name': '番茄炒蛋',
            'time': '12:00',
            'type': 'lunch',
            'calories': 400,
            'days': [1],
            'details': [
              {'item': '番茄', 'amount': '2个'},
              {'item': '鸡蛋', 'amount': '2个'},
            ],
            'steps': ['打蛋', '翻炒'],
          },
        ],
        'exercises': [
          {
            'name': '哑铃弯举',
            'time': '18:00',
            'duration': 20,
            'days': [1],
            'content': [
              {'item': '弯举', 'detail': '12次×4组', 'minutes': 10},
            ],
          },
        ],
      });
      expect(p.meals.single.details.length, 2);
      expect(p.meals.single.steps, ['打蛋', '翻炒']);
      expect(p.exercises.single.content.single.minutes, 10);
    });
  });

  // ---------- 费用估算 ----------

  group('estimateCost', () {
    test('按 DeepSeek V4-Flash 牌价计算', () {
      // 10 万 input miss + 5 万 cache hit + 2 万 output
      final u = ApiUsage(calls: 3, promptTokens: 150000, cacheHitTokens: 50000, completionTokens: 20000);
      final cost = estimateCost(u);
      expect(cost, closeTo(100000 / 1e6 * 1.5 + 50000 / 1e6 * 0.05 + 20000 / 1e6 * 4.5, 0.0001));
      expect(u.calls, 3);
    });

    test('cache hit 不超过 prompt 时按差额计费（防御）', () {
      final u = ApiUsage(promptTokens: 1000, cacheHitTokens: 5000, completionTokens: 0);
      expect(estimateCost(u), closeTo(5000 / 1e6 * 0.05, 0.0001)); // miss 按 0
    });
  });
}
