import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/widgets/meal_card.dart';

void main() {
  group('AI 采纳餐食进入今日打卡后的勾选剔除与删除测试', () {
    const today = '2026-11-06';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.init();
    });

    test('采纳进入今日正餐后，取消勾选能够立即从总摄入和宏量营养中剔除，重新勾选恢复', () async {
      final provider = RecordProvider(StorageService.instance);
      provider.store.dayEntries[today] = [
        // 原有一条计划早餐，300 kcal (已打卡)
        DayEntry(
          id: 'p_breakfast',
          kind: 'meal',
          slot: 'breakfast',
          time: '08:00',
          content: '燕麦牛奶',
          calories: 300,
          protein: 15,
          carbs: 40,
          fat: 8,
          planItemId: 'item_b',
          source: 'plan',
        ),
      ];
      provider.store.checkRecords[today] = {
        'meal:item_b': CheckEntry(checkedAt: 1000),
      };

      final plan = PlanData.empty();
      final settings = AppSettings.defaults();

      // 初始：只有早餐 300 kcal
      var summary = dailySummary(plan, settings, provider.store, today);
      expect(summary.intake, 300);
      expect(summary.intakeProtein, 15);

      // 1. 用户在 AI 参谋中采纳了一顿午餐推荐（500 kcal, P:30, C:50, F:15）
      await provider.addDayEntry(
        today,
        kind: 'meal',
        content: '老乡鸡 葱油鸡+米饭半碗',
        calories: 500,
        protein: 30,
        carbs: 50,
        fat: 15,
        slot: 'lunch',
        time: '12:30',
        source: 'ai',
        autoCheck: true,
      );

      final entries = provider.store.dayEntries[today]!;
      expect(entries.length, 2);
      final adoptedLunch = entries.last;

      // 采纳后自动打卡
      expect(provider.isEntryChecked(today, adoptedLunch), isTrue);

      // 此时摄入应为 300 + 500 = 800 kcal
      summary = dailySummary(plan, settings, provider.store, today);
      expect(summary.intake, 800);
      expect(summary.intakeProtein, 45);
      expect(summary.intakeCarbs, 90);
      expect(summary.intakeFat, 23);

      // 2. 用户在今日页面取消勾选这顿午餐
      final nowChecked = await provider.toggleEntryCheck(today, adoptedLunch, plan: plan);
      expect(nowChecked, isFalse);
      expect(provider.isEntryChecked(today, adoptedLunch), isFalse);

      // 核心断言：取消勾选后，必须立即从总摄入和宏量营养中剔除，回退到 300 kcal！
      summary = dailySummary(plan, settings, provider.store, today);
      expect(summary.intake, 300);
      expect(summary.intakeProtein, 15);
      expect(summary.intakeCarbs, 40);
      expect(summary.intakeFat, 8);

      // 3. 用户重新勾选这顿午餐
      final reChecked = await provider.toggleEntryCheck(today, adoptedLunch, plan: plan);
      expect(reChecked, isTrue);
      expect(provider.isEntryChecked(today, adoptedLunch), isTrue);

      summary = dailySummary(plan, settings, provider.store, today);
      expect(summary.intake, 800);
      expect(summary.intakeProtein, 45);

      // 4. 用户点击删除这顿午餐
      await provider.removeDayEntry(today, adoptedLunch.id);
      expect(provider.store.dayEntries[today]!.length, 1);
      expect(provider.store.checkRecords[today]!.containsKey('temp:${adoptedLunch.id}'), isFalse);

      // 删除后摄入恢复为 300 kcal
      summary = dailySummary(plan, settings, provider.store, today);
      expect(summary.intake, 300);
    });

    testWidgets('MealCard 对非计划正餐显示删除按钮与打卡圈', (tester) async {
      final adoptedLunch = DayEntry(
        id: 'ai_lunch_1',
        kind: 'meal',
        slot: 'lunch',
        time: '12:00',
        content: '肯德基 原味鸡套餐',
        calories: 450,
        source: 'ai',
      );

      var deleteCalled = false;
      var checkCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MealCard(
            entry: adoptedLunch,
            checked: true,
            onDelete: () {
              deleteCalled = true;
            },
            onCheck: () {
              checkCalled = true;
            },
          ),
        ),
      ));

      // 能够找到删除按钮 (Icons.close)
      final closeIcon = find.byIcon(Icons.close);
      expect(closeIcon, findsOneWidget);
      await tester.tap(closeIcon);
      expect(deleteCalled, isTrue);

      // 能够找到打卡圈
      final checkCircle = find.byType(CheckCircle);
      expect(checkCircle, findsOneWidget);
      await tester.tap(checkCircle);
      expect(checkCalled, isTrue);
    });
  });
}
