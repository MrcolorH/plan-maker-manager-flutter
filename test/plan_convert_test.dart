/// 零门槛冷启动、空白餐卡生成、冲突检测与一键转计划测试
/// 对应测试边界：TC-01, TC-02, TC-09, TC-10, TC-11, TC-12, TC-13, TC-14, TC-16
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/services/reminder_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';

class _FakeReminderService extends ReminderService {
  _FakeReminderService() : super.forTesting();

  @override
  Future<void> fullReschedule(PlanData plan, AppSettings settings) async {}

  @override
  Future<void> ensureScheduled(PlanData plan, AppSettings settings) async {}
}

(PlanProvider, RecordProvider) createProviders() {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService.instance;
  final reminder = _FakeReminderService();
  final settingsProv = SettingsProvider(storage, reminder);
  final recordProv = RecordProvider(storage);
  final planProv = PlanProvider(storage, reminder, settingsProv, recordProv);
  return (planProv, recordProv);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('冷启动与空白餐卡生成 (TC-01, TC-02)', () {
    test('TC-01: 无计划状态下，自动注入默认早中晚三餐骨架且不计入已摄入热量', () async {
      final (planProv, recordProv) = createProviders();
      final today = todayStr();

      // 验证初始无计划
      expect(planProv.hasPlan, false);

      // 同步今天
      await recordProv.syncDayEntries(today, planProv.plan);
      final entries = recordProv.getDayEntries(today);

      // 应当生成早餐、午餐、晚餐 3 条骨架
      expect(entries.length, 3);
      final breakfast = entries.firstWhere((e) => e.slot == 'breakfast');
      final lunch = entries.firstWhere((e) => e.slot == 'lunch');
      final dinner = entries.firstWhere((e) => e.slot == 'dinner');

      expect(breakfast.time, '08:00');
      expect(breakfast.content, '');
      expect(breakfast.calories, isNull);

      expect(lunch.time, '12:00');
      expect(lunch.content, '');
      expect(lunch.calories, isNull);

      expect(dinner.time, '18:30');
      expect(dinner.content, '');
      expect(dinner.calories, isNull);

      // TC-02: 空白餐卡不产生摄入热量
      final summary = dailySummary(
        planProv.plan,
        AppSettings(),
        recordProv.store,
        today,
      );
      expect(summary.intake, 0);
      expect(summary.taskCount, 0);
    });

    test('录入食物与热量后，支持打卡并正确累加摄入热量', () async {
      final (planProv, recordProv) = createProviders();
      final today = todayStr();
      await recordProv.ensureDefaultMealEntries(today);

      final entries = recordProv.getDayEntries(today);
      final breakfast = entries.firstWhere((e) => e.slot == 'breakfast');

      // 用户录入早餐
      final updated = DayEntry(
        id: breakfast.id,
        kind: 'meal',
        slot: 'breakfast',
        time: '08:00',
        content: '两个包子一杯牛奶',
        calories: 350,
        protein: 15,
        carbs: 45,
        fat: 10,
        source: 'manual',
      );
      await recordProv.updateDayEntry(today, updated);

      // 打卡前
      expect(recordProv.isEntryChecked(today, updated), false);

      // 执行打卡
      await recordProv.toggleEntryCheck(today, updated);
      expect(recordProv.isEntryChecked(today, updated), true);

      // 摄入应计入 350 kcal
      final summary = dailySummary(
        planProv.plan,
        AppSettings(),
        recordProv.store,
        today,
      );
      expect(summary.intake, 350);
    });
  });

  group('计划冲突检测与覆盖裁剪引擎 (TC-09 ~ TC-14)', () {
    test('TC-09: 纯净无计划转计划，成功新增并初始化 startedAt', () async {
      final (planProv, _) = createProviders();
      expect(planProv.hasPlan, false);

      // 检测冲突：无冲突
      final conflicts = planProv.checkMealConflicts(
        type: 'breakfast',
        days: [1, 2, 3, 4, 5],
      );
      expect(conflicts, isEmpty);

      // 转为计划
      final newMeal = await planProv.convertSnapshotToPlan(
        type: 'breakfast',
        name: '两个包子一杯牛奶',
        time: '08:00',
        calories: 350,
        days: [1, 2, 3, 4, 5],
      );

      expect(newMeal.name, '两个包子一杯牛奶');
      expect(newMeal.days, [1, 2, 3, 4, 5]);
      expect(planProv.hasPlan, true);
      expect(planProv.plan.meals.length, 1);
      expect(planProv.plan.meta.startedAt, isNotEmpty);
    });

    test('TC-10: 同餐次工作日完全重叠，旧计划被完全覆盖移除', () async {
      final (planProv, _) = createProviders();
      // 预置旧计划：周一到周五早餐【燕麦牛奶】
      planProv.plan.meals.add(MealItem(
        id: 'old-b1',
        type: 'breakfast',
        name: '燕麦牛奶',
        time: '08:00',
        calories: 300,
        days: [1, 2, 3, 4, 5],
      ));

      // 冲突检测
      final conflicts = planProv.checkMealConflicts(
        type: 'breakfast',
        days: [1, 2, 3, 4, 5],
      );
      expect(conflicts.length, 1);
      expect(conflicts.first.existingMeal.id, 'old-b1');
      expect(conflicts.first.conflictDays, [1, 2, 3, 4, 5]);

      // 执行覆盖转计划
      final newMeal = await planProv.convertSnapshotToPlan(
        type: 'breakfast',
        name: '两个包子一杯牛奶',
        time: '08:00',
        calories: 350,
        days: [1, 2, 3, 4, 5],
      );

      // 验证结果：旧项被完全移除，仅剩新计划
      expect(planProv.plan.meals.length, 1);
      expect(planProv.plan.meals.first.id, newMeal.id);
      expect(planProv.plan.meals.first.name, '两个包子一杯牛奶');
    });

    test('TC-11: 旧计划为每天，新计划选工作日，旧计划被部分裁剪为仅周末生效', () async {
      final (planProv, _) = createProviders();
      // 预置旧计划：每天早餐【燕麦鸡蛋】(days 为空即每天)
      planProv.plan.meals.add(MealItem(
        id: 'old-daily',
        type: 'breakfast',
        name: '燕麦鸡蛋',
        time: '07:30',
        calories: 280,
        days: [], // 每天
      ));

      // 冲突检测：工作日覆盖
      final conflicts = planProv.checkMealConflicts(
        type: 'breakfast',
        days: [1, 2, 3, 4, 5],
      );
      expect(conflicts.length, 1);
      expect(conflicts.first.conflictDays, [1, 2, 3, 4, 5]);

      // 执行裁剪覆盖
      await planProv.convertSnapshotToPlan(
        type: 'breakfast',
        name: '两个包子',
        time: '08:00',
        calories: 350,
        days: [1, 2, 3, 4, 5],
      );

      // 验证结果：两个计划共存，旧项裁剪为周末 [6, 7]，新项为工作日 [1, 2, 3, 4, 5]
      expect(planProv.plan.meals.length, 2);
      final oldMeal = planProv.plan.meals.firstWhere((m) => m.id == 'old-daily');
      final newMeal = planProv.plan.meals.firstWhere((m) => m.id != 'old-daily');

      expect(oldMeal.days, [6, 7]);
      expect(newMeal.days, [1, 2, 3, 4, 5]);
    });

    test('TC-12: 旧计划仅工作日，新计划选每天，旧计划被完全覆盖', () async {
      final (planProv, _) = createProviders();
      planProv.plan.meals.add(MealItem(
        id: 'old-workdays',
        type: 'breakfast',
        name: '吐司',
        time: '08:00',
        calories: 200,
        days: [1, 2, 3, 4, 5],
      ));

      // 新计划选每天 [1..7]
      await planProv.convertSnapshotToPlan(
        type: 'breakfast',
        name: '中式大早餐',
        time: '08:00',
        calories: 450,
        days: [1, 2, 3, 4, 5, 6, 7],
      );

      expect(planProv.plan.meals.length, 1);
      expect(planProv.plan.meals.first.name, '中式大早餐');
      expect(planProv.plan.meals.first.days, isEmpty); // 每天存为 []
    });

    test('TC-13: 多项混合冲突同时清理', () async {
      final (planProv, _) = createProviders();
      // 旧早餐 A：周一、周二
      planProv.plan.meals.add(MealItem(
        id: 'old-a',
        type: 'breakfast',
        name: 'A餐',
        time: '08:00',
        calories: 200,
        days: [1, 2],
      ));
      // 旧早餐 B：周三至周五
      planProv.plan.meals.add(MealItem(
        id: 'old-b',
        type: 'breakfast',
        name: 'B餐',
        time: '08:00',
        calories: 300,
        days: [3, 4, 5],
      ));

      // 检测冲突：同时检测到 A 和 B
      final conflicts = planProv.checkMealConflicts(
        type: 'breakfast',
        days: [1, 2, 3, 4, 5],
      );
      expect(conflicts.length, 2);

      // 执行工作日覆盖
      await planProv.convertSnapshotToPlan(
        type: 'breakfast',
        name: '统一工作日早餐',
        time: '08:00',
        calories: 350,
        days: [1, 2, 3, 4, 5],
      );

      // A 和 B 均被完全清理，仅剩新项
      expect(planProv.plan.meals.length, 1);
      expect(planProv.plan.meals.first.name, '统一工作日早餐');
    });

    test('TC-14: 异餐次互不影响', () async {
      final (planProv, _) = createProviders();
      planProv.plan.meals.add(MealItem(
        id: 'lunch-1',
        type: 'lunch',
        name: '午餐',
        time: '12:00',
        calories: 500,
        days: [1, 2, 3, 4, 5],
      ));

      // 早餐选工作日，无冲突
      final conflicts = planProv.checkMealConflicts(
        type: 'breakfast',
        days: [1, 2, 3, 4, 5],
      );
      expect(conflicts, isEmpty);
    });
  });

  group('打卡状态平滑迁移 (TC-16)', () {
    test('TC-16: 条目转计划后，旧 temp: 打卡状态迁移至新 meal: 键，打卡状态保持', () async {
      final (_, recordProv) = createProviders();
      final today = todayStr();

      final entry = DayEntry(
        id: 'temp-breakfast-01',
        kind: 'meal',
        slot: 'breakfast',
        time: '08:00',
        content: '热干面',
        calories: 400,
        source: 'manual',
      );
      await recordProv.addDayEntry(
        today,
        kind: entry.kind,
        slot: entry.slot,
        time: entry.time,
        content: entry.content,
        calories: entry.calories,
      );

      // 用户打卡
      final oldKey = recordProv.checkKeyOf(entry);
      expect(oldKey, 'temp:temp-breakfast-01');
      await recordProv.toggleCheck(today, 'temp', 'temp-breakfast-01');
      expect(recordProv.isChecked(today, 'temp', 'temp-breakfast-01'), true);

      // 执行迁移到新计划项 'meal:new-plan-id'
      await recordProv.migrateEntryCheck(
        date: today,
        oldCheckKey: 'temp:temp-breakfast-01',
        newCheckKey: 'meal:new-plan-id',
      );

      // 验证旧键已清除，新键处于已打卡态
      expect(recordProv.isChecked(today, 'temp', 'temp-breakfast-01'), false);
      expect(recordProv.isChecked(today, 'meal', 'new-plan-id'), true);
    });
  });

  group('设为日常计划防重与存量脏数据智能合并 (TC-17 ~ TC-19)', () {
    test('TC-17: 设为日常计划时原子升级快照，今日有且仅有 1 条计划快照，打卡绝不重复计算热量', () async {
      final (planProv, recordProv) = createProviders();
      final today = todayStr();

      // 用户今天录入了一个午餐
      await recordProv.addDayEntry(
        today,
        kind: 'meal',
        slot: 'lunch',
        time: '12:00',
        content: '两个汉堡',
        calories: 600,
        autoCheck: false,
      );

      final entriesBefore = recordProv.getDayEntries(today);
      expect(entriesBefore.length, 1);
      final initialEntry = entriesBefore.first;
      expect(recordProv.isEntryChecked(today, initialEntry), false);

      // 用户点击打卡
      await recordProv.toggleEntryCheck(today, initialEntry);
      expect(recordProv.isEntryChecked(today, initialEntry), true);

      // 用户点击「设为日常计划」（每天执行）
      final newMeal = await planProv.convertSnapshotToPlan(
        type: 'lunch',
        name: '两个汉堡',
        time: '12:00',
        calories: 600,
        days: [1, 2, 3, 4, 5, 6, 7],
        sourceSnapshotDate: today,
        sourceSnapshotEntryId: initialEntry.id,
      );

      // 验证 1：今日快照列表有且仅有 1 条该午餐条目，绝无第二条重复计划！
      final entriesAfter = recordProv.getDayEntries(today);
      final lunchEntries = entriesAfter.where((e) => e.kind == 'meal' && e.slot == 'lunch').toList();
      expect(lunchEntries.length, 1, reason: '今日午餐必须有且仅有 1 条，不能产生重复计划');
      expect(lunchEntries.first.planItemId, newMeal.id);
      expect(lunchEntries.first.isPlan, true);

      // 验证 2：打卡状态迁移至新计划项，且依然处于打卡状态
      expect(recordProv.isEntryChecked(today, lunchEntries.first), true);

      // 验证 3：今日热量摄入计算恰好为 600 kcal，绝不重复计算翻倍！
      final summary = dailySummary(planProv.plan, AppSettings(), recordProv.store, today);
      expect(summary.mealIntake, 600, reason: '已打卡热量摄入只能计算一次 600 kcal，绝不能翻倍为 1200 kcal');
      expect(summary.taskCount, 1);
      expect(summary.doneCount, 1);
    });

    test('TC-18: 存量脏数据（今日已存在两个相同 planItemId 的计划项）经 syncDayEntries 自动智能合并', () async {
      final (planProv, recordProv) = createProviders();
      final today = todayStr();

      final meal = MealItem(
        id: 'm-dup-01',
        type: 'lunch',
        name: '两个汉堡',
        time: '12:00',
        calories: 600,
        days: [1, 2, 3, 4, 5, 6, 7],
      );
      planProv.plan.meals.add(meal);

      // 人为在今日放入 2 个指向同一个日常计划项的重复条目（模拟线上发生过的脏数据）
      recordProv.store.dayEntries[today] = [
        DayEntry(
          id: 'dup-1',
          kind: 'meal',
          slot: 'lunch',
          time: '12:00',
          content: '两个汉堡（自定义）',
          calories: 650, // 手改过热量
          source: 'plan',
          planItemId: 'm-dup-01',
          caloriesDirty: true,
        ),
        DayEntry(
          id: 'm-dup-01',
          kind: 'meal',
          slot: 'lunch',
          time: '12:00',
          content: '两个汉堡',
          calories: 600,
          source: 'plan',
          planItemId: 'm-dup-01',
        ),
      ];

      // 给其中一个打上卡
      recordProv.store.checkRecords[today] = {
        'meal:m-dup-01': CheckEntry(checkedAt: 123456),
      };

      // 触发 syncDayEntries
      await recordProv.syncDayEntries(today, planProv.plan);

      // 验证 1：自动去重合并为 1 条
      final entries = recordProv.getDayEntries(today);
      expect(entries.length, 1, reason: '同一 planItemId 的重复条目必须被自动清洗合并为 1 条');
      final merged = entries.first;
      expect(merged.planItemId, 'm-dup-01');
      expect(merged.calories, 650, reason: '保留手改过的自定义有效数值');
      expect(merged.caloriesDirty, true);

      // 验证 2：打卡状态完好保持
      expect(recordProv.isEntryChecked(today, merged), true);

      // 验证 3：热量摄入计算正常（为 650，绝不叠加成 1250）
      final summary = dailySummary(planProv.plan, AppSettings(), recordProv.store, today);
      expect(summary.mealIntake, 650);
      expect(summary.taskCount, 1);
      expect(summary.doneCount, 1);
    });

    test('TC-19: 正餐已有日常计划快照时，未填写的空白正餐骨架被自动清理', () async {
      final (planProv, recordProv) = createProviders();
      final today = todayStr();

      // 计划中制定了日常晚餐
      planProv.plan.meals.add(MealItem(
        id: 'm-dinner-01',
        type: 'dinner',
        name: '鸡胸肉沙拉',
        time: '18:30',
        calories: 350,
        days: [1, 2, 3, 4, 5, 6, 7],
      ));

      // 今日既有空白晚餐骨架，又有其他条目
      recordProv.store.dayEntries[today] = [
        DayEntry(
          id: 'blank-dinner',
          kind: 'meal',
          slot: 'dinner',
          time: '18:30',
          content: '',
          calories: null,
          source: 'manual',
        ),
      ];

      // 触发 syncDayEntries
      await recordProv.syncDayEntries(today, planProv.plan);

      // 验证空白骨架被日常计划快照替换，晚餐仅有 1 条
      final entries = recordProv.getDayEntries(today);
      expect(entries.length, 1);
      expect(entries.first.content, '鸡胸肉沙拉');
      expect(entries.first.calories, 350);
      expect(entries.first.isPlan, true);
    });
  });
}
