import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jianfei_dazi/models/nutrition_scan.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/pages/food/food_nutrition_scan_page.dart';
import 'package:jianfei_dazi/providers/preset_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/providers/usage_provider.dart';
import 'package:jianfei_dazi/services/ai_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/theme/app_theme.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';

void main() {
  group('预包装食品配料表与营养成分模型及换算测试', () {
    test('calculate 能够根据摄入克数精确等比例折算热量与三大营养素', () {
      // 假设包装标称：每 100g 含 热量 480 kcal，蛋白质 6.0g，脂肪 20.0g，碳水 69.0g，钠 400mg
      const baseResult = FoodPackageScanResult(
        foodName: '全麦夹心饼干',
        servingSize: 100,
        servingUnit: 'g',
        calories: 480,
        energyKj: 2008,
        protein: 6.0,
        fat: 20.0,
        carbs: 69.0,
        sodium: 400,
        fiber: 4.0,
        ingredients: '全麦粉、植物油、白砂糖、乳粉、食用盐',
        healthTips: ['🟡 含有添加糖', '🔴 脂肪偏高注意控量'],
      );

      // 用户实际手输摄入 50g（半份）
      final calc50 = baseResult.calculate(50);
      expect(calc50.intakeAmount, 50.0);
      expect(calc50.ratio, 0.5);
      expect(calc50.calories, 240); // 480 * 0.5
      expect(calc50.protein, 3.0); // 6.0 * 0.5
      expect(calc50.fat, 10.0); // 20.0 * 0.5
      expect(calc50.carbs, 34.5); // 69.0 * 0.5
      expect(calc50.sodium, 200); // 400 * 0.5
      expect(calc50.fiber, 2.0);

      // 宏量营养素供能比验证
      // 蛋白质供能: 3*4=12; 碳水供能: 34.5*4=138; 脂肪供能: 10*9=90; 合计: 240
      expect(calc50.proteinRatio, closeTo(12.0 / 240.0, 0.01));
      expect(calc50.fatRatio, closeTo(90.0 / 240.0, 0.01));
      expect(calc50.carbsRatio, closeTo(138.0 / 240.0, 0.01));

      // 用户手输摄入 120g
      final calc120 = baseResult.calculate(120);
      expect(calc120.ratio, 1.2);
      expect(calc120.calories, 576); // 480 * 1.2
      expect(calc120.protein, 7.2); // 6.0 * 1.2
      expect(calc120.fat, 24.0); // 20.0 * 1.2
      expect(calc120.carbs, 82.8); // 69.0 * 1.2
      expect(calc120.sodium, 480); // 400 * 1.2
    });

    test('非100g基准（例如每份30g）时，也能准确换算', () {
      const perServing = FoodPackageScanResult(
        foodName: '蛋白棒',
        servingSize: 30,
        servingUnit: 'g',
        calories: 120,
        protein: 10.0,
        fat: 4.0,
        carbs: 11.0,
        sodium: 80,
      );

      // 吃了整根 30g
      final c30 = perServing.calculate(30);
      expect(c30.ratio, 1.0);
      expect(c30.calories, 120);
      expect(c30.protein, 10.0);

      // 吃了两根 60g
      final c60 = perServing.calculate(60);
      expect(c60.ratio, 2.0);
      expect(c60.calories, 240);
      expect(c60.protein, 20.0);
      expect(c60.fat, 8.0);
      expect(c60.carbs, 22.0);
      expect(c60.sodium, 160);
    });

    test('千焦 (kJ) 自动换算为千卡 (kcal) 规则准确', () {
      // 常见中国包装仅标示千焦 1850 kJ
      final json = {
        'foodName': '即食燕麦片',
        'servingSize': 100,
        'servingUnit': 'g',
        'energyKj': 1674, // 1674 kJ / 4.184 ≈ 400 kcal
        'protein': 12.0,
        'fat': 7.0,
        'carbs': 65.0,
        'sodium': 20,
      };

      final parsed = FoodPackageScanResult.fromJson(json);
      expect(parsed.foodName, '即食燕麦片');
      expect(parsed.calories, closeTo(400.0, 1.0));
      expect(parsed.energyKj, 1674.0);
    });

    test('extractFromText 本地智能正则提取离线文本', () {
      const text = '''
项目          每100克(g)       NRV%
能量          1850千焦(kJ)     22%
蛋白质        8.5克(g)         14%
脂肪          16.0克(g)        27%
碳水化合物    62.0克(g)        21%
钠            350毫克(mg)      18%
配料：小麦粉、白砂糖、精炼植物油、食用盐、食品添加剂
''';

      final extracted = FoodPackageScanResult.extractFromText(text);
      expect(extracted.servingSize, 100.0);
      expect(extracted.servingUnit, 'g');
      // 1850 kJ / 4.184 ≈ 442.2 kcal
      expect(extracted.calories, closeTo(442.0, 1.0));
      expect(extracted.protein, 8.5);
      expect(extracted.fat, 16.0);
      expect(extracted.carbs, 62.0);
      expect(extracted.sodium, 350.0);
      expect(extracted.ingredients.contains('小麦粉'), isTrue);
      // 包含白砂糖应触发健康避坑标签
      expect(extracted.healthTips.any((t) => t.contains('添加糖')), isTrue);
    });

    test('AiService.analyzeFoodNutritionPackage 视觉识别与解析完整流', () async {
      AiService.instance.mockVisionHandler = (
        config, {
        required systemPrompt,
        required userPrompt,
        imageBase64,
        mimeType,
        timeoutMs = 60000,
        onUsage,
      }) async {
        return '''
```json
{
  "foodName": "低卡高蛋白无糖酸奶",
  "brand": "简爱",
  "servingSize": 100,
  "servingUnit": "g",
  "calories": 58,
  "energyKj": 243,
  "protein": 5.6,
  "fat": 2.2,
  "carbs": 3.9,
  "sodium": 55,
  "ingredients": "生牛乳、乳酸菌",
  "healthTips": ["🟢 配料表极简", "🟢 高蛋白质", "🟢 低脂无蔗糖"]
}
```
''';
      };

      final result = await AiService.instance.analyzeFoodNutritionPackage(
        AiConfig(provider: 'gemini', apiKey: 'test_key'),
        imageBase64: 'fake_base64_data',
      );

      expect(result.foodName, '低卡高蛋白无糖酸奶');
      expect(result.brand, '简爱');
      expect(result.calories, 58.0);
      expect(result.protein, 5.6);
      expect(result.fat, 2.2);
      expect(result.carbs, 3.9);
      expect(result.sodium, 55.0);
      expect(result.healthTips.length, 3);

      // 输入手输克数 200g（吃了一整盒大罐酸奶）
      final calc200 = result.calculate(200);
      expect(calc200.calories, 116);
      expect(calc200.protein, 11.2);
      expect(calc200.fat, 4.4);
      expect(calc200.carbs, 7.8);
      expect(calc200.sodium, 110);

      // 清理 mock
      AiService.instance.mockVisionHandler = null;
    });

    test('buildRecommendationContext 能够正确集成餐饮倾向与手里现有食材', () {
      const summary = DailySummary(
        plannedIntake: 1400,
        mealIntake: 800,
        tempIntake: 0,
        tempBurn: 0,
        extraIntake: 0,
        planBurn: 200,
        exerciseBurn: 200,
        baseBurn: 1500,
        burn: 1700,
        intake: 800,
        tdee: 1800,
        deficit: 900,
        taskCount: 3,
        doneCount: 2,
      );

      // 1. 自己做 + 现有食材
      final cookContext = buildRecommendationContext(
        summary: summary,
        entries: [],
        now: DateTime(2026, 11, 6, 12, 0),
        targetDeficit: 400,
        mealPreference: 'cook',
        availableIngredients: '鸡蛋, 西红柿, 西兰花',
      );
      expect(cookContext.contains('【用户指定就餐倾向】：🍳 自己做'), isTrue);
      expect(cookContext.contains('【用户手头现有的食材】：鸡蛋, 西红柿, 西兰花'), isTrue);
      expect(cookContext.contains('必须优先充分利用用户现有的上述食材来设计搭配减脂餐'), isTrue);

      // 2. 点外卖（支持美团外卖搜索品类定制）
      final takeoutContext = buildRecommendationContext(
        summary: summary,
        entries: [],
        now: DateTime(2026, 11, 6, 12, 0),
        targetDeficit: 400,
        mealPreference: 'takeout',
        deliveryKeywords: '老乡鸡, 轻食沙拉, 赛百味',
      );
      expect(takeoutContext.contains('【用户指定就餐倾向】：🛵 点外卖'), isTrue);
      expect(takeoutContext.contains('【用户在美团搜索/偏好的外卖品类与店铺】：老乡鸡, 轻食沙拉, 赛百味'), isTrue);
      expect(takeoutContext.contains('避重油重酱的外卖神备注'), isTrue);

      // 3. 去店里吃（支持周围实体店铺如 KFC、麦当劳、黄焖鸡等）
      final dineOutContext = buildRecommendationContext(
        summary: summary,
        entries: [],
        now: DateTime(2026, 11, 6, 12, 0),
        targetDeficit: 400,
        mealPreference: 'dine_out',
        targetStores: '肯德基 (KFC), 麦当劳, 黄焖鸡米饭',
      );
      expect(dineOutContext.contains('【用户指定就餐倾向】：🏬 去店里吃'), isTrue);
      expect(dineOutContext.contains('【用户周围/想要前往的具体实体店铺】：肯德基 (KFC), 麦当劳, 黄焖鸡米饭'), isTrue);
      expect(dineOutContext.contains('绝不踩坑减脂点单方案'), isTrue);
      expect(dineOutContext.contains('去皮吃、过水涮油、牛肉面少面多青菜'), isTrue);
    });

    testWidgets('FoodNutritionScanPage 拍照主推、Telegram风格面板及排版顺序测试', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      SharedPreferences.setMockInitialValues({});
      await StorageService.instance.init();
      final storage = StorageService.instance;
      final setP = SettingsProvider(storage);
      final recP = RecordProvider(storage);
      final presetP = PresetProvider();
      final usageP = UsageProvider(storage);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: setP),
            ChangeNotifierProvider.value(value: recP),
            ChangeNotifierProvider.value(value: presetP),
            ChangeNotifierProvider.value(value: usageP),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const FoodNutritionScanPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 验证拍照为主推按钮存在，且相册与面板按钮均齐备
      expect(find.text('拍照识别 (主推)'), findsOneWidget);
      expect(find.text('相册'), findsOneWidget);

      // 2. 点击 Telegram 风格全览面板按钮，弹出底部弹窗并展示拍照主卡、相册与省 Token 文本
      final telegramBtn = find.byTooltip('Telegram 媒体全览面板');
      expect(telegramBtn, findsOneWidget);
      await tester.tap(telegramBtn);
      await tester.pumpAndSettle();

      expect(find.text('选取包装成分表照片'), findsOneWidget);
      expect(find.text('即时拍照 (主推)'), findsOneWidget);
      expect(find.text('相册选图'), findsOneWidget);
      expect(find.text('输入文本'), findsOneWidget);
      expect(find.textContaining('1280px'), findsOneWidget);

      // 关闭 bottom sheet
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 3. 点击顶部「常见示例」快速体验，模拟识别出欧包
      await tester.tap(find.byTooltip('常见示例'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('全麦黑麦吐司'));
      await tester.pumpAndSettle();

      // 4. 核心排版顺序验证：
      // - 「输入食用克数 · 一键换算清单」在上方
      // - 「记录到今日餐次：」紧随其后
      // - 「食物介绍与各项说明」/「包装标称与配料说明」置于最下方
      final intakeFinder = find.text('输入食用克数 · 一键换算清单');
      final recordMealFinder = find.text('记录到今日餐次：');
      final baseDescFinder = find.text('包装标称与配料说明');

      expect(intakeFinder, findsOneWidget);
      expect(recordMealFinder, findsOneWidget);
      expect(baseDescFinder, findsOneWidget);

      final intakeTop = tester.getTopLeft(intakeFinder).dy;
      final recordMealTop = tester.getTopLeft(recordMealFinder).dy;
      final baseDescTop = tester.getTopLeft(baseDescFinder).dy;

      // 验证坐标自上而下顺序：intakeTop < recordMealTop < baseDescTop
      expect(intakeTop < recordMealTop, isTrue, reason: '食用克数换算应在餐次记录上方');
      expect(recordMealTop < baseDescTop, isTrue, reason: '餐次记录应在各项说明框上方，各项说明框在最下方');

      // 5. 点击「微调基准」按钮，验证成功展开编辑面板，且文本切换为「收起微调」
      final tuneBtn = find.text('微调基准');
      expect(tuneBtn, findsOneWidget);
      await tester.tap(tuneBtn);
      await tester.pumpAndSettle();

      expect(find.text('收起微调'), findsOneWidget);
      expect(find.textContaining('修改包装标称参数'), findsOneWidget);

      // 再次点击收起
      await tester.tap(find.text('收起微调'));
      await tester.pumpAndSettle();
      expect(find.text('微调基准'), findsOneWidget);
    });
  });
}
