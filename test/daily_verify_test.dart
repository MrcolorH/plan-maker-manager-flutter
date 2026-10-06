import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';
import 'package:jianfei_dazi/utils/verify_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VerifyUtils 总结生成与提示词构建测试', () {
    test('generateSummaryText 生成规范包含摄入与消耗的文本', () {
      final entries = [
        DayEntry(
          id: 'm1',
          kind: 'meal',
          slot: 'breakfast',
          time: '08:00',
          content: '水煮蛋2个+燕麦片50g',
          calories: 320,
          protein: 20,
          carbs: 35,
          fat: 10,
          items: const [
            FoodBreakdownItem(name: '水煮蛋', portion: '2个', calories: 150),
            FoodBreakdownItem(name: '燕麦片', portion: '50g', calories: 170),
          ],
        ),
        DayEntry(
          id: 'e1',
          kind: 'exercise',
          time: '18:30',
          content: '慢跑 40 分钟',
          calories: 350,
          detail: '配速 6分半',
        ),
      ];

      const dailySummary = DailySummary(
        plannedIntake: 1500,
        mealIntake: 320,
        tempIntake: 0,
        tempBurn: 0,
        extraIntake: 0,
        planBurn: 350,
        exerciseBurn: 350,
        baseBurn: 1600,
        burn: 1950,
        intake: 320,
        tdee: 1600,
        deficit: 1630,
        taskCount: 2,
        doneCount: 2,
        intakeProtein: 20,
        intakeCarbs: 35,
        intakeFat: 10,
      );

      final text = VerifyUtils.generateSummaryText(
        date: '2026-10-06',
        entries: entries,
        dailySummary: dailySummary,
      );

      expect(text, contains('2026-10-06'));
      expect(text, contains('水煮蛋2个+燕麦片50g'));
      expect(text, contains('320 kcal'));
      expect(text, contains('水煮蛋(2个)≈150kcal'));
      expect(text, contains('慢跑 40 分钟'));
      expect(text, contains('350 kcal'));
      expect(text, contains('今日热量缺口：+1630 kcal'));
    });

    test('generateSummaryText 严格排除未打卡的预设计划项', () {
      final entries = [
        DayEntry(
          id: 'p1',
          kind: 'meal',
          slot: 'breakfast',
          content: '已打卡的早餐',
          source: 'plan',
          planItemId: 'item_1',
          calories: 300,
        ),
        DayEntry(
          id: 'p2',
          kind: 'meal',
          slot: 'lunch',
          content: '未打卡的预设计划午餐',
          source: 'plan',
          planItemId: 'item_2',
          calories: 600,
        ),
        DayEntry(
          id: 'e_plan',
          kind: 'exercise',
          content: '未打卡的预设计划运动',
          source: 'plan',
          planItemId: 'item_3',
          calories: 200,
        ),
        DayEntry(
          id: 'extra_snack',
          kind: 'meal',
          slot: 'snack',
          content: '实际吃的加餐苹果',
          source: 'manual',
          calories: 90,
        ),
      ];

      // 仅 p1 打卡了，p2 和 e_plan 未打卡
      bool mockChecked(DayEntry e) => e.id == 'p1';

      final text = VerifyUtils.generateSummaryText(
        date: '2026-10-06',
        entries: entries,
        isChecked: mockChecked,
      );

      // 已打卡的正餐和实际加餐应当被包含
      expect(text, contains('已打卡的早餐'));
      expect(text, contains('实际吃的加餐苹果'));

      // 未打卡的预设计划餐和计划运动绝对不能被包含！
      expect(text, isNot(contains('未打卡的预设计划午餐')));
      expect(text, isNot(contains('未打卡的预设计划运动')));
    });

    test('buildVerifyPrompt 拼装包含总结与严格格式约束', () {
      const summary = '早餐：燕麦粥一份 300kcal';
      final prompt = VerifyUtils.buildVerifyPrompt(summary);

      expect(prompt, contains('早餐：燕麦粥一份 300kcal'));
      expect(prompt, contains('overall'));
      expect(prompt, contains('corrected_calories'));
      expect(prompt, contains('这里必须100%一字不差复制对应的【原始输入】文本'));
    });
  });

  group('VerifyUtils 纠偏结果解析与多级匹配测试', () {
    final testEntries = [
      DayEntry(
        id: 'm1',
        kind: 'meal',
        slot: 'lunch',
        content: '外卖黄焖鸡米饭一份',
        calories: 680,
        protein: 30,
        carbs: 80,
        fat: 25,
      ),
      DayEntry(
        id: 'm2',
        kind: 'meal',
        slot: 'dinner',
        content: '西红柿炒蛋，米饭一碗',
        calories: 450,
        protein: 16,
        carbs: 55,
        fat: 18,
      ),
      DayEntry(
        id: 'e1',
        kind: 'exercise',
        content: '慢跑 5 公里',
        calories: 320,
      ),
    ];

    test('解析标准 JSON 并精确匹配条目', () {
      const aiResponse = '''
```json
{
  "overall": "存在偏差",
  "summary": "午餐黄焖鸡米饭偏油，热量低估；运动消耗估算合理",
  "items": [
    {
      "content": "外卖黄焖鸡米饭一份",
      "status": "偏差",
      "issue": "外卖重油且汤汁泡饭，热量约750kcal",
      "corrected_calories": 750,
      "corrected_protein": 32,
      "corrected_carbs": 82,
      "corrected_fat": 32
    },
    {
      "content": "西红柿炒蛋，米饭一碗",
      "status": "准确",
      "issue": "",
      "corrected_calories": 450,
      "corrected_protein": 16,
      "corrected_carbs": 55,
      "corrected_fat": 18
    },
    {
      "content": "慢跑 5 公里",
      "status": "准确",
      "issue": "",
      "corrected_calories": 320
    }
  ]
}
```
''';

      final res = VerifyUtils.parseCorrectionResult(aiResponse, testEntries);
      expect(res, isNotNull);
      expect(res!.overall, '存在偏差');
      expect(res.items.length, 3);

      final item1 = res.items[0];
      expect(item1.matchedEntry, isNotNull);
      expect(item1.matchedEntry!.id, 'm1');
      expect(item1.isDifferent, isTrue);
      expect(item1.calories, 750);

      final item2 = res.items[1];
      expect(item2.matchedEntry, isNotNull);
      expect(item2.matchedEntry!.id, 'm2');
      expect(item2.isDifferent, isFalse);
    });

    test('多级匹配算法：标点差异与模糊包含仍可正确匹配', () {
      const aiResponse = '''
{
  "overall": "准确",
  "summary": "大致准确",
  "items": [
    {
      "content": "西红柿炒蛋 米饭一碗",
      "status": "准确",
      "corrected_calories": 430
    },
    {
      "content": "黄焖鸡米饭",
      "status": "准确",
      "corrected_calories": 650
    }
  ]
}
''';

      final res = VerifyUtils.parseCorrectionResult(aiResponse, testEntries);
      expect(res, isNotNull);
      expect(res!.items.length, 2);

      // 第一项：去标点归一化匹配 "西红柿炒蛋 米饭一碗" -> "西红柿炒蛋，米饭一碗"
      expect(res.items[0].matchedEntry?.id, 'm2');
      expect(res.items[0].calories, 430);

      // 第二项：包含匹配 "黄焖鸡米饭" -> "外卖黄焖鸡米饭一份"
      expect(res.items[1].matchedEntry?.id, 'm1');
    });

    test('异常格式容错：非 JSON 文本返回 null', () {
      final res = VerifyUtils.parseCorrectionResult('抱歉我无法完成校验', testEntries);
      expect(res, isNull);
    });
  });

  group('RecordProvider.batchUpdateEntryCalories 安全纠偏核心铁律测试', () {
    late RecordProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService.instance;
      await storage.init();
      provider = RecordProvider(storage);
    });

    test('严格只修改估算数值，绝不修改用户原始输入 content', () async {
      const date = '2026-10-06';
      final originalEntry = DayEntry(
        id: 'entry_target',
        kind: 'meal',
        slot: 'lunch',
        content: '我爱吃的大碗麻辣烫（加很多麻酱）',
        calories: 600,
        protein: 15,
        carbs: 60,
        fat: 30,
        detached: false,
        caloriesDirty: false,
      );

      final otherEntry = DayEntry(
        id: 'entry_other',
        kind: 'meal',
        slot: 'dinner',
        content: '一根黄瓜',
        calories: 30,
        protein: 1,
        carbs: 5,
        fat: 0,
      );

      // 录入初始条目
      provider.store.dayEntries[date] = [originalEntry, otherEntry];

      // 构造纠偏请求（纠偏数据即使携带了不同的文本描述）
      final corrections = [
        CorrectionItem(
          content: '麻辣烫',
          calories: 850,
          protein: 22,
          carbs: 70,
          fat: 45,
          matchedEntry: originalEntry,
        ),
      ];

      final count = await provider.batchUpdateEntryCalories(date, corrections);
      expect(count, 1);

      final updatedList = provider.store.dayEntries[date]!;
      final updatedTarget = updatedList.firstWhere((e) => e.id == 'entry_target');

      // 【核心铁律断言】
      // 1. 用户原始输入 content 绝不能被任何自动化逻辑篡改！
      expect(updatedTarget.content, '我爱吃的大碗麻辣烫（加很多麻酱）');
      // 2. 估算热量与宏量营养素必须按新值更新
      expect(updatedTarget.calories, 850);
      expect(updatedTarget.protein, 22);
      expect(updatedTarget.carbs, 70);
      expect(updatedTarget.fat, 45);
      // 3. 必须标记 caloriesDirty = true，防止未来被长期计划覆盖
      expect(updatedTarget.caloriesDirty, isTrue);

      // 未纠偏的条目不受任何影响
      final unchangedOther = updatedList.firstWhere((e) => e.id == 'entry_other');
      expect(unchangedOther.content, '一根黄瓜');
      expect(unchangedOther.calories, 30);
    });

    test('addDayEntry 自动将用户手动记录的加餐与临时运动标记为已打卡', () async {
      const date = '2026-10-06';
      await provider.addDayEntry(
        date,
        kind: 'meal',
        slot: 'snack',
        content: '下午茶蛋挞1个',
        calories: 220,
      );

      final entries = provider.store.dayEntries[date]!;
      expect(entries.length, 1);
      final snack = entries.first;

      // 手动添加的加餐应当被自动打卡（已吃）
      expect(provider.isEntryChecked(date, snack), isTrue);

      // 临时运动也是添加即打卡（已练）
      await provider.addDayEntry(
        date,
        kind: 'exercise',
        content: '跳绳 500 下',
        calories: 80,
      );
      final exercise = provider.store.dayEntries[date]!.last;
      expect(provider.isEntryChecked(date, exercise), isTrue);
    });
  });
}
