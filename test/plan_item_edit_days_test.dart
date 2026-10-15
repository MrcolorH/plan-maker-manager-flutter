import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/pages/item/item_detail_page.dart';
import 'package:jianfei_dazi/providers/onboarding_provider.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/providers/usage_provider.dart';
import 'package:jianfei_dazi/services/reminder_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';
import 'package:jianfei_dazi/widgets/plan_item_edit.dart';

class _FakeReminderService extends ReminderService {
  _FakeReminderService() : super.forTesting();

  @override
  Future<void> fullReschedule(PlanData plan, AppSettings settings) async {}

  @override
  Future<void> ensureScheduled(PlanData plan, AppSettings settings) async {}
}

Widget _wrapWithProviders({
  required Widget child,
  required PlanProvider planProv,
  required RecordProvider recordProv,
  required SettingsProvider settingsProv,
  required OnboardingProvider onboardingProv,
  required UsageProvider usageProv,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: planProv),
      ChangeNotifierProvider.value(value: recordProv),
      ChangeNotifierProvider.value(value: settingsProv),
      ChangeNotifierProvider.value(value: onboardingProv),
      ChangeNotifierProvider.value(value: usageProv),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late _FakeReminderService reminder;
  late SettingsProvider settingsProv;
  late RecordProvider recordProv;
  late PlanProvider planProv;
  late OnboardingProvider onboardingProv;
  late UsageProvider usageProv;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    storage = StorageService.instance;
    reminder = _FakeReminderService();
    settingsProv = SettingsProvider(storage, reminder);
    recordProv = RecordProvider(storage);
    planProv = PlanProvider(storage, reminder, settingsProv, recordProv);
    onboardingProv = OnboardingProvider(storage, planProv, settingsProv, recordProv);
    usageProv = UsageProvider(storage);
  });

  group('计划条目执行星期调整与展示测试', () {
    test('daysCn 格式：全周与周末汉字格式化', () {
      expect(daysCn([]), '每天');
      expect(daysCn([1, 2, 3, 4, 5, 6, 7]), '每天');
      expect(daysCn([6, 7]), '六日');
      expect(daysCn([1, 2, 3, 4, 5]), '一二三四五');
      expect(daysCn([7]), '日');
      expect(weekCn(7), '日');
    });

    testWidgets('编辑餐食计划：从工作日调整为周末并保存成功', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final initialMeal = MealItem(
        id: 'm-test-1',
        type: 'lunch',
        name: '减脂沙拉',
        time: '12:00',
        calories: 350,
        days: [1, 2, 3, 4, 5],
      );

      MealItem? savedMeal;

      await tester.pumpWidget(
        _wrapWithProviders(
          planProv: planProv,
          recordProv: recordProv,
          settingsProv: settingsProv,
          onboardingProv: onboardingProv,
          usageProv: usageProv,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final r = await showPlanItemEditor(context: ctx, meal: initialMeal);
                if (r is MealItem) savedMeal = r;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      // 打开编辑器
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('编辑餐食'), findsOneWidget);
      expect(find.text('执行周期（每周哪几天）'), findsOneWidget);
      expect(find.text('工作日'), findsOneWidget);
      expect(find.text('周末'), findsOneWidget);
      expect(find.text('每天'), findsOneWidget);

      // 切换为「周末」
      await tester.tap(find.text('周末'));
      await tester.pumpAndSettle();

      // 点击保存
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(savedMeal, isNotNull);
      expect(savedMeal!.days, [6, 7]);
      expect(savedMeal!.name, '减脂沙拉');
    });

    testWidgets('编辑餐食计划：切换为「每天」时保存为全选空列表', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final initialMeal = MealItem(
        id: 'm-test-2',
        type: 'breakfast',
        name: '燕麦粥',
        time: '08:00',
        calories: 250,
        days: [1, 3, 5],
      );

      MealItem? savedMeal;

      await tester.pumpWidget(
        _wrapWithProviders(
          planProv: planProv,
          recordProv: recordProv,
          settingsProv: settingsProv,
          onboardingProv: onboardingProv,
          usageProv: usageProv,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final r = await showPlanItemEditor(context: ctx, meal: initialMeal);
                if (r is MealItem) savedMeal = r;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // 切换为「每天」
      await tester.tap(find.text('每天'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(savedMeal, isNotNull);
      expect(savedMeal!.days, isEmpty); // 每天保存为 []
    });

    testWidgets('编辑运动计划：切换为单日点选（周二+周四）并保存成功', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final initialExercise = ExerciseItem(
        id: 'e-test-1',
        name: '有氧慢跑',
        time: '19:00',
        duration: 40,
        caloriesBurned: 350,
        days: [], // 初始每天
      );

      ExerciseItem? savedExercise;

      await tester.pumpWidget(
        _wrapWithProviders(
          planProv: planProv,
          recordProv: recordProv,
          settingsProv: settingsProv,
          onboardingProv: onboardingProv,
          usageProv: usageProv,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final r = await showPlanItemEditor(context: ctx, exercise: initialExercise);
                if (r is ExerciseItem) savedExercise = r;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('编辑运动'), findsOneWidget);
      expect(find.text('执行周期（每周哪几天）'), findsOneWidget);

      // 切换为工作日 [1, 2, 3, 4, 5]
      await tester.tap(find.text('工作日'));
      await tester.pumpAndSettle();

      // 取消周一、周三、周五，只保留周二、周四
      await tester.tap(find.text('一'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('三'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('五'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(savedExercise, isNotNull);
      expect(savedExercise!.days, [2, 4]);
    });

    testWidgets('全部取消勾选时阻止保存并给出提示', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final meal = MealItem(
        id: 'm-test-3',
        type: 'dinner',
        name: '轻食晚餐',
        time: '18:30',
        days: [6],
      );

      MealItem? savedMeal;

      await tester.pumpWidget(
        _wrapWithProviders(
          planProv: planProv,
          recordProv: recordProv,
          settingsProv: settingsProv,
          onboardingProv: onboardingProv,
          usageProv: usageProv,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final r = await showPlanItemEditor(context: ctx, meal: meal);
                if (r is MealItem) savedMeal = r;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // 点击「六」取消唯一选中的周六
      await tester.tap(find.text('六'));
      await tester.pumpAndSettle();

      // 点击保存，此时 _selectedDays 为空
      await tester.tap(find.text('保存'));
      await tester.pump();

      // 应该弹出 SnackBar 阻止保存，弹层未关闭
      expect(find.text('请至少选择一天执行该计划'), findsOneWidget);
      expect(savedMeal, isNull);
      expect(find.text('编辑餐食'), findsOneWidget);
    });

    test('PlanProvider.replaceItem 能够成功持久化更新后的执行周期', () async {
      final meal = MealItem(
        id: 'm-orig-1',
        type: 'lunch',
        name: '原始餐食',
        time: '12:00',
        days: [1, 2, 3],
      );
      planProv.plan.meals.add(meal);

      final updatedMeal = MealItem(
        id: 'm-orig-1',
        type: 'lunch',
        name: '修改后的餐食',
        time: '12:30',
        days: [6, 7],
      );

      await planProv.replaceItem('meal', updatedMeal);

      final current = planProv.plan.meals.firstWhere((m) => m.id == 'm-orig-1');
      expect(current.days, [6, 7]);
      expect(current.time, '12:30');

      // 验证读取本地持久化数据
      final storedJson = storage.readMap(StorageService.kPlan);
      final storedPlan = PlanData.fromJson(storedJson);
      final storedMeal = storedPlan.meals.firstWhere((m) => m.id == 'm-orig-1');
      expect(storedMeal.days, [6, 7]);
    });

    testWidgets('ItemDetailPage 中点击执行星期行能够唤起编辑弹层并修改执行星期', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final meal = MealItem(
        id: 'm-detail-1',
        type: 'lunch',
        name: '工作日鸡胸肉',
        time: '12:00',
        calories: 300,
        days: [1, 2, 3, 4, 5],
      );
      planProv.plan.meals.add(meal);

      await tester.pumpWidget(
        _wrapWithProviders(
          planProv: planProv,
          recordProv: recordProv,
          settingsProv: settingsProv,
          onboardingProv: onboardingProv,
          usageProv: usageProv,
          child: const ItemDetailPage(type: 'meal', itemId: 'm-detail-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('执行星期'), findsOneWidget);
      expect(find.text('每周一二三四五'), findsOneWidget);

      // 点击执行星期行唤起编辑
      await tester.tap(find.text('每周一二三四五'));
      await tester.pumpAndSettle();

      expect(find.text('编辑餐食'), findsOneWidget);
      expect(find.text('执行周期（每周哪几天）'), findsOneWidget);

      // 切换为周末
      await tester.tap(find.text('周末'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 页面更新为每周六日
      expect(find.text('每周六日'), findsOneWidget);
      expect(planProv.plan.meals.firstWhere((m) => m.id == 'm-detail-1').days, [6, 7]);
    });
  });
}
