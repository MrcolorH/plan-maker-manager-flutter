import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/services/ai_service.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';
import 'package:jianfei_dazi/utils/weekly_report_utils.dart';
import 'package:jianfei_dazi/widgets/exercise_breakdown_table.dart';

void main() {
  group('运动拆解表格与解析测试 (对标饮食保持一致)', () {
    test('parseBreakdownFromText 能够准确解析运动分项拆解文本', () {
      const text1 = '室外慢跑25分钟≈200，哑铃弯举4组≈50，全身拉伸10分钟≈30，合计280';
      final list1 = AiService.parseBreakdownFromText(text1);
      expect(list1.length, 3);
      expect(list1[0].name, '室外慢跑');
      expect(list1[0].portion, '25分钟');
      expect(list1[0].calories, 200);

      expect(list1[1].name, '哑铃弯举');
      expect(list1[1].portion, '4组');
      expect(list1[1].calories, 50);

      expect(list1[2].name, '全身拉伸');
      expect(list1[2].portion, '10分钟');
      expect(list1[2].calories, 30);
    });

    test('parseBreakdownItems 能够从 JSON 数组中提取运动子项', () {
      final rawItems = [
        {'name': '跑步机慢跑', 'portion': '30分钟', 'calories': 220},
        {'name': '平板支撑', 'portion': '3组', 'calories': 40},
      ];
      final items = AiService.parseBreakdownItems(rawItems, null);
      expect(items.length, 2);
      expect(items[0].name, '跑步机慢跑');
      expect(items[0].portion, '30分钟');
      expect(items[0].calories, 220);
      expect(items[1].name, '平板支撑');
      expect(items[1].portion, '3组');
      expect(items[1].calories, 40);
    });

    test('DayEntry(kind: exercise) 能够正确序列化与反序列化 items 和 detail', () {
      final entry = DayEntry(
        id: 'test_ex1',
        kind: 'exercise',
        time: '19:30',
        content: '晚上健身房训练',
        calories: 310,
        note: '状态不错',
        source: 'manual',
        detached: true,
        caloriesDirty: true,
        detail: '跑步机30分钟≈220，深蹲4组≈60，拉伸10分钟≈30，合计310',
        items: const [
          FoodBreakdownItem(name: '跑步机', portion: '30分钟', calories: 220),
          FoodBreakdownItem(name: '深蹲', portion: '4组', calories: 60),
          FoodBreakdownItem(name: '拉伸', portion: '10分钟', calories: 30),
        ],
      );

      final json = entry.toJson();
      expect(json['kind'], 'exercise');
      expect(json['detail'], isNotNull);
      expect(json['items'], isA<List>());
      expect((json['items'] as List).length, 3);

      final restored = DayEntry.fromJson(json);
      expect(restored.id, 'test_ex1');
      expect(restored.kind, 'exercise');
      expect(restored.content, '晚上健身房训练');
      expect(restored.detail, entry.detail);
      expect(restored.items, isNotNull);
      expect(restored.items!.length, 3);
      expect(restored.items![0].name, '跑步机');
      expect(restored.items![0].portion, '30分钟');
      expect(restored.items![0].calories, 220);
      expect(restored.items![1].name, '深蹲');
      expect(restored.items![1].portion, '4组');
      expect(restored.items![1].calories, 60);
      expect(restored.items![2].name, '拉伸');
      expect(restored.items![2].portion, '10分钟');
      expect(restored.items![2].calories, 30);
    });

    test('weekly_report_utils 正确从运动 items 中提取子项目名称', () {
      final today = todayStr();
      final wd = parseDate(today).weekday;
      final monday = addDays(today, -(wd - 1));

      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(planName: '测试计划', dailyCalorieTarget: 1500),
      );
      final settings = AppSettings(bmr: 1400, tdee: 1680, dailyCalorieTarget: 1500);
      final profile = UserProfile(gender: 'male', age: 28, height: 175, weight: 70);

      final store = RecordStore();
      store.dayEntries[monday] = [
        DayEntry(
          id: 'e1',
          kind: 'exercise',
          content: '综合体能',
          calories: 250,
          items: const [
            FoodBreakdownItem(name: '跳绳', portion: '800个', calories: 120),
            FoodBreakdownItem(name: '波比跳', portion: '30个', calories: 130),
          ],
        ),
      ];

      final stats = calculateWeeklyReportStats(
        plan: plan,
        settings: settings,
        records: store,
        profile: profile,
        weekOffset: 0,
      );

      expect(stats.exerciseDays, 1);
      expect(stats.totalExerciseBurn, 250);
      expect(stats.exerciseNames.contains('跳绳'), true);
      expect(stats.exerciseNames.contains('波比跳'), true);
    });

    testWidgets('ExerciseBreakdownTable 正常渲染运动项目、时长及消耗', (tester) async {
      const testItems = [
        FoodBreakdownItem(name: '室外慢跑', portion: '25分钟', calories: 200),
        FoodBreakdownItem(name: '哑铃弯举', portion: '4组', calories: 50),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExerciseBreakdownTable(
              items: testItems,
              totalCalories: 250,
            ),
          ),
        ),
      );

      expect(find.text('运动项目'), findsOneWidget);
      expect(find.text('时长 / 运动量'), findsOneWidget);
      expect(find.text('预估消耗'), findsOneWidget);
      expect(find.text('室外慢跑'), findsOneWidget);
      expect(find.text('25分钟'), findsOneWidget);
      expect(find.text('-200 kcal'), findsOneWidget);
      expect(find.text('哑铃弯举'), findsOneWidget);
      expect(find.text('4组'), findsOneWidget);
      expect(find.text('-50 kcal'), findsOneWidget);
      expect(find.text('合计消耗'), findsOneWidget);
      expect(find.text('-250 kcal'), findsOneWidget);
    });
  });
}
