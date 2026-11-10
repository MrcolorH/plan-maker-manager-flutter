import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/pages/plan/plan_page.dart';
import 'package:jianfei_dazi/pages/settings/backup_page.dart';
import 'package:jianfei_dazi/pages/settings/settings_page.dart';
import 'package:jianfei_dazi/providers/onboarding_provider.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/providers/theme_provider.dart';
import 'package:jianfei_dazi/providers/usage_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';

Widget _wrapSettings({
  required SettingsProvider settingsProv,
  required OnboardingProvider onboardingProv,
  required RecordProvider recordProv,
  required PlanProvider planProv,
  required ThemeProvider themeProv,
  required UsageProvider usageProv,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settingsProv),
      ChangeNotifierProvider.value(value: onboardingProv),
      ChangeNotifierProvider.value(value: recordProv),
      ChangeNotifierProvider.value(value: planProv),
      ChangeNotifierProvider.value(value: themeProv),
      ChangeNotifierProvider.value(value: usageProv),
    ],
    child: const MaterialApp(
      home: SettingsPage(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late SettingsProvider settingsProv;
  late RecordProvider recordProv;
  late PlanProvider planProv;
  late OnboardingProvider onboardingProv;
  late ThemeProvider themeProv;
  late UsageProvider usageProv;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    storage = StorageService.instance;
    settingsProv = SettingsProvider(storage);
    recordProv = RecordProvider(storage);
    planProv = PlanProvider(storage, settingsProv, recordProv);
    onboardingProv = OnboardingProvider(storage, planProv, settingsProv, recordProv);
    themeProv = ThemeProvider(storage);
    usageProv = UsageProvider(storage);

    await settingsProv.update({
      'tdee': 2100,
      'dailyCalorieTarget': 1600,
      'autoBackupEnabled': true,
    });
    await onboardingProv.saveProfile({
      'gender': 'male',
      'age': 28,
      'height': 178,
      'weight': 75.0,
      'activity': 1.2,
    });
  });

  group('设置页 - 热量卡片与本地备份整合测试', () {
    testWidgets('热量区域：合并为每日消耗与基础信息展示卡片，原有基础消耗与每日目标摄入独立行已移除', (tester) async {
      await tester.pumpWidget(_wrapSettings(
        settingsProv: settingsProv,
        onboardingProv: onboardingProv,
        recordProv: recordProv,
        planProv: planProv,
        themeProv: themeProv,
        usageProv: usageProv,
      ));
      await tester.pumpAndSettle();

      // 原有的两行已去除
      expect(find.text('基础消耗(TDEE)'), findsNothing);
      expect(find.text('每日目标摄入'), findsNothing);

      // 合并后的展示卡片包含「每日消耗」与「基础信息」
      expect(find.text('每日消耗'), findsOneWidget);
      expect(find.text('2100 kcal'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.textContaining('男 · 28岁 · 178cm · 75kg'), findsOneWidget);

      // 点击合并展示卡片，能打开设置弹层
      await tester.tap(find.text('每日消耗'));
      await tester.pumpAndSettle();

      expect(find.text('热量设置'), findsOneWidget);
      expect(find.text('每日消耗（TDEE，kcal）'), findsOneWidget);
    });

    testWidgets('数据与备份区域：自动备份、导入备份、导出备份已整合至本地备份子菜单', (tester) async {
      await tester.pumpWidget(_wrapSettings(
        settingsProv: settingsProv,
        onboardingProv: onboardingProv,
        recordProv: recordProv,
        planProv: planProv,
        themeProv: themeProv,
        usageProv: usageProv,
      ));
      await tester.pumpAndSettle();

      // 在设置主页，不直接展示独立的自动备份开关、导出备份行、导入备份行
      expect(find.text('本地备份与恢复'), findsOneWidget);
      expect(find.text('自动备份 · 导入 · 导出'), findsOneWidget);
      expect(find.text('云端同步与 QQ 绑定'), findsOneWidget);

      // 点击进入子页面
      await tester.tap(find.text('本地备份与恢复'));
      await tester.pumpAndSettle();

      // 在子页面中展示三项功能
      expect(find.byType(BackupPage), findsOneWidget);
      expect(find.text('自动备份'), findsOneWidget);
      expect(find.text('导出备份'), findsOneWidget);
      expect(find.text('导入备份'), findsOneWidget);
      expect(find.text('清空全部数据并重置', skipOffstage: false), findsOneWidget);
    });

    testWidgets('计划页面：顶部计划介绍已去除，只留餐食和运动分栏与条目', (tester) async {
      await planProv.importPlan(PlanData(
        meta: PlanMeta(
          planName: '夏季减脂特训',
          startDate: '2026-06-01',
          endDate: '2026-08-31',
          baseWeight: 78,
          targetWeight: 68,
        ),
        meals: [
          MealItem(id: 'm1', type: 'breakfast', name: '全麦燕麦蛋', time: '08:00', calories: 350, days: []),
        ],
        exercises: [
          ExerciseItem(id: 'e1', name: '晨跑5公里', time: '07:00', duration: 30, caloriesBurned: 320, days: []),
        ],
      ).toJson());

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsProv),
          ChangeNotifierProvider.value(value: onboardingProv),
          ChangeNotifierProvider.value(value: recordProv),
          ChangeNotifierProvider.value(value: planProv),
          ChangeNotifierProvider.value(value: themeProv),
          ChangeNotifierProvider.value(value: usageProv),
        ],
        child: const MaterialApp(
          home: PlanPage(),
        ),
      ));
      await tester.pumpAndSettle();

      // 顶部计划介绍卡片中的内容已不展示
      expect(find.text('夏季减脂特训'), findsNothing);
      expect(find.text('2026-06-01 ~ 2026-08-31'), findsNothing);
      expect(find.text('起始 kg'), findsNothing);
      expect(find.text('目标 kg'), findsNothing);
      expect(find.text('每日目标 kcal'), findsNothing);

      // 餐食和运动分栏正常展示，并能切换查看条目
      expect(find.text('餐食 1'), findsOneWidget);
      expect(find.text('运动 1'), findsOneWidget);
      expect(find.text('全麦燕麦蛋'), findsOneWidget);

      await tester.tap(find.text('运动 1'));
      await tester.pumpAndSettle();
      expect(find.text('晨跑5公里'), findsOneWidget);
    });
  });
}
