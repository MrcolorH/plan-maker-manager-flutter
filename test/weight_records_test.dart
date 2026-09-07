/// F10 体重记录与基础消耗按日沿用测试
/// 覆盖：baseBurnForDate 沿用链（记录/baseline/兜底/bmr=0 跳过）、weightForDate、
///       R2 回归（录体重后历史缺口逐日不变）、ensureBaseline 幂等与时机、
///       setWeightRecord 覆盖/删除回退、provider 持久化
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/models/weight.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/utils/date_utils.dart' show todayStr;

final AppSettings _settings = AppSettings(tdee: 2000, bmr: 1500); // 现状口径 = 1500×1.2 = 1800

WeightData wd({
  WeightBaseline? baseline,
  Map<String, WeightEntry>? records,
}) =>
    WeightData(baseline: baseline, records: records);

WeightEntry we(double weight, int bmr, int updatedAt) =>
    WeightEntry(weight: weight, bmr: bmr, updatedAt: updatedAt);

void main() {
  group('UserProfile.weight 两位小数与 roundtrip（与体重记录同口径）', () {
    test('int? 时代 68.55 会被 round 成 69；double 后保留两位小数', () {
      final p = UserProfile.fromJson({'gender': 'male', 'weight': 68.55});
      expect(p.weight, 68.55); // 不再被 round 成 69
    });

    test('toJson → fromJson 往返保留两位小数', () {
      final p = UserProfile.fromJson({'gender': 'male', 'weight': 68.55});
      final back = UserProfile.fromJson(p.toJson());
      expect(back.weight, 68.55);
    });

    test('完整 profile complete 判定不变', () {
      final p = UserProfile(
          gender: 'male', age: 30, height: 175, weight: 68.55);
      expect(p.complete, true);
    });
  });

  group('fmtWeight 展示去尾零（两位小数口径）', () {
    test('整数去尾（68.00 → 68）', () {
      expect(fmtWeight(68.0), '68');
    });
    test('尾零去除（68.50 → 68.5）', () {
      expect(fmtWeight(68.5), '68.5');
    });
    test('两位小数原样（68.55 → 68.55）', () {
      expect(fmtWeight(68.55), '68.55');
    });
  });

  group('baseBurnForDate 沿用链', () {
    test('无任何数据 → 现状口径（bmr×1.2 优先，无 bmr 用 tdee）', () {
      final store = RecordStore();
      expect(baseBurnForDate(_settings, store, '2026-09-01'), 1800);
      expect(baseBurnForDate(AppSettings(tdee: 2000, bmr: 0), store, '2026-09-01'), 2000);
    });

    test('仅 baseline：严格早于固化日的日期用基准值，其余现算', () {
      final store = RecordStore(
        weightRecords: wd(baseline: WeightBaseline(base: 1814, date: '2026-09-03')),
      );
      expect(baseBurnForDate(_settings, store, '2026-09-02'), 1814);
      expect(baseBurnForDate(_settings, store, '2026-09-03'), 1800);
      expect(baseBurnForDate(_settings, store, '2026-09-10'), 1800);
    });

    test('体重记录链：最近 ≤date 记录生效，未录入的天沿用', () {
      final store = RecordStore(
        weightRecords: wd(records: {
          '2026-09-01': we(68.5, 1500, 1),
          '2026-09-05': we(68.0, 1400, 2),
        }),
      );
      expect(baseBurnForDate(_settings, store, '2026-09-01'), 1800);
      expect(baseBurnForDate(_settings, store, '2026-09-03'), 1800); // 沿用 09-01
      expect(baseBurnForDate(_settings, store, '2026-09-05'), 1680); // 1400×1.2
      expect(baseBurnForDate(_settings, store, '2026-09-20'), 1680); // 沿用 09-05
      expect(baseBurnForDate(_settings, store, '2026-08-31'), 1800); // 无记录 → fallback
    });

    test('bmr=0 的记录跳过继续沿链（基础信息不全仅作体重展示）', () {
      final store = RecordStore(
        weightRecords: wd(records: {
          '2026-09-05': we(68.0, 0, 2), // 今天录了但当时基础信息不全
          '2026-09-01': we(68.5, 1400, 1),
        }),
      );
      // 09-05 记录 bmr=0 → 回溯到 09-01 的 bmr 1400
      expect(baseBurnForDate(_settings, store, '2026-09-05'), 1680);
      // 但 weightForDate 展示仍用最近记录体重
      expect(weightForDate(store, '2026-09-05'), 68.0);
    });

    test('weightForDate 未录入返回 null', () {
      expect(weightForDate(RecordStore(), '2026-09-01'), isNull);
    });
  });

  group('R2 回归：录体重历史缺口逐日不变（最高优先）', () {
    // 计划：dailySummary 走「无快照日 fallback」口径即可聚焦 base burn 变化
    test('30 天历史打卡 → 录新体重 → 全部历史日基础消耗与缺口不变，仅当天起变化', () {
      final plan = PlanData(
        meta: PlanMeta(startedAt: '2026-08-01'),
        meals: [
          MealItem(id: 'm1', type: 'lunch', name: '午餐', time: '12:00', calories: 500, days: [1, 2, 3, 4, 5, 6, 7]),
        ],
      );
      final checks = <String, Map<String, CheckEntry>>{};
      for (var d = 1; d <= 30; d++) {
        final date = d < 10 ? '2026-08-0$d' : '2026-08-$d';
        checks[date] = {'meal:m1': CheckEntry(checkedAt: d)};
      }
      final before = <String, int>{};
      final storeA = RecordStore(checkRecords: checks);
      for (final date in checks.keys) {
        before[date] = dailySummary(plan, _settings, storeA, date).deficit.round();
      }
      // 用户现在录了体重（BMR 变化），今天 = 2026-09-03
      final storeB = RecordStore(
        checkRecords: checks,
        weightRecords: WeightData(
          baseline: WeightBaseline(base: 1800, date: '2026-09-03'), // 录入时固化旧基准
          records: {'2026-09-03': we(60.0, 1200, 3)}, // 新 BMR → 基础消耗 1440
        ),
      );
      for (final date in checks.keys) {
        final after = dailySummary(plan, _settings, storeB, date);
        expect(after.deficit.round(), before[date], reason: '历史缺口漂移: $date');
        expect(after.baseBurn, 1800, reason: '历史基础消耗漂移: $date');
      }
      // 固化日（今天）之后用新记录
      expect(dailySummary(plan, _settings, storeB, '2026-09-03').baseBurn, 1440);
    });
  });

  group('ensureBaseline / setWeightRecord / removeWeightRecord（provider）', () {
    RecordProvider newProvider() {
      SharedPreferences.setMockInitialValues({});
      return RecordProvider(StorageService.instance);
    }

    test('有历史时固化（幂等：重复调用不覆盖已有 baseline）；无历史不固化', () async {
      final p = newProvider();
      // 无历史 → 不固化
      await p.ensureBaseline(1800);
      expect(p.store.weightRecords.baseline, isNull);
      // 有打卡历史 → 固化
      await p.setWeightRecord(68.5, 1500);
      await p.toggleCheck('2026-09-01', 'meal', 'm1');
      await p.ensureBaseline(1800);
      expect(p.store.weightRecords.baseline!.base, 1800);
      expect(p.store.weightRecords.baseline!.date, todayStr()); // 固化日 = 运行当天（勿硬编码日期）
      // 幂等：再次调用不覆盖
      await p.ensureBaseline(9999);
      expect(p.store.weightRecords.baseline!.base, 1800);
    });

    test('同日重复录入覆盖并刷新 updatedAt；删除回退', () async {
      final p = newProvider();
      await p.setWeightRecord(68.5, 1500, date: '2026-09-01', updatedAt: 100);
      await p.setWeightRecord(68.0, 1400, date: '2026-09-01', updatedAt: 200);
      expect(p.store.weightRecords.records['2026-09-01']!.weight, 68.0);
      expect(p.store.weightRecords.records['2026-09-01']!.updatedAt, 200);
      expect(p.store.weightRecords.records.length, 1);
      await p.removeWeightRecord('2026-09-01');
      expect(p.store.weightRecords.records, isEmpty);
    });
  });
}
