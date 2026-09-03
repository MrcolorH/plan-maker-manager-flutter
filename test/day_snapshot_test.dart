/// F11 当日条目快照核心逻辑测试
/// 覆盖：syncDayEntries 实例化/跟随/失效移除/脱钩保留、dailySummary 快照口径、
///       历史固化（计划变更不影响历史统计）、convertLegacyToEntries 转换
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/utils/legacy_convert.dart';

/// 周三（days=[3]）计划：早 m1 300 / 午 m2 400 / 运动 e1 300
PlanData buildPlan({List<String>? mealIds}) {
  final ids = mealIds ?? ['m1', 'm2'];
  return PlanData(
    version: '1.0',
    meta: PlanMeta(startedAt: '2026-09-01'),
    meals: [
      if (ids.contains('m1'))
        MealItem(id: 'm1', type: 'breakfast', name: '两个包子', time: '07:30', calories: 300, days: [3]),
      if (ids.contains('m2'))
        MealItem(id: 'm2', type: 'lunch', name: '冻豆腐虾仁荞麦面', time: '12:00', calories: 400, days: [3]),
    ],
    exercises: [
      ExerciseItem(id: 'e1', name: '快走40分钟', time: '18:30', duration: 40, caloriesBurned: 300, days: [3]),
    ],
  );
}

const String wed = '2026-09-02'; // 周三

RecordProvider newProvider() {
  SharedPreferences.setMockInitialValues({});
  return RecordProvider(StorageService.instance);
}

void main() {
group('syncDayEntries（实例化与同步规则）', () {
  test('首次实例化：计划餐/运动 → 快照（content=计划名、热量=计划值）', () async {
    final p = newProvider();
    await p.syncDayEntries(wed, buildPlan());
    final list = p.store.dayEntries[wed]!;
    expect(list.length, 3);
    final m1 = list.firstWhere((e) => e.id == 'm1');
    expect(m1.content, '两个包子');
    expect(m1.calories, 300);
    expect(m1.isPlan, true);
    final e1 = list.firstWhere((e) => e.id == 'e1');
    expect(e1.kind, 'exercise');
    expect(e1.calories, 300);
  });

  test('未脱钩跟随计划（热量未手改则跟随）', () async {
    final p = newProvider();
    await p.syncDayEntries(wed, buildPlan());
    // 计划改了早餐热量与名称
    final plan2 = PlanData(
      meta: PlanMeta(startedAt: '2026-09-01'),
      meals: [
        MealItem(id: 'm1', type: 'breakfast', name: '鸡蛋三明治', time: '07:30', calories: 350, days: [3]),
      ],
      exercises: const [],
    );
    await p.syncDayEntries(wed, plan2);
    final list = p.store.dayEntries[wed]!;
    expect(list.length, 1); // m2/e1 在 plan2 当天没有 → 未脱钩被移除
    final m1 = list.first;
    expect(m1.content, '鸡蛋三明治');
    expect(m1.calories, 350);
    expect(m1.detached, false);
  });

  test('脱钩条目永不跟随、计划删了也保留；计划外加餐原样', () async {
    final p = newProvider();
    await p.syncDayEntries(wed, buildPlan());
    // 用户把 m1 改成了黄焖鸡并保存（detached）
    final list = p.store.dayEntries[wed]!;
    final i = list.indexWhere((e) => e.id == 'm1');
    list[i] = DayEntry(
      id: 'm1', kind: 'meal', slot: 'breakfast', time: '07:30',
      content: '外卖黄焖鸡米饭', calories: 640, note: '大份',
      source: 'plan', planItemId: 'm1', detached: true, caloriesDirty: true,
    );
    await p.addDayEntry(wed, kind: 'meal', slot: 'snack', content: '奶茶', calories: 400);
    // 换新计划：m1 不在计划里了
    final plan3 = PlanData(
      meta: PlanMeta(startedAt: '2026-09-01'),
      meals: [MealItem(id: 'm9', type: 'dinner', name: '晚餐', time: '18:00', calories: 500, days: [3])],
      exercises: const [],
    );
    await p.syncDayEntries(wed, plan3);
    final out = p.store.dayEntries[wed]!;
    // 脱钩 m1 保留 + 计划外奶茶保留 + 新计划 m9 追加；m2/e1（未脱钩）被移除
    expect(out.any((e) => e.id == 'm1' && e.detached && e.content == '外卖黄焖鸡米饭'), true);
    expect(out.any((e) => e.id == '奶茶' || e.content == '奶茶'), true);
    expect(out.any((e) => e.id == 'm2'), false);
    expect(out.any((e) => e.id == 'm9'), true);
    final m1 = out.firstWhere((e) => e.id == 'm1');
    expect(m1.calories, 640);
  });
});

group('dailySummary 快照路径（历史固化）', () {
  List<DayEntry> wedEntries() => [
        DayEntry(id: 'm1', kind: 'meal', slot: 'breakfast', time: '07:30', content: '两个包子', calories: 300, source: 'plan', planItemId: 'm1'),
        DayEntry(id: 'm2', kind: 'meal', slot: 'lunch', time: '12:00', content: '荞麦面', calories: 400, source: 'plan', planItemId: 'm2'),
        DayEntry(id: 'e1', kind: 'exercise', time: '18:30', content: '快走', calories: 300, source: 'plan', planItemId: 'e1'),
        DayEntry(id: 't1', kind: 'meal', slot: 'snack', time: '15:00', content: '奶茶', calories: 400, source: 'ai', planItemId: ''),
      ];

  test('口径：计划餐打卡计入、计划运动打卡计入、加餐即计、完成度只算计划条目', () {
    final store = RecordStore(
      dayEntries: {'2026-09-02': wedEntries()},
      checkRecords: {
        '2026-09-02': {
          'meal:m1': CheckEntry(checkedAt: 1), // 只打卡了早餐
        },
      },
    );
    final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, wed);
    expect(s.taskCount, 3); // m1+m2+e1（t1 计划外不计）
    expect(s.doneCount, 1);
    expect(s.mealIntake, 300); // 只计打卡的早餐
    expect(s.tempIntake, 400); // 奶茶即计
    expect(s.exerciseBurn, 0); // e1 未打卡
    expect(s.intake, 700);
    expect(s.plannedIntake, 700);
  });

  test('历史固化核心：计划删除/清空后，历史日统计逐项不变', () {
    final store = RecordStore(
      dayEntries: {'2026-09-02': wedEntries()},
      checkRecords: {
        '2026-09-02': {'meal:m1': CheckEntry(checkedAt: 1), 'exercise:e1': CheckEntry(checkedAt: 2)},
      },
    );
    final before = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), store, wed);
    // 清空计划后重算（当前 plan 与统计无关）
    final after = dailySummary(PlanData.empty(), AppSettings(tdee: 2000, bmr: 0), store, wed);
    expect(after.mealIntake, before.mealIntake);
    expect(after.tempIntake, before.tempIntake);
    expect(after.exerciseBurn, before.exerciseBurn);
    expect(after.deficit, before.deficit);
    expect(after.taskCount, 3);
    expect(after.doneCount, 2);
    expect(after.intake, 300 + 400);
    expect(after.exerciseBurn, 300);
  });

  test('无快照日期走旧口径 fallback（未来日/未生成日不崩）', () {
    final s = dailySummary(buildPlan(), AppSettings(tdee: 2000, bmr: 0), RecordStore.empty(), '2026-09-09');
    // fallback：getTasksForDate 按当前计划投影 —— 2026-09-09 是周三，days[3] 命中 → taskCount=3
    expect(s.taskCount, 3);
    expect(s.doneCount, 0);
  });
});

