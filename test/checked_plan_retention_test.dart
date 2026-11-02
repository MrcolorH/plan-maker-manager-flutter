import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';

RecordProvider createRecordProvider() {
  SharedPreferences.setMockInitialValues({});
  return RecordProvider(StorageService.instance);
}

void main() {
  group('已确认打卡的计划条目防误删与更新保护测试', () {
    const today = '2026-09-02'; // 周三

    test('已打卡的计划项在删除计划时坚决保留，不随计划删除而消失', () async {
      final provider = createRecordProvider();

      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [
          MealItem(
            id: 'm_breakfast',
            type: 'breakfast',
            name: '全麦面包+煎蛋',
            time: '08:00',
            calories: 300,
            days: [3],
          ),
          MealItem(
            id: 'm_lunch',
            type: 'lunch',
            name: '鸡胸肉荞麦面',
            time: '12:00',
            calories: 450,
            days: [3],
          ),
        ],
      );

      // 1. 同步生成当日快照
      await provider.syncDayEntries(today, plan);
      var entries = provider.getDayEntries(today);
      expect(entries.length, 2);

      final breakfast = entries.firstWhere((e) => e.planItemId == 'm_breakfast');

      // 2. 用户早晨吃了早餐并打卡确认
      await provider.toggleEntryCheck(today, breakfast);
      expect(provider.isEntryChecked(today, breakfast), isTrue);

      // 3. 用户在计划中删除了该早餐计划
      plan.meals.removeWhere((m) => m.id == 'm_breakfast');

      // 4. 再次触发同步
      await provider.syncDayEntries(today, plan);
      entries = provider.getDayEntries(today);

      // 核心断言：已打卡的早餐必须仍然保留在今日快照中！打卡即事实，绝不能被删除
      final preservedBreakfast = entries.where((e) => e.planItemId == 'm_breakfast').toList();
      expect(
        preservedBreakfast.isNotEmpty,
        isTrue,
        reason: '已经确认打卡的计划条目是今日既定事实，删除长期计划时绝不能把今日对应条目删除',
      );
      expect(preservedBreakfast.first.content, '全麦面包+煎蛋');
      expect(preservedBreakfast.first.calories, 300);
      expect(provider.isEntryChecked(today, preservedBreakfast.first), isTrue);

      // 未打卡的午餐如果被删除则正常移除
      plan.meals.removeWhere((m) => m.id == 'm_lunch');
      await provider.syncDayEntries(today, plan);
      entries = provider.getDayEntries(today);
      expect(entries.any((e) => e.planItemId == 'm_lunch'), isFalse);
    });

    test('已打卡的计划项在修改计划时不被覆盖，取消打卡后最新计划才生效', () async {
      final provider = createRecordProvider();

      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [
          MealItem(
            id: 'm_lunch',
            type: 'lunch',
            name: '轻食沙拉',
            time: '12:00',
            calories: 350,
            days: [3],
          ),
        ],
      );

      // 1. 同步生成当日快照并打卡
      await provider.syncDayEntries(today, plan);
      var lunch = provider.getDayEntries(today).first;
      await provider.toggleEntryCheck(today, lunch);
      expect(provider.isEntryChecked(today, lunch), isTrue);

      // 2. 用户在长期计划中把午餐修改成了大餐
      plan.meals[0] = MealItem(
        id: 'm_lunch',
        type: 'lunch',
        name: '安格斯牛排套餐',
        time: '12:30',
        calories: 750,
        days: [3],
      );

      // 3. 计划修改后同步
      await provider.syncDayEntries(today, plan);
      lunch = provider.getDayEntries(today).first;

      // 核心断言 1：因为今日已经打卡，已打卡内容不能被新计划覆盖！依然是吃过的轻食沙拉
      expect(lunch.content, '轻食沙拉');
      expect(lunch.calories, 350);
      expect(provider.isEntryChecked(today, lunch), isTrue);

      // 4. 用户若想让计划修改生效，取消打卡
      final nowChecked = await provider.toggleEntryCheck(today, lunch, plan: plan);
      expect(nowChecked, isFalse);

      // 核心断言 2：取消打卡后，最新计划立即对今日生效（变为安格斯牛排套餐），等待用户重新打卡
      lunch = provider.getDayEntries(today).first;
      expect(lunch.content, '安格斯牛排套餐');
      expect(lunch.calories, 750);
      expect(provider.isEntryChecked(today, lunch), isFalse);

      // 5. 用户重新打卡最新修改后的计划
      await provider.toggleEntryCheck(today, lunch, plan: plan);
      expect(provider.isEntryChecked(today, lunch), isTrue);
    });

    test('已打卡条目在计划删除后若被取消打卡，该已删除计划项从今日移除', () async {
      final provider = createRecordProvider();

      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [
          MealItem(
            id: 'm_snack',
            type: 'snack',
            name: '每日坚果',
            time: '15:00',
            calories: 160,
            days: [3],
          ),
        ],
      );

      await provider.syncDayEntries(today, plan);
      var snack = provider.getDayEntries(today).first;
      await provider.toggleEntryCheck(today, snack);
      expect(provider.isEntryChecked(today, snack), isTrue);

      // 计划中删除了该加餐
      plan.meals.clear();
      await provider.syncDayEntries(today, plan);

      // 因为已打卡，依然被保护保留
      expect(provider.getDayEntries(today).any((e) => e.planItemId == 'm_snack'), isTrue);

      // 用户取消打卡
      await provider.toggleEntryCheck(today, snack, plan: plan);

      // 取消打卡后，由于计划中已无此项，该项被正式从今日清理
      expect(provider.getDayEntries(today).any((e) => e.planItemId == 'm_snack'), isFalse);
    });
  });
}
