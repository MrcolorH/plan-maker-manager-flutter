import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/services/ai_service.dart';

void main() {
  group('Food Breakdown Parsing & Sanitizing Tests', () {
    test('TC-01: Parse detail with math formula and ensure no blank or numeric items', () {
      const detail =
          '白米饭200g≈232，清炒西兰花48g≈26，炒蒜苔44g≈33，瘦肉片37g≈55，豆腐皮丝15g≈31，辣炒鸡胗40g≈59，卤肉块26g≈70，26+33+55+31+59+70=506，合计 506 kcal';

      final res = AiService.parseBreakdownFromText(detail);
      expect(res.length, 7);
      expect(res[0].name, '白米饭');
      expect(res[0].portion, '200g');
      expect(res[0].calories, 232);

      expect(res[1].name, '清炒西兰花');
      expect(res[1].portion, '48g');
      expect(res[1].calories, 26);

      expect(res[6].name, '卤肉块');
      expect(res[6].portion, '26g');
      expect(res[6].calories, 70);

      // 确保没有任何空名称、纯数字名称、或异常项
      for (final item in res) {
        expect(item.name.trim().isNotEmpty, isTrue);
        expect(RegExp(r'^\d+$').hasMatch(item.name), isFalse);
        expect(item.name, isNot(contains('合计')));
      }
    });

    test('TC-02: Parse multi-line structured AI conversation text directly', () {
      const text = '''
收到，萌萌这就把菜品总重按210g重新等比例缩放计算，米饭依然按原来的200g单独保留。

原先菜品总重是285g（485g减去200g米饭），调整到210g后，缩放系数约为0.737。

修正后的餐品明细：

1. 白米饭（单独核算）
预估克数：200g
预估热量：232 kcal
蛋白质：5.2g / 脂肪：0.6g / 碳水：51.8g

2. 清炒西兰花
预估克数：48g
预估热量：26 kcal
蛋白质：1.3g / 脂肪：1.5g / 碳水：2.1g

3. 炒蒜苔
预估克数：44g
预估热量：33 kcal
蛋白质：0.9g / 脂肪：1.8g / 碳水：3.5g

4. 水煮/清炒瘦肉片
预估克数：37g
预估热量：55 kcal
蛋白质：7.8g / 脂肪：2.2g / 碳水：0.7g

5. 卤/炒豆腐皮丝
预估克数：15g
预估热量：31 kcal
蛋白质：2.6g / 脂肪：1.5g / 碳水：1.6g

6. 辣炒鸡胗/鸭胗
预估克数：40g
预估热量：59 kcal
蛋白质：7.0g / 脂肪：2.6g / 碳水：1.8g

7. 红烧/卤肉块
预估克数：26g
预估热量：70 kcal
蛋白质：4.4g / 脂肪：5.5g / 碳水：0.9g

修正后总计与营养小结：
菜品总重：210g
米饭重量：200g
整餐总重：410g

预估总热量：约 506 kcal
蛋白质总量：约 29.2g
脂肪总量：约 15.7g
碳水总量：约 62.4g

重新校准后，整餐热量控制在500大卡左右，不仅有近30g的优质蛋白，脂肪也压得很健康，搭配非常扎实。

如无误可回复【确认】，我将为您结束本次记录。

👉 请核对以上识别是否有误？如果您知道某道菜或整盒饭菜的实际称重（克数），也可以告诉我，我将按真实重量为您重新精细计算！
''';

      final res = AiService.parseBreakdownFromText(text);
      expect(res.length, 7);
      expect(res[0].name, '白米饭（单独核算）');
      expect(res[0].portion, '200g');
      expect(res[0].calories, 232);

      expect(res[1].name, '清炒西兰花');
      expect(res[1].portion, '48g');
      expect(res[1].calories, 26);

      expect(res[2].name, '炒蒜苔');
      expect(res[2].portion, '44g');
      expect(res[2].calories, 33);

      expect(res[3].name, '水煮/清炒瘦肉片');
      expect(res[3].portion, '37g');
      expect(res[3].calories, 55);

      expect(res[4].name, '卤/炒豆腐皮丝');
      expect(res[4].portion, '15g');
      expect(res[4].calories, 31);

      expect(res[5].name, '辣炒鸡胗/鸭胗');
      expect(res[5].portion, '40g');
      expect(res[5].calories, 59);

      expect(res[6].name, '红烧/卤肉块');
      expect(res[6].portion, '26g');
      expect(res[6].calories, 70);
    });

    test('TC-03: parseBreakdownItems filters out noise items from rawItems list', () {
      final rawItems = [
        {'name': '白米饭', 'portion': '200g', 'calories': 232},
        {'name': '', 'portion': '-', 'calories': 26},
        {'name': ' ', 'portion': '-', 'calories': 33},
        {'name': '70', 'portion': '-', 'calories': 506},
        {'name': '菜品总重', 'portion': '210g', 'calories': 0},
        {'name': '合计', 'portion': '', 'calories': 506},
        {'name': '清炒西兰花', 'portion': '48g', 'calories': 26},
      ];

      final res = AiService.parseBreakdownItems(rawItems, null);
      expect(res.length, 2);
      expect(res[0].name, '白米饭');
      expect(res[0].portion, '200g');
      expect(res[0].calories, 232);
      expect(res[1].name, '清炒西兰花');
      expect(res[1].portion, '48g');
      expect(res[1].calories, 26);
    });

    test('TC-04: reconcileCalorieAndDetail removes trailing arithmetic formulas', () {
      const rawDetail =
          '白米饭200g≈232，清炒西兰花48g≈26，26+33+55+31+59+70=506，合计 506 kcal';
      final reconciled = reconcileCalorieAndDetail(506, rawDetail);
      expect(reconciled.$1, 506);
      expect(reconciled.$2.contains('26+33+55'), isFalse);
      expect(reconciled.$2.contains('合计'), isTrue);
    });
  });
}
