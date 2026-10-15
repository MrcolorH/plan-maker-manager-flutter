/// 周度减脂复盘报告单元与组件测试
/// 测试本地统计计算、Prompt组装、AI建议解析、Markdown报告生成与海报卡片渲染
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/models/weight.dart';
import 'package:jianfei_dazi/services/ai_service.dart';
import 'package:jianfei_dazi/theme/app_theme.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';
import 'package:jianfei_dazi/utils/weekly_report_utils.dart';
import 'package:jianfei_dazi/widgets/weekly_report_poster.dart';

void main() {
  group('WeeklyReportStats 本地数据统计测试', () {
    test('正确聚合 7 天体重、缺口、宏量营养素与打卡率', () {
      final today = todayStr();
      final wd = parseDate(today).weekday;
      final monday = addDays(today, -(wd - 1));

      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(
          planName: '减脂冲刺计划',
          startedAt: monday,
          dailyCalorieTarget: 1500,
          targetProtein: 80,
          targetCarbs: 150,
          targetFat: 45,
        ),
        meals: [
          MealItem(id: 'm1', name: '减脂早餐', time: '07:30', calories: 350, protein: 25, carbs: 40, fat: 10, days: [1, 2, 3, 4, 5, 6, 7]),
          MealItem(id: 'm2', name: '鸡胸午餐', time: '12:00', calories: 500, protein: 40, carbs: 60, fat: 12, days: [1, 2, 3, 4, 5, 6, 7]),
        ],
        exercises: [
          ExerciseItem(id: 'e1', name: '慢跑', time: '18:30', duration: 30, caloriesBurned: 250, days: [1, 3, 5]),
        ],
      );

      final settings = AppSettings(
        bmr: 1400,
        tdee: 1680,
        dailyCalorieTarget: 1500,
      );

      final store = RecordStore();
      // 模拟周一称重 68.5kg，周五称重 67.9kg
      store.weightRecords.records[monday] = WeightEntry(weight: 68.5, bmr: 1400, updatedAt: 1);
      final friday = addDays(monday, 4);
      store.weightRecords.records[friday] = WeightEntry(weight: 67.9, bmr: 1400, updatedAt: 2);

      // 模拟周一打卡
      store.checkRecords[monday] = {
        'meal:m1': CheckEntry(checkedAt: 100),
        'meal:m2': CheckEntry(checkedAt: 200),
        'exercise:e1': CheckEntry(checkedAt: 300),
      };

      final profile = UserProfile(gender: 'female', age: 26, height: 165, weight: 68.5);

      final stats = calculateWeeklyReportStats(
        plan: plan,
        settings: settings,
        records: store,
        profile: profile,
        weekOffset: 0,
      );

      // 验证周期
      expect(stats.startDate, monday);
      expect(stats.days.length, 7);

      // 验证体重计算
      expect(stats.startWeight, 68.5);
      expect(stats.endWeight, 67.9);
      expect(stats.weightDelta, closeTo(-0.6, 0.001));
      expect(stats.weightRecordCount, 2);

      // 验证热量与理论掉秤
      expect(stats.targetDailyCalories, 1500);
      expect(stats.hasSufficientData, isTrue);
    });
  });

  group('Prompt 与 Markdown 生成测试', () {
    test('生成发给 AI 的摘要与外部提问 Prompt', () {
      const stats = WeeklyReportStats(
        startDate: '2026-10-12',
        endDate: '2026-10-18',
        weekLabel: '10月12日 - 10月18日',
        isCurrentWeek: true,
        days: [],
        startWeight: 68.5,
        endWeight: 67.9,
        weightDelta: -0.6,
        minWeight: 67.9,
        maxWeight: 68.5,
        weightRecordCount: 3,
        totalIntake: 9800,
        avgIntake: 1400,
        totalBurn: 13300,
        avgBurn: 1900,
        totalDeficit: 3500,
        avgDeficit: 500,
        estimatedFatLossKg: 0.45,
        totalProtein: 490,
        avgProtein: 70,
        totalCarbs: 1050,
        avgCarbs: 150,
        totalFat: 280,
        avgFat: 40,
        proteinPercent: 23,
        carbsPercent: 50,
        fatPercent: 27,
        targetDailyCalories: 1500,
        targetProtein: 80,
        targetCarbs: 150,
        targetFat: 45,
        totalPlannedTasks: 21,
        totalDoneTasks: 18,
        taskComplianceRate: 86,
        recordedDays: 6,
        exerciseDays: 3,
        totalExerciseBurn: 750,
        exerciseNames: ['慢跑', '快走'],
      );

      final summary = buildWeeklyStatsSummaryForAi(stats);
      expect(summary, contains('【体重体脂数据】'));
      expect(summary, contains('-0.60 kg'));
      expect(summary, contains('3500 kcal'));
      expect(summary, contains('慢跑、快走'));

      final prompt = buildExternalAiPrompt(stats);
      expect(prompt, contains('你是资深临床营养师与国家级运动减脂教练'));
      expect(prompt, contains('【本周整体点评】'));
      expect(prompt, contains('【未来一周减脂建议】'));

      final md = buildFullMarkdownReport(
        stats: stats,
        headline: '执行稳健，节奏极佳',
        review: '本周热量缺口达成良好。',
        suggestions: ['建议早餐加一颗鸡蛋', '建议下周增加一次慢跑'],
        encouragement: '继续保持！',
      );
      expect(md, contains('# 🌿 知轻 · 减脂周度复盘报告'));
      expect(md, contains('建议早餐加一颗鸡蛋'));
    });
  });

  group('AI 建议解析测试', () {
    test('正确解析 JSON 格式响应', () {
      const jsonResponse = '''
```json
{
  "headline": "控油出色，蛋白质需微调",
  "review": "本周7天累计缺口达到3500kcal，掉秤0.6kg非常稳健。午餐与晚餐烹饪清淡，但日均蛋白质仅70g，距离80g目标略有差距。",
  "suggestions": [
    "早餐增加一颗水煮蛋或一杯无糖豆浆，将蛋白质补齐至80g；",
    "下周维持1400~1500kcal摄入不变，避免热量过低引起代谢适应；",
    "可将周五的快走提升为30分钟慢跑，巩固下半周热量缺口。"
  ],
  "encouragement": "减脂是一场跟自己的长跑，节奏比速度更重要，你做得非常棒！"
}
```
''';
      final result = parseWeeklyAdvice(jsonResponse);
      expect(result.headline, '控油出色，蛋白质需微调');
      expect(result.review, contains('掉秤0.6kg非常稳健'));
      expect(result.suggestions.length, 3);
      expect(result.suggestions[0], contains('早餐增加一颗水煮蛋'));
      expect(result.encouragement, contains('节奏比速度更重要'));
    });

    test('对纯文本/Markdown 降级输出也能鲁棒提取', () {
      const textResponse = '''
【本周点评】
本周整体执行非常优秀，三餐规律，有效控制了油脂摄入。

【未来一周建议】
- 1. 早餐多摄入优质蛋白
- 2. 晚餐减少高碳水主食
- 3. 保持每周三次有氧

【教练寄语】
平稳就是最快的减脂速度，继续加油！
''';
      final result = parseWeeklyAdvice(textResponse);
      expect(result.review, contains('本周整体执行非常优秀'));
      expect(result.suggestions.length, 3);
      expect(result.suggestions[0], contains('早餐多摄入优质蛋白'));
      expect(result.encouragement, contains('平稳就是最快的减脂速度'));
    });
  });

  group('WeeklyReportPoster 组件渲染测试', () {
    testWidgets('海报卡片与各模块正常布局渲染无溢出', (tester) async {
      const stats = WeeklyReportStats(
        startDate: '2026-10-12',
        endDate: '2026-10-18',
        weekLabel: '10月12日 - 10月18日',
        isCurrentWeek: true,
        days: [
          WeeklyDaySnapshot(
            date: '2026-10-12',
            weekdayName: '周一',
            summary: DailySummary(
              plannedIntake: 1500,
              mealIntake: 1400,
              tempIntake: 0,
              tempBurn: 0,
              extraIntake: 0,
              planBurn: 250,
              exerciseBurn: 250,
              baseBurn: 1680,
              burn: 1930,
              intake: 1400,
              tdee: 1680,
              deficit: 530,
              taskCount: 3,
              doneCount: 3,
            ),
            weight: 68.5,
            hasData: true,
            isFuture: false,
          ),
        ],
        startWeight: 68.5,
        endWeight: 67.9,
        weightDelta: -0.6,
        minWeight: 67.9,
        maxWeight: 68.5,
        weightRecordCount: 2,
        totalIntake: 9800,
        avgIntake: 1400,
        totalBurn: 13300,
        avgBurn: 1900,
        totalDeficit: 3500,
        avgDeficit: 500,
        estimatedFatLossKg: 0.45,
        totalProtein: 490,
        avgProtein: 70,
        totalCarbs: 1050,
        avgCarbs: 150,
        totalFat: 280,
        avgFat: 40,
        proteinPercent: 23,
        carbsPercent: 50,
        fatPercent: 27,
        targetDailyCalories: 1500,
        targetProtein: 80,
        targetCarbs: 150,
        targetFat: 45,
        totalPlannedTasks: 21,
        totalDoneTasks: 18,
        taskComplianceRate: 86,
        recordedDays: 6,
        exerciseDays: 3,
        totalExerciseBurn: 750,
        exerciseNames: ['慢跑'],
      );

      const advice = WeeklyAdviceResult(
        headline: '执行稳健，节奏极佳',
        review: '本周热量缺口达成稳健。',
        suggestions: ['建议早餐加一颗水煮蛋', '建议下周增加慢跑频次'],
        encouragement: '继续保持好习惯！',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyReportPoster(
                stats: stats,
                advice: advice,
              ),
            ),
          ),
        ),
      );

      expect(find.text('知轻 · 减脂周报'), findsOneWidget);
      expect(find.text('每周复盘与建议'), findsOneWidget);
      expect(find.text('-0.60 kg'), findsOneWidget);
      expect(find.text('+3500 kcal'), findsOneWidget);
      expect(find.text('AI 营养师指导'), findsOneWidget);
      expect(find.text('执行稳健，节奏极佳'), findsOneWidget);
      expect(find.text('建议早餐加一颗水煮蛋'), findsOneWidget);
    });
  });
}
