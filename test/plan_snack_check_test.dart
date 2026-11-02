import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/widgets/meal_card.dart';

RecordProvider createRecordProvider() {
  SharedPreferences.setMockInitialValues({});
  return RecordProvider(StorageService.instance);
}

void main() {
  group('计划加餐 vs 临时加餐 打卡状态测试', () {
    const testDate = '2026-09-02'; // 周三

    test('计划中的加餐导入后默认绝不处于打卡状态，且支持用户主动打卡/取消打卡', () async {
      final provider = createRecordProvider();

      // 构建包含加餐的计划（days=[3] 即周三）
      final planWithSnack = PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [
          MealItem(
            id: 'm_breakfast',
            type: 'breakfast',
            name: '燕麦粥',
            time: '08:00',
            calories: 250,
            days: [3],
          ),
          MealItem(
            id: 'm_snack',
            type: 'snack',
            name: '下午茶黑咖啡加坚果',
            time: '15:30',
            calories: 180,
            days: [3],
          ),
        ],
      );

      // 同步生成当日快照
      await provider.syncDayEntries(testDate, planWithSnack);
      final entries = provider.getDayEntries(testDate);
      expect(entries.length, 2);

      final planSnack = entries.firstWhere((e) => e.planItemId == 'm_snack');
      expect(planSnack.isPlan, isTrue);
      expect(planSnack.slot, 'snack');
      expect(planSnack.content, '下午茶黑咖啡加坚果');

      // 核心断言 1：计划中的加餐是计划类任务，用户未打卡时，isEntryChecked 必须为 false！
      expect(
        provider.isEntryChecked(testDate, planSnack),
        isFalse,
        reason: '从计划中导入的加餐，每一个都必须默认是不打卡状态',
      );

      // 核心断言 2：用户点击打卡后，状态变为已打卡
      await provider.toggleEntryCheck(testDate, planSnack);
      expect(
        provider.isEntryChecked(testDate, planSnack),
        isTrue,
        reason: '用户打卡后，计划加餐应变为已打卡',
      );

      // 核心断言 3：用户再次点击取消打卡，状态变回未打卡
      await provider.toggleEntryCheck(testDate, planSnack);
      expect(
        provider.isEntryChecked(testDate, planSnack),
        isFalse,
        reason: '用户取消打卡后，计划加餐应恢复未打卡',
      );
    });

    test('计划外临时加餐录入即事实，恒为已打卡状态', () async {
      final provider = createRecordProvider();

      // 用户在今日手动添加临时加餐（如点选今日加餐）
      await provider.addDayEntry(
        testDate,
        kind: 'meal',
        slot: 'snack',
        content: '临时下午茶奶茶',
        calories: 320,
      );

      final entries = provider.getDayEntries(testDate);
      expect(entries.length, 1);

      final tempSnack = entries.first;
      expect(tempSnack.isPlan, isFalse);
      expect(tempSnack.slot, 'snack');

      // 临时加餐吃了才录入，天然恒为已打卡
      expect(provider.isEntryChecked(testDate, tempSnack), isTrue);
    });
  });

  group('MealCard UI 表现测试', () {
    testWidgets('计划加餐显示「加餐」绿色标签与打卡圆圈，不显示「今日加」与删除叉号', (tester) async {
      final planSnackEntry = DayEntry(
        id: 'ps_1',
        kind: 'meal',
        slot: 'snack',
        time: '15:30',
        content: '无糖希腊酸奶',
        calories: 120,
        source: 'plan',
        planItemId: 'item_snack_1',
      );

      var checkToggled = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MealCard(
            entry: planSnackEntry,
            checked: false,
            onCheck: () => checkToggled = true,
          ),
        ),
      ));

      // 应该展示「加餐」标签
      expect(find.text('加餐'), findsOneWidget);
      // 绝不展示临时加餐的「今日加」标签
      expect(find.text('今日加'), findsNothing);

      // 应该展示打卡圆形图标 CheckCircle
      expect(find.byType(CheckCircle), findsOneWidget);
      // 绝不展示临时加餐的删除图标 Icons.close
      expect(find.byIcon(Icons.close), findsNothing);

      // 点击打卡圆圈触发 onCheck
      await tester.tap(find.byType(CheckCircle));
      expect(checkToggled, isTrue);
    });

    testWidgets('计划外临时加餐显示「今日加」橙色标签与删除按钮，不显示打卡圆圈', (tester) async {
      final tempSnackEntry = DayEntry(
        id: 'ts_1',
        kind: 'meal',
        slot: 'snack',
        time: '16:00',
        content: '蓝莓 100g',
        calories: 60,
        source: 'manual',
        planItemId: '',
      );

      var deleteTriggered = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MealCard(
            entry: tempSnackEntry,
            checked: true,
            onDelete: () => deleteTriggered = true,
          ),
        ),
      ));

      // 应该展示「今日加」标签
      expect(find.text('今日加'), findsOneWidget);
      // 应该展示删除按钮 Icons.close
      expect(find.byIcon(Icons.close), findsOneWidget);
      // 临时加餐不展示打卡圆圈 CheckCircle
      expect(find.byType(CheckCircle), findsNothing);

      // 点击删除按钮触发 onDelete
      await tester.tap(find.byIcon(Icons.close));
      expect(deleteTriggered, isTrue);
    });
  });
}
