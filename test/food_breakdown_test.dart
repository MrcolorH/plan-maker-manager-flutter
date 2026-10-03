import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/data/food_db.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/services/ai_service.dart';

void main() {
  group('食物拆解表格与解析测试 (1.0.1)', () {
    test('parseBreakdownFromText 能够准确解析各种 AI 分项拆解文本', () {
      const text1 = '米饭100g≈116，炒茄子1/4盘(含油约2.5g)≈45，合计161';
      final list1 = AiService.parseBreakdownFromText(text1);
      expect(list1.length, 2);
      expect(list1[0].name, '米饭');
      expect(list1[0].portion, '100g');
      expect(list1[0].calories, 116);
      expect(list1[1].name.contains('炒茄子'), true);
      expect(list1[1].calories, 45);

      const text2 = '鸡胸肉150g≈200(P45g)，橄榄油5g≈45，米饭150g≈175，合计420';
      final list2 = AiService.parseBreakdownFromText(text2);
      expect(list2.length, 3);
      expect(list2[0].name, '鸡胸肉');
      expect(list2[0].portion, '150g');
      expect(list2[0].calories, 200);
      expect(list2[1].name, '橄榄油');
      expect(list2[1].portion, '5g');
      expect(list2[1].calories, 45);
      expect(list2[2].name, '米饭');
      expect(list2[2].portion, '150g');
      expect(list2[2].calories, 175);
    });

    test('parseBreakdownFromText 能够解析端侧食物库命中格式', () {
      const text = '牛肉面(1碗, 550kcal) + 葡式蛋挞(1个, 290kcal)';
      final list = AiService.parseBreakdownFromText(text);
      expect(list.length, 2);
      expect(list[0].name, '牛肉面');
      expect(list[0].portion, '1碗');
      expect(list[0].calories, 550);
      expect(list[1].name, '葡式蛋挞');
      expect(list[1].portion, '1个');
      expect(list[1].calories, 290);
    });

    test('DayEntry 能够正确序列化与反序列化 items 和 detail', () {
      final entry = DayEntry(
        id: 'test_m1',
        kind: 'meal',
        slot: 'lunch',
        time: '12:00',
        content: '黄焖鸡米饭',
        calories: 620,
        protein: 35,
        carbs: 70,
        fat: 20,
        note: '少放油',
        source: 'plan',
        planItemId: 'p1',
        detached: true,
        caloriesDirty: true,
        detail: '米饭200g≈232，带皮鸡腿肉150g≈270，青椒香菇80g≈25，合计527',
        items: const [
          FoodBreakdownItem(name: '米饭', portion: '200g', calories: 232),
          FoodBreakdownItem(name: '带皮鸡腿肉', portion: '150g', calories: 270),
          FoodBreakdownItem(name: '青椒香菇', portion: '80g', calories: 25),
        ],
      );

      final json = entry.toJson();
      expect(json['detail'], isNotNull);
      expect(json['items'], isA<List>());
      expect((json['items'] as List).length, 3);

      final restored = DayEntry.fromJson(json);
      expect(restored.id, 'test_m1');
      expect(restored.content, '黄焖鸡米饭');
      expect(restored.detail, entry.detail);
      expect(restored.items, isNotNull);
      expect(restored.items!.length, 3);
      expect(restored.items![0].name, '米饭');
      expect(restored.items![0].portion, '200g');
      expect(restored.items![0].calories, 232);
    });

    test('matchAndCalculateFood 本地食物库自动输出 breakdownItems', () {
      final match = matchAndCalculateFood('葡式蛋挞');
      expect(match, isNotNull);
      expect(match!.breakdownItems.isNotEmpty, true);
      expect(match.breakdownItems[0].name, '葡式蛋挞');
      expect(match.breakdownItems[0].calories, 290);
    });
  });
}
