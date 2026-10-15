/// 日历视图与某日详情弹层校验入口测试
/// 覆盖：
/// 1. 查看昨天详情：展示「昨日校验（AI 识别与热量二次核验）」入口，点击唤起校验页
/// 2. 查看今天详情：展示「今日校验（AI 识别与热量二次核验）」入口
/// 3. 未来日期：不展示校验入口
/// 4. DailyVerifyPage 根据日期自适应标题与文案（今天：今日校验；昨天：昨日校验；其他过去日期：热量校验）
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/pages/stats/stats_page.dart';
import 'package:jianfei_dazi/pages/today/daily_verify_page.dart';
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

Widget buildTestWidget({
  required Widget child,
  required StorageService storage,
  PlanData? plan,
  void Function(RecordProvider)? onSetupRecords,
}) {
  final reminder = _FakeReminderService();
  final recP = RecordProvider(storage);
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
  final presetP = PresetProvider();
  if (onSetupRecords != null) {
    onSetupRecords(recP);
  }

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

  group('日历某日详情弹层校验入口展示测试', () {
    testWidgets('查看昨天详情展示「昨日校验（AI 识别与热量二次核验）」且点击可进入校验页面', (tester) async {
      final today = todayStr();
      final yesterday = addDays(today, -1);
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
        meals: [
          MealItem(id: 'm1', type: 'breakfast', name: '全麦面包', calories: 200),
        ],
      );

      await tester.pumpWidget(
        buildTestWidget(
          storage: StorageService.instance,
          plan: plan,
          onSetupRecords: (recP) {
            recP.store.dayEntries[yesterday] = [
              DayEntry(
                id: 'e_yes_1',
                kind: 'meal',
                slot: 'breakfast',
                content: '燕麦牛奶',
                calories: 250,
              ),
            ];
            recP.store.checkRecords[yesterday] = {
              'temp:e_yes_1': CheckEntry(checkedAt: 1728800000000),
            };
          },
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  builder: (_) => DayDetailSheet(date: yesterday),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      );

      // 打开弹层
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();

      // 验证存在昨日校验入口
      expect(find.text('昨日校验（AI 识别与热量二次核验）'), findsOneWidget);

      // 点击进入校验页面
      await tester.tap(find.text('昨日校验（AI 识别与热量二次核验）'));
      await tester.pumpAndSettle();

      // 验证 DailyVerifyPage 展现自适应标题与总结
      expect(find.byType(DailyVerifyPage), findsOneWidget);
      expect(find.text('昨日校验 · $yesterday'), findsOneWidget);
      expect(find.text('昨日条目总结'), findsOneWidget);
      expect(find.textContaining('燕麦牛奶'), findsOneWidget);
    });

    testWidgets('查看今天详情展示「今日校验（AI 识别与热量二次核验）」', (tester) async {
      final today = todayStr();
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
      );

      await tester.pumpWidget(
        buildTestWidget(
          storage: StorageService.instance,
          plan: plan,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
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

      expect(find.text('今日校验（AI 识别与热量二次核验）'), findsOneWidget);
    });

    testWidgets('查看未来日期不展示校验入口', (tester) async {
      final today = todayStr();
      final futureDate = addDays(today, 3);
      final plan = PlanData(
        meta: PlanMeta(startedAt: addDays(today, -10)),
      );

      await tester.pumpWidget(
        buildTestWidget(
          storage: StorageService.instance,
          plan: plan,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: ctx,
                  builder: (_) => DayDetailSheet(date: futureDate),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();

      expect(find.textContaining('校验（AI 识别与热量二次核验）'), findsNothing);
    });
  });

  group('DailyVerifyPage 自适应标题与文案测试', () {
    testWidgets('更早过去的日期显示「热量校验」与对应总结标题', (tester) async {
      final today = todayStr();
      final pastDate = addDays(today, -4);

      await tester.pumpWidget(
        buildTestWidget(
          storage: StorageService.instance,
          plan: PlanData(),
          child: DailyVerifyPage(date: pastDate),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('热量校验 · $pastDate'), findsOneWidget);
      expect(find.text('${dateCn(pastDate)}条目总结'), findsOneWidget);
    });
  });
}
