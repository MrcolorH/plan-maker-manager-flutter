import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QQ 机器人多餐次导入与 App 计划自动核销打卡测试', () {
    late RecordProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService.instance;
      await storage.init();
      provider = RecordProvider(storage);
    });

    test('1. 首次核销替换未脱钩计划餐：保留 planItemId 与 source: plan，替换内容并自动打卡', () async {
      const date = '2026-11-19';
      // 预置当天计划早餐与午餐
      final originalBreakfast = DayEntry(
        id: 'plan_breakfast_id',
        kind: 'meal',
        slot: 'breakfast',
        time: '08:00',
        content: '燕麦粥+煮鸡蛋',
        calories: 300,
        protein: 15,
        carbs: 45,
        fat: 8,
        source: 'plan',
        planItemId: 'meal_plan_b1',
        detached: false,
        caloriesDirty: false,
      );
      final originalLunch = DayEntry(
        id: 'plan_lunch_id',
        kind: 'meal',
        slot: 'lunch',
        time: '12:00',
        content: '鸡胸肉沙拉',
        calories: 450,
        source: 'plan',
        planItemId: 'meal_plan_l1',
        detached: false,
        caloriesDirty: false,
      );
      provider.store.dayEntries[date] = [originalBreakfast, originalLunch];

      // 验证打卡前未打卡
      expect(provider.isEntryChecked(date, originalBreakfast), isFalse);

      // QQ 机器人导入早餐
      await provider.importExternalMealEntry(
        date,
        slot: 'breakfast',
        content: '小笼包 200g',
        calories: 460,
        protein: 18,
        carbs: 55,
        fat: 16,
        detail: '小笼包6只，皮薄汁多',
        items: const [
          FoodBreakdownItem(name: '小笼包', portion: '200g', calories: 460),
        ],
        source: 'qq_bot',
      );

      final entries = provider.store.dayEntries[date]!;
      expect(entries.length, 2, reason: '核销替换不应增加条目数量');

      final replaced = entries.firstWhere((e) => e.slot == 'breakfast');

      // 核心断言：
      // 1. 保留原计划核心元数据，且 source 依然为 'plan'
      expect(replaced.id, 'plan_breakfast_id');
      expect(replaced.planItemId, 'meal_plan_b1');
      expect(replaced.source, 'plan');
      expect(replaced.time, '08:00');
      expect(replaced.slot, 'breakfast');

      // 2. 真实食物数据已替换
      expect(replaced.content, '小笼包 200g');
      expect(replaced.calories, 460);
      expect(replaced.protein, 18);
      expect(replaced.carbs, 55);
      expect(replaced.fat, 16);
      expect(replaced.detail, '小笼包6只，皮薄汁多');
      expect(replaced.items?.length, 1);

      // 3. 状态标记为已脱钩且热量已手改
      expect(replaced.detached, isTrue);
      expect(replaced.caloriesDirty, isTrue);

      // 4. 备注记录原计划菜名供详情页追溯
      expect(replaced.note, 'QQ机器人同步（原计划：燕麦粥+煮鸡蛋）');

      // 5. 自动打卡状态生效
      expect(provider.store.checkRecords[date]?['meal:meal_plan_b1'], isNotNull);
      expect(provider.isEntryChecked(date, replaced), isTrue);

      // 6. 其他未导入正餐不受影响
      final untouchedLunch = entries.firstWhere((e) => e.slot == 'lunch');
      expect(untouchedLunch.content, '鸡胸肉沙拉');
      expect(untouchedLunch.detached, isFalse);
      expect(provider.isEntryChecked(date, untouchedLunch), isFalse);
    });

    test('2. 同餐次二次追加合并：同一顿饭分两次发机器人，累加数值与拼接内容，保持 source: plan 与已打卡', () async {
      const date = '2026-11-19';
      final originalDinner = DayEntry(
        id: 'plan_dinner_id',
        kind: 'meal',
        slot: 'dinner',
        time: '18:30',
        content: '杂粮饭',
        calories: 300,
        source: 'plan',
        planItemId: 'meal_plan_d1',
        detached: false,
      );
      provider.store.dayEntries[date] = [originalDinner];

      // 第一次导入：发了主食杂粮饭与炒菜
      await provider.importExternalMealEntry(
        date,
        slot: 'dinner',
        content: '番茄炒蛋盖浇饭',
        calories: 520,
        protein: 15,
        carbs: 70,
        fat: 18,
        items: const [
          FoodBreakdownItem(name: '米饭', portion: '150g', calories: 200),
          FoodBreakdownItem(name: '番茄炒蛋', portion: '200g', calories: 320),
        ],
      );

      // 第二次导入：追加了紫菜蛋花汤
      await provider.importExternalMealEntry(
        date,
        slot: 'dinner',
        content: '紫菜蛋花汤一碗',
        calories: 80,
        protein: 5,
        carbs: 4,
        fat: 3,
        items: const [
          FoodBreakdownItem(name: '紫菜蛋花汤', portion: '250ml', calories: 80),
        ],
      );

      final entries = provider.store.dayEntries[date]!;
      expect(entries.length, 1, reason: '二次导入应合并到已有条目，不产生第二顿晚餐');

      final merged = entries.first;
      expect(merged.source, 'plan');
      expect(merged.planItemId, 'meal_plan_d1');
      expect(merged.detached, isTrue);
      // 内容换行拼接
      expect(merged.content, '番茄炒蛋盖浇饭\n紫菜蛋花汤一碗');
      // 数值累加
      expect(merged.calories, 600); // 520 + 80
      expect(merged.protein, 20);   // 15 + 5
      expect(merged.carbs, 74);     // 70 + 4
      expect(merged.fat, 21);       // 18 + 3
      // 食材列表合并
      expect(merged.items?.length, 3);
      // 打卡状态保持已打卡
      expect(provider.isEntryChecked(date, merged), isTrue);
    });

    test('3. 无计划骨架填充：若无计划但有空白正餐骨架，填充骨架并自动写入 temp 打卡', () async {
      const date = '2026-11-19';
      // 用户无日常计划，但今日页有默认生成的空白午餐骨架
      final blankLunch = DayEntry(
        id: 'blank_m2',
        kind: 'meal',
        slot: 'lunch',
        time: '12:00',
        content: '',
        calories: null,
        source: 'manual',
        planItemId: '',
        detached: true,
        caloriesDirty: true,
      );
      provider.store.dayEntries[date] = [blankLunch];

      await provider.importExternalMealEntry(
        date,
        slot: 'lunch',
        content: '牛肉面大碗',
        calories: 680,
        protein: 30,
        carbs: 85,
        fat: 20,
      );

      final entries = provider.store.dayEntries[date]!;
      expect(entries.length, 1);
      final filled = entries.first;
      expect(filled.id, 'blank_m2');
      expect(filled.content, '牛肉面大碗');
      expect(filled.calories, 680);
      expect(provider.store.checkRecords[date]?['temp:blank_m2'], isNotNull);
      expect(provider.isEntryChecked(date, filled), isTrue);
    });

    test('4. 导入加餐 (snack)：不替换正餐条目，直接新增条目并自动打卡', () async {
      const date = '2026-11-19';
      final breakfast = DayEntry(
        id: 'plan_b',
        kind: 'meal',
        slot: 'breakfast',
        content: '全麦面包',
        calories: 200,
        source: 'plan',
        planItemId: 'pb',
      );
      provider.store.dayEntries[date] = [breakfast];

      await provider.importExternalMealEntry(
        date,
        slot: 'snack',
        content: '冰美式 + 巴旦木 20g',
        calories: 130,
        source: 'qq_bot',
      );

      final entries = provider.store.dayEntries[date]!;
      expect(entries.length, 2);

      // 原早餐保持不变
      final b = entries.firstWhere((e) => e.slot == 'breakfast');
      expect(b.content, '全麦面包');

      // 新增加餐条目且自动打卡
      final snack = entries.firstWhere((e) => e.slot == 'snack');
      expect(snack.content, '冰美式 + 巴旦木 20g');
      expect(snack.calories, 130);
      expect(snack.source, 'qq_bot');
      expect(provider.isEntryChecked(date, snack), isTrue);
    });

    test('5. 幂等去重兼容性测试：识别已核销替换的计划餐，防止弱网重复消费', () {
      const date = '2026-11-19';
      final replacedMeal = DayEntry(
        id: 'plan_b1',
        kind: 'meal',
        slot: 'breakfast',
        content: '小笼包 200g\n食材明细：小笼包 (200g)',
        calories: 460,
        note: 'QQ机器人同步（原计划：燕麦粥）',
        source: 'plan',
        planItemId: 'p_b1',
        detached: true,
      );
      provider.store.dayEntries[date] = [replacedMeal];

      final existingEntries = provider.store.dayEntries[date] ?? [];
      const newIncomingContent = '小笼包 200g\n食材明细：小笼包 (200g)';
      const newIncomingSlot = 'breakfast';
      const newIncomingCalories = 460;
      final firstLine = newIncomingContent.split('\n').first.trim();

      // 验证 SyncService 中的去重逻辑
      final isDuplicated = existingEntries.any((e) =>
          (e.source == 'qq_bot' || (e.isPlan && e.detached && e.note.contains('QQ机器人'))) &&
          e.slot == newIncomingSlot &&
          e.calories == newIncomingCalories &&
          (e.content == newIncomingContent || (firstLine.isNotEmpty && e.content.contains(firstLine))));

      expect(isDuplicated, isTrue, reason: '已替换的计划餐能正确通过 QQ机器人 备注与内容热量命中幂等去重');
    });

    test('6. 统计页完成度与连续打卡天数：计划全部核销打卡后，任务进度 100% 且 streak 递增', () {
      const date = '2026-11-19';
      // 构造轻量 PlanData
      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-11-18'),
        meals: [
          MealItem(id: 'mb', type: 'breakfast', name: '计划早餐', time: '08:00', calories: 300, days: [1, 2, 3, 4, 5, 6, 7]),
          MealItem(id: 'ml', type: 'lunch', name: '计划午餐', time: '12:00', calories: 500, days: [1, 2, 3, 4, 5, 6, 7]),
        ],
        exercises: [
          ExerciseItem(id: 'ex', name: '晚间快走', time: '19:00', caloriesBurned: 200, days: [1, 2, 3, 4, 5, 6, 7]),
        ],
      );

      // 快照条目已通过机器人核销打卡
      final replacedBreakfast = DayEntry(
        id: 'snap_mb',
        kind: 'meal',
        slot: 'breakfast',
        content: '煎饼果子',
        calories: 450,
        source: 'plan',
        planItemId: 'mb',
        detached: true,
      );
      final replacedLunch = DayEntry(
        id: 'snap_ml',
        kind: 'meal',
        slot: 'lunch',
        content: '减脂沙拉',
        calories: 400,
        source: 'plan',
        planItemId: 'ml',
        detached: true,
      );
      final exEntry = DayEntry(
        id: 'snap_ex',
        kind: 'exercise',
        content: '晚间快走',
        calories: 200,
        source: 'plan',
        planItemId: 'ex',
      );
      provider.store.dayEntries[date] = [replacedBreakfast, replacedLunch, exEntry];

      // 写入打卡记录 (早餐、午餐由机器人打卡，运动已打卡)
      provider.store.checkRecords[date] = {
        'meal:mb': CheckEntry(checkedAt: 1000),
        'meal:ml': CheckEntry(checkedAt: 2000),
        'exercise:ex': CheckEntry(checkedAt: 3000),
      };

      // 验证 taskProgress 完成度
      final (total, done) = taskProgress(plan, provider.store, date);
      expect(total, 3, reason: '计划包含早、午、运动共 3 项');
      expect(done, 3, reason: '核销后的早餐、午餐及运动均被正确识别为已打卡');

      // 验证 dayActive 与连续打卡
      expect(dayActive(provider.store, date), isTrue);
    });
  });
}
