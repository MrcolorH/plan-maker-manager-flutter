import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jianfei_dazi/data/food_db.dart';
import 'package:jianfei_dazi/services/preset_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
  });

  group('matchAndCalculateFood tests', () {
    test('matches built-in foods with quantity modifiers', () {
      // 1. 半个香辣鸡腿堡 (590 * 0.5 = 295)
      final r1 = matchAndCalculateFood('半个香辣鸡腿堡');
      expect(r1, isNotNull);
      expect(r1!.food.name, '香辣鸡腿堡');
      expect(r1.quantity, 0.5);
      expect(r1.totalCalories, 295);
      expect(r1.isUserCustom, isFalse);

      // 2. 2个香辣鸡腿堡 (590 * 2 = 1180)
      final r2 = matchAndCalculateFood('2个香辣鸡腿堡');
      expect(r2, isNotNull);
      expect(r2!.quantity, 2.0);
      expect(r2.totalCalories, 1180);

      // 3. 两个水煮蛋 (70 * 2 = 140)
      final r3 = matchAndCalculateFood('两个水煮蛋');
      expect(r3, isNotNull);
      expect(r3!.food.name, '水煮蛋');
      expect(r3.quantity, 2.0);
      expect(r3.totalCalories, 140);

      // 4. 水煮蛋2个 (后置数量词)
      final r4 = matchAndCalculateFood('水煮蛋2个');
      expect(r4, isNotNull);
      expect(r4!.quantity, 2.0);
      expect(r4.totalCalories, 140);

      // 5. 200g白米饭 (白米饭基准 230 kcal / 1碗200g)
      final r5 = matchAndCalculateFood('200g白米饭');
      expect(r5, isNotNull);
      expect(r5!.totalCalories, 230);

      // 6. 100g白米饭 (230 * 0.5 = 115)
      final r6 = matchAndCalculateFood('100g白米饭');
      expect(r6, isNotNull);
      expect(r6!.totalCalories, 115);

      // 7. 未收录食物返回 null
      final r7 = matchAndCalculateFood('太空超级秘制分子料理');
      expect(r7, isNull);
    });
  });

  group('extractUnitFood & UserFood flywheel tests', () {
    test('extractUnitFood normalizes base quantity and calories', () {
      // 半个香辣鸡腿堡 295 kcal -> 590 kcal
      final f1 = extractUnitFood(name: '半个香辣鸡腿堡', calories: 295, protein: 12);
      expect(f1.name, '香辣鸡腿堡');
      expect(f1.calories, 590);
      expect(f1.protein, 24);
      expect(f1.unit, '1个');
      expect(f1.isUserCustom, isTrue);

      // 2个水煮蛋 140 kcal -> 70 kcal
      final f2 = extractUnitFood(name: '2个水煮蛋', calories: 140, protein: 14);
      expect(f2.name, '水煮蛋');
      expect(f2.calories, 70);
      expect(f2.protein, 7);

      // 无数量修饰
      final f3 = extractUnitFood(name: '牛油果奶昔', calories: 320, unit: '1杯');
      expect(f3.name, '牛油果奶昔');
      expect(f3.calories, 320);
      expect(f3.unit, '1杯');
    });

    test('PresetService saves preset and automatically feeds UserFood library', () async {
      final service = PresetService(StorageService.instance);
      expect(service.getUserFoods(), isEmpty);

      // 用户采纳并存入常用方案「半个全麦牛肉卷 220 kcal」
      await service.savePreset(
        name: '半个全麦牛肉卷',
        calories: 220,
        protein: 16,
        carbs: 20,
        fat: 8,
      );

      // 验证常用方案已存
      final presets = service.getPresets();
      expect(presets.length, 1);
      expect(presets.first.name, '半个全麦牛肉卷');

      // 验证已自动归一化沉淀到用户自定义食物库（基准变为 440 kcal）
      final userFoods = service.getUserFoods();
      expect(userFoods.length, 1);
      final customFood = userFoods.first;
      expect(customFood.name, '全麦牛肉卷');
      expect(customFood.calories, 440);
      expect(customFood.protein, 32);
      expect(customFood.isUserCustom, isTrue);

      // 验证后续使用该自定义库进行匹配计算
      // 1) 输入整份「全麦牛肉卷」
      final match1 = matchAndCalculateFood('全麦牛肉卷', userFoods: userFoods);
      expect(match1, isNotNull);
      expect(match1!.totalCalories, 440);
      expect(match1.isUserCustom, isTrue);

      // 2) 输入「2个全麦牛肉卷」
      final match2 = matchAndCalculateFood('2个全麦牛肉卷', userFoods: userFoods);
      expect(match2, isNotNull);
      expect(match2!.totalCalories, 880);
      expect(match2.totalProtein, 64);
    });

    test('PresetService can delete presets and custom user foods', () async {
      final service = PresetService(StorageService.instance);
      final p = await service.savePreset(name: '美式咖啡', calories: 10);
      expect(service.getPresets().length, 1);

      await service.deletePreset(p.id);
      expect(service.getPresets(), isEmpty);

      final userFoods = service.getUserFoods();
      expect(userFoods.length, 1);
      await service.deleteUserFood(userFoods.first.id);
      expect(service.getUserFoods(), isEmpty);
    });
  });
}
