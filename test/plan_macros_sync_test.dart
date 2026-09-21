import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';

void main() {
  group('身高体重体脂率估算与宏量目标同步测试', () {
    test('calculateFatLossMacroTargets 针对身材计算科学三大营养素标准', () {
      final targets = calculateFatLossMacroTargets(
        targetCalories: 1400,
        weight: 65.0,
        bodyFat: 20.0,
        gender: 'male',
        height: 175,
        age: 26,
      );

      // 去脂体重: 65 * 0.8 = 52kg
      // 蛋白质 2.0g/kg 瘦体重 ≈ 104g
      expect(targets.protein, inInclusiveRange(90, 120));
      // 脂肪 0.75g/kg 体重 ≈ 49g
      expect(targets.fat, inInclusiveRange(40, 60));
      // 剩余热量给碳水
      expect(targets.carbs, greaterThan(50));

      final totalCal = targets.protein * 4 + targets.carbs * 4 + targets.fat * 9;
      // 宏量总热量应紧密围绕目标摄入
      expect((totalCal - 1400).abs(), lessThan(50));
    });

    test('dailySummary 首页宏量目标严格跟随身材与计划目标走', () {
      final plan = PlanData(
        meta: PlanMeta(
          dailyCalorieTarget: 1400,
          targetProtein: 105,
          targetCarbs: 145,
          targetFat: 44,
        ),
      );
      final settings = AppSettings(dailyCalorieTarget: 1400, tdee: 2000);
      final records = RecordStore.empty();
      final profile = UserProfile(
        gender: 'male',
        height: 175,
        weight: 65,
        age: 26,
        bodyFat: 20,
      );

      final s = dailySummary(plan, settings, records, '2026-09-20', profile: profile);

      // 首页顶部三个宏量营养素进度条的目标值（分母）应为用户身材估算目标
      expect(s.plannedProtein, 105);
      expect(s.plannedCarbs, 145);
      expect(s.plannedFat, 44);
    });

    test('PlanMeta 序列化支持 targetProtein, targetCarbs, targetFat', () {
      final meta = PlanMeta(
        dailyCalorieTarget: 1500,
        targetProtein: 120,
        targetCarbs: 150,
        targetFat: 45,
      );

      final json = meta.toJson();
      expect(json['targetProtein'], 120);
      expect(json['targetCarbs'], 150);
      expect(json['targetFat'], 45);

      final restored = PlanMeta.fromJson(json);
      expect(restored.targetProtein, 120);
      expect(restored.targetCarbs, 150);
      expect(restored.targetFat, 45);
    });
  });
}