group('taskProgress / dayActive（快照口径）', () {
  test('taskProgress 快照日返回计划条目进度', () {
    final store = RecordStore(
      dayEntries: {
        '2026-09-02': [
          DayEntry(id: 'm1', kind: 'meal', slot: 'breakfast', content: 'a', calories: 1, source: 'plan', planItemId: 'm1'),
          DayEntry(id: 't1', kind: 'meal', slot: 'snack', content: '加餐', calories: 1, source: 'ai', planItemId: ''),
        ],
      },
      checkRecords: {'2026-09-02': {'meal:m1': CheckEntry(checkedAt: 1)}},
    );
    final (total, done) = taskProgress(buildPlan(), store, '2026-09-02');
    expect(total, 1);
    expect(done, 1);
  });

  test('dayActive：仅有快照也算打卡天', () {
    final store = RecordStore(dayEntries: {'2026-09-02': [
      DayEntry(id: 't1', kind: 'meal', slot: 'snack', content: '奶茶', calories: 300, source: 'ai', planItemId: ''),
    ]});
    expect(dayActive(store, '2026-09-02'), true);
  });
});

group('convertLegacyToEntries（旧数据 → 快照，启动迁移/导入共用核心）', () {
  test('计划餐(含覆盖)+计划运动+临时任务 → 快照；打卡状态不转换', () {
    final converted = convertLegacyToEntries(
      plan: buildPlan(),
      checkRecords: {
        wed: {'meal:m1': {'checkedAt': 1}},
      },
      mealAdjust: {
        wed: {'meal:m1': {'calories': 350, 'note': '少个蛋'}},
      },
      tempTasks: {
        wed: [
          {'id': 't1', 'type': 'exercise', 'name': '补录跳绳', 'time': '20:00', 'calories': 200, 'source': 'manual'},
        ],
      },
      extraFoods: const {},
    );
    final list = converted[wed]!;
    expect(list.length, 4); // m1+m2+e1+临时运动
    final m1 = list.firstWhere((e) => e.id == 'm1');
    expect(m1.calories, 350);
    expect(m1.note, '少个蛋');
    expect(m1.caloriesDirty, true);
    expect(m1.detached, false);
    final t1 = list.firstWhere((e) => e.id == 't1');
    expect(t1.kind, 'exercise');
    expect(t1.isPlan, false);
    expect(t1.detached, true);
  });

  test('无记录日期不产生快照；非法日期跳过', () {
    final converted = convertLegacyToEntries(
      plan: buildPlan(),
      checkRecords: {'not-a-date': {}},
      mealAdjust: const {},
      tempTasks: const {},
      extraFoods: const {},
    );
    expect(converted, isEmpty);
  });
});
}
