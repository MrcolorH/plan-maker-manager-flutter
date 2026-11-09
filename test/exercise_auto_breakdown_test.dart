import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/pages/today/today_page.dart';
import 'package:jianfei_dazi/pages/stats/stats_page.dart';
import 'package:jianfei_dazi/providers/app_provider.dart';
import 'package:jianfei_dazi/providers/onboarding_provider.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/preset_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/providers/usage_provider.dart';
import 'package:jianfei_dazi/services/ai_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/theme/app_theme.dart';
import 'package:jianfei_dazi/utils/date_utils.dart';
import 'package:jianfei_dazi/widgets/exercise_breakdown_table.dart';

Widget _buildTestApp({
  required StorageService storage,
  required RecordProvider recP,
  required SettingsProvider setP,
  required PlanProvider planP,
  required OnboardingProvider onbP,
  required PresetProvider presetP,
  required UsageProvider usageP,
  required AppProvider appP,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: planP),
      ChangeNotifierProvider.value(value: recP),
      ChangeNotifierProvider.value(value: setP),
      ChangeNotifierProvider.value(value: onbP),
      ChangeNotifierProvider.value(value: presetP),
      ChangeNotifierProvider.value(value: usageP),
      ChangeNotifierProvider.value(value: appP),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late RecordProvider recP;
  late SettingsProvider setP;
  late PlanProvider planP;
  late OnboardingProvider onbP;
  late PresetProvider presetP;
  late UsageProvider usageP;
  late AppProvider appP;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService.instance;
    await storage.init();
    recP = RecordProvider(storage);
    setP = SettingsProvider(storage);
    planP = PlanProvider(storage, setP, recP);
    onbP = OnboardingProvider(storage, planP, setP, recP);
    onbP.state.done = true;
    presetP = PresetProvider();
    usageP = UsageProvider(storage);
    appP = AppProvider();

    // 配置好 AI Profile 并激活
    await setP.addAiProfile(AiConfig(
      provider: 'custom',
      endpoint: 'https://api.test.com',
      apiKey: 'test_key',
      model: 'test-model',
    ));
  });

  group('运动录入时自动拆解功能测试', () {
    testWidgets('在今日页点击「＋ 今日运动」录入，输入描述后自动拆解并落库明细', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      planP.plan = PlanData(meta: PlanMeta(startedAt: addDays(todayStr(), -5)));
      await recP.syncDayEntries(todayStr(), planP.plan);

      // 模拟 AiService
      AiService.instance.mockChatHandler = (config, messages, {bool enableThinking = false, int timeoutMs = 60000, void Function(Map<String, dynamic>)? onUsage}) async {
        return '''{
          "name": "慢跑与拉伸",
          "calories": 250,
          "items": [
            {"name": "室外慢跑", "portion": "30分钟", "calories": 220},
            {"name": "静态拉伸", "portion": "10分钟", "calories": 30}
          ],
          "detail": "慢跑30分钟≈220，静态拉伸10分钟≈30，合计250"
        }''';
      };

      await tester.pumpWidget(
        _buildTestApp(
          storage: storage,
          recP: recP,
          setP: setP,
          planP: planP,
          onbP: onbP,
          presetP: presetP,
          usageP: usageP,
          appP: appP,
          child: const TodayPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 找到「＋ 今日运动」并确保可见
      final addExBtn = find.text('＋ 今日运动');
      await tester.ensureVisible(addExBtn);
      await tester.tap(addExBtn);
      await tester.pumpAndSettle();

      // 验证弹层标题和 AI 自动拆解标签
      expect(find.text('AI 自动拆解'), findsOneWidget);

      // 输入运动描述
      final descField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText?.contains('描述运动') ?? false),
      );
      expect(descField, findsOneWidget);
      await tester.enterText(descField, '慢跑30分钟，拉伸10分钟');
      await tester.pump();

      // 等待防抖计时器（700ms）触发自动拆解
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // 验证拆解表格在录入弹窗中直接展示
      expect(find.byType(ExerciseBreakdownTable), findsOneWidget);
      expect(find.text('室外慢跑'), findsOneWidget);
      expect(find.text('30分钟'), findsOneWidget);
      expect(find.text('-220 kcal'), findsOneWidget);
      expect(find.text('静态拉伸'), findsOneWidget);
      expect(find.text('10分钟'), findsOneWidget);
      expect(find.text('-30 kcal'), findsOneWidget);

      // 运动名和消耗输入框被自动回填
      expect(find.text('慢跑与拉伸'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);

      // 点击「记录（计入今日消耗）」
      await tester.tap(find.text('记录（计入今日消耗）'));
      await tester.pumpAndSettle();

      // 验证记录落库：包含 items、detail 且 source 为 ai
      final today = todayStr();
      final entries = recP.getDayEntries(today);
      final savedEx = entries.firstWhere((e) => e.kind == 'exercise');
      expect(savedEx.content, '慢跑与拉伸');
      expect(savedEx.calories, 250);
      expect(savedEx.source, 'ai');
      expect(savedEx.detail, contains('慢跑30分钟≈220'));
      expect(savedEx.items, isNotNull);
      expect(savedEx.items!.length, 2);
      expect(savedEx.items![0].name, '室外慢跑');
      expect(savedEx.items![0].portion, '30分钟');
      expect(savedEx.items![0].calories, 220);
      expect(savedEx.items![1].name, '静态拉伸');
      expect(savedEx.items![1].portion, '10分钟');
      expect(savedEx.items![1].calories, 30);
    });

    testWidgets('输入描述后不等防抖直接点击「记录」，系统自动先拆解再保存落库', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      planP.plan = PlanData(meta: PlanMeta(startedAt: addDays(todayStr(), -5)));
      await recP.syncDayEntries(todayStr(), planP.plan);

      AiService.instance.mockChatHandler = (config, messages, {bool enableThinking = false, int timeoutMs = 60000, void Function(Map<String, dynamic>)? onUsage}) async {
        return '''{
          "name": "跳绳减脂",
          "calories": 180,
          "items": [
            {"name": "双脚跳绳", "portion": "1000个", "calories": 150},
            {"name": "小腿拉伸", "portion": "5分钟", "calories": 30}
          ],
          "detail": "双脚跳绳1000个≈150，小腿拉伸5分钟≈30，合计180"
        }''';
      };

      await tester.pumpWidget(
        _buildTestApp(
          storage: storage,
          recP: recP,
          setP: setP,
          planP: planP,
          onbP: onbP,
          presetP: presetP,
          usageP: usageP,
          appP: appP,
          child: const TodayPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 打开弹层
      final addExBtn = find.text('＋ 今日运动');
      await tester.ensureVisible(addExBtn);
      await tester.tap(addExBtn);
      await tester.pumpAndSettle();

      // 输入后直接点击记录
      final descField = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.hintText?.contains('描述运动') ?? false),
      );
      expect(descField, findsOneWidget);
      await tester.enterText(descField, '跳绳1000个加拉伸');
      await tester.pump();

      // 不等待 700ms 防抖，直接点「记录（计入今日消耗）」
      await tester.tap(find.text('记录（计入今日消耗）'));
      await tester.pumpAndSettle();

      // 验证自动触发拆解后成功保存
      final today = todayStr();
      final entries = recP.getDayEntries(today);
      final savedEx = entries.firstWhere((e) => e.content == '跳绳减脂');
      expect(savedEx.calories, 180);
      expect(savedEx.source, 'ai');
      expect(savedEx.items, isNotNull);
      expect(savedEx.items!.length, 2);
      expect(savedEx.items![0].name, '双脚跳绳');
      expect(savedEx.items![0].calories, 150);
      expect(savedEx.items![1].name, '小腿拉伸');
      expect(savedEx.items![1].calories, 30);
    });

    testWidgets('在统计页补录运动时，自动拆解展示表格并保存明细', (tester) async {
      AiService.instance.mockChatHandler = (config, messages, {bool enableThinking = false, int timeoutMs = 60000, void Function(Map<String, dynamic>)? onUsage}) async {
        return '''{
          "name": "游泳训练",
          "calories": 320,
          "items": [
            {"name": "自由泳", "portion": "45分钟", "calories": 320}
          ],
          "detail": "自由泳45分钟≈320，合计320"
        }''';
      };

      const targetDate = '2026-10-10';
      await tester.pumpWidget(
        _buildTestApp(
          storage: storage,
          recP: recP,
          setP: setP,
          planP: planP,
          onbP: onbP,
          presetP: presetP,
          usageP: usageP,
          appP: appP,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const StatsPage(),
                );
                // 模拟打开补录锻炼弹窗
                showModalBottomSheet<void>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => DayDetailSheet(date: targetDate),
                );
              },
              child: const Text('打开测试'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开补录锻炼弹层
      await tester.tap(find.text('打开测试'));
      await tester.pumpAndSettle();

      // 在 DayDetailSheet 中点击「＋ 补录锻炼」
      final addExBtn = find.text('＋ 补录锻炼');
      if (addExBtn.evaluate().isNotEmpty) {
        await tester.tap(addExBtn);
        await tester.pumpAndSettle();

        // 验证弹层
        expect(find.text('补录锻炼'), findsOneWidget);

        // 输入描述
        final descField = find.byType(TextField).first;
        await tester.enterText(descField, '自由泳45分钟');
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pumpAndSettle();

        // 验证表格展示
        expect(find.byType(ExerciseBreakdownTable), findsOneWidget);
        expect(find.text('自由泳'), findsOneWidget);
        expect(find.text('-320 kcal'), findsOneWidget);

        // 点击确认补录
        await tester.tap(find.text('＋ 确认补录（320 kcal）'));
        await tester.pumpAndSettle();

        // 验证落库
        final entries = recP.getDayEntries(targetDate);
        final saved = entries.firstWhere((e) => e.kind == 'exercise');
        expect(saved.content, '游泳训练');
        expect(saved.calories, 320);
        expect(saved.source, 'ai');
        expect(saved.items, isNotNull);
        expect(saved.items![0].name, '自由泳');
        expect(saved.items![0].calories, 320);
      }
    });
  });
}
