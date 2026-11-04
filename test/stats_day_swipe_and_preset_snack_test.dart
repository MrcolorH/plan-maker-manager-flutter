/// 日历视图详情左右滑动切换天 & 补充加餐支持常用方案功能测试
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/pages/stats/stats_page.dart';
import 'package:jianfei_dazi/providers/onboarding_provider.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/preset_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/services/reminder_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/theme/app_theme.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';

class _FakeReminderService extends ReminderService {
  _FakeReminderService() : super.forTesting();
  @override
  Future<void> fullReschedule(PlanData plan, AppSettings settings) async {}
  @override
  Future<void> ensureScheduled(PlanData plan, AppSettings settings) async {}
}

Widget _buildTestApp({
  required Widget child,
  required StorageService storage,
  PlanData? plan,
  PresetProvider? presetProvider,
  RecordProvider? recordProvider,
}) {
  final reminder = _FakeReminderService();
  final recP = recordProvider ?? RecordProvider(storage);
  late final PlanProvider planP;
  final setP = SettingsProvider(
    storage,
    reminder,
    getPlan: () => planP.plan,
  );
  planP = PlanProvider(storage, reminder, setP, recP);
  if (plan != null) {
    planP.plan = plan;
  }
  final onbP = OnboardingProvider(storage, planP, setP, recP);
  onbP.state.done = true;
  final presetP = presetProvider ?? PresetProvider();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: planP),
      ChangeNotifierProvider.value(value: recP),
      ChangeNotifierProvider.value(value: setP),
      ChangeNotifierProvider.value(value: onbP),
      ChangeNotifierProvider.value(value: presetP),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
  });

  group('日历某日详情左右滑动与切换天测试', () {
    testWidgets('可以通过左右滑动切换前一天与后一天', (tester) async {
      final today = todayStr();
      final yesterday = addDays(today, -1);
      final tomorrow = addDays(today, 1);
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
      );

      await tester.pumpWidget(
        _buildTestApp(
          storage: StorageService.instance,
          plan: plan,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => DayDetailSheet(date: today),
                );
              },
              child: const Text('打开今日详情'),
            ),
          ),
        ),
      );

      // 打开弹层
      await tester.tap(find.text('打开今日详情'));
      await tester.pumpAndSettle();

      // 验证当前显示今天日期
      expect(find.text(dateCn(today)), findsOneWidget);

      // 向左滑动（拖动从右向左）切换到后一天
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // 验证切换到了明天
      expect(find.text(dateCn(tomorrow)), findsOneWidget);

      // 向右滑动（拖动从左向右）切换回今天
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text(dateCn(today)), findsOneWidget);

      // 再次向右滑动切换到昨天
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text(dateCn(yesterday)), findsOneWidget);
    });

    testWidgets('可以通过点击前一天后一天箭头按钮切换天', (tester) async {
      final today = todayStr();
      final yesterday = addDays(today, -1);
      final tomorrow = addDays(today, 1);
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
      );

      await tester.pumpWidget(
        _buildTestApp(
          storage: StorageService.instance,
          plan: plan,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => DayDetailSheet(date: today),
                );
              },
              child: const Text('打开今日详情'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开今日详情'));
      await tester.pumpAndSettle();

      expect(find.text(dateCn(today)), findsOneWidget);

      // 点击前一天箭头
      await tester.tap(find.byTooltip('前一天'));
      await tester.pumpAndSettle();
      expect(find.text(dateCn(yesterday)), findsOneWidget);

      // 点击后一天箭头返回今天
      await tester.tap(find.byTooltip('后一天'));
      await tester.pumpAndSettle();
      expect(find.text(dateCn(today)), findsOneWidget);

      // 再次点击后一天切换至明天
      await tester.tap(find.byTooltip('后一天'));
      await tester.pumpAndSettle();
      expect(find.text(dateCn(tomorrow)), findsOneWidget);
    });
  });

  group('日历补充加餐支持已保存常用方案测试', () {
    testWidgets('补录加餐弹窗中展示常用方案，点击选中可选择份量并保存', (tester) async {
      final today = todayStr();
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
      );
      final storage = StorageService.instance;
      final presetProvider = PresetProvider();
      final recordProvider = RecordProvider(storage);

      // 预先存入两个常用方案
      await presetProvider.savePreset(
        name: '希腊酸奶碗',
        calories: 180,
        protein: 15,
        carbs: 12,
        fat: 4,
        unit: '碗',
      );
      await presetProvider.savePreset(
        name: '水煮蛋',
        calories: 75,
        protein: 7,
        carbs: 1,
        fat: 5,
        unit: '个',
      );

      await tester.pumpWidget(
        _buildTestApp(
          storage: storage,
          plan: plan,
          presetProvider: presetProvider,
          recordProvider: recordProvider,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => DayDetailSheet(date: today),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();

      // 点击「＋ 补录加餐」
      await tester.tap(find.text('＋ 补录加餐'));
      await tester.pumpAndSettle();

      // 验证存在常用方案区域与预设食物（日详情背景与补录弹窗均存在）
      expect(find.text('常用方案'), findsOneWidget);
      expect(find.text('希腊酸奶碗'), findsWidgets);
      expect(find.text('水煮蛋'), findsWidgets);

      // 点击补录弹层中的「希腊酸奶碗」
      await tester.tap(find.text('希腊酸奶碗').last);
      await tester.pumpAndSettle();

      // 验证份量选择出现
      expect(find.text('份量：'), findsOneWidget);
      expect(find.text('180k'), findsWidgets);

      // 选择 2 份
      await tester.tap(find.text('2份'));
      await tester.pumpAndSettle();

      // 验证自动折算热量为 360 kcal
      expect(find.text('保存加餐（360 kcal）'), findsOneWidget);

      // 点击保存
      await tester.tap(find.text('保存加餐（360 kcal）'));
      await tester.pumpAndSettle();

      // 验证记录添加成功且在日详情加餐列表中展现
      final snacks = recordProvider.store.dayEntries[today]?.where((e) => e.slot == 'snack').toList() ?? [];
      expect(snacks.any((s) => s.content.contains('希腊酸奶碗') && s.calories == 360), isTrue);
      expect(find.text('希腊酸奶碗 (2.0份)'), findsOneWidget);
    });

    testWidgets('在日详情中可直接点选常用方案并以自选份量快捷补录加餐', (tester) async {
      final today = todayStr();
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
      );
      final storage = StorageService.instance;
      final presetProvider = PresetProvider();
      final recordProvider = RecordProvider(storage);

      await presetProvider.savePreset(
        name: '黑咖啡',
        calories: 10,
        protein: 1,
        carbs: 1,
        fat: 0,
        unit: '杯',
      );

      await tester.pumpWidget(
        _buildTestApp(
          storage: storage,
          plan: plan,
          presetProvider: presetProvider,
          recordProvider: recordProvider,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => DayDetailSheet(date: today),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();

      // 日详情直接展示常用加餐方案横滑栏
      expect(find.text('常用加餐方案'), findsOneWidget);
      expect(find.text('黑咖啡'), findsOneWidget);

      // 点击常用方案「黑咖啡」，弹出份量选择弹窗
      await tester.tap(find.text('黑咖啡'));
      await tester.pumpAndSettle();

      // 确认弹窗展示基准热量与份量选项
      expect(find.text('基准：10 kcal / 杯'), findsOneWidget);
      expect(find.text('选择份量：'), findsOneWidget);

      // 点击「＋ 确认补录（10 kcal）」
      await tester.tap(find.text('＋ 确认补录（10 kcal）'));
      await tester.pumpAndSettle();

      // 验证日条目已添加
      final snacks = recordProvider.store.dayEntries[today]?.where((e) => e.slot == 'snack').toList() ?? [];
      expect(snacks.any((s) => s.content == '黑咖啡' && s.calories == 10), isTrue);
      expect(find.text('黑咖啡'), findsWidgets);
    });
  });
}
