import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/services/ai_service.dart';
import 'package:jianfei_dazi/utils/calorie_utils.dart';

void main() {
  group('空气炸锅逼油与热量损耗扣减测试', () {
    test('parseBreakdownFromText 能够精确解析负数热量损耗项（空气炸锅逼油）', () {
      const text = '香辣鸡腿堡2个≈900，空气炸锅逼出油3g≈-27，合计873';
      final list = AiService.parseBreakdownFromText(text);

      expect(list.length, 2);
      expect(list[0].name.contains('香辣鸡腿堡'), isTrue);
      expect(list[0].calories, 900);

      expect(list[1].name.contains('空气炸锅逼出油'), isTrue);
      expect(list[1].portion, '3g');
      expect(list[1].calories, -27);
    });

    test('reconcileCalorieAndDetail 正确对齐包含损耗扣减的总热量', () {
      // 拆解包含负数扣减项，合计为 873
      final r1 = reconcileCalorieAndDetail(900, '汉堡2个≈900，空气炸锅沥出油3g≈-27，合计873');
      expect(r1.$1, 873);
      expect(r1.$2, contains('合计873'));

      // 单独录入负值损耗项
      final r2 = reconcileCalorieAndDetail(-27, '空气炸锅逼出油3g≈-27');
      expect(r2.$1, -27);
      expect(r2.$2, contains('合计约 -27 kcal'));
    });

    test('DailySummary 正确汇总并扣除热量损耗与宏量脂肪', () {
      final plan = PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-09-01'),
        meals: [
          MealItem(id: 'm1', type: 'lunch', time: '12:00', name: '计划午餐', calories: 500, days: [1, 2, 3, 4, 5, 6, 7]),
        ],
        exercises: [],
      );

      final settings = AppSettings(
        tdee: 2000,
        dailyCalorieTarget: 1800,
      );

      const dateStr = '2026-10-15';
      final store = RecordStore(
        checkRecords: {
          dateStr: {'meal:m1': CheckEntry(checkedAt: 123456)},
        },
        dayEntries: {
          dateStr: [
            // 正餐：吃2个汉堡，900 kcal，脂肪 40g
            DayEntry(
              id: 'e_lunch',
              kind: 'meal',
              slot: 'lunch',
              time: '12:00',
              content: '两个汉堡',
              calories: 900,
              protein: 30,
              carbs: 80,
              fat: 40,
              source: 'plan',
              planItemId: 'm1',
            ),
            // 加餐/损耗扣减：空气炸锅复热逼出3g油，-27 kcal，脂肪 -3g
            DayEntry(
              id: 'e_loss',
              kind: 'meal',
              slot: 'snack',
              time: '12:10',
              content: '空气炸锅逼出油3g',
              calories: -27,
              protein: 0,
              carbs: 0,
              fat: -3,
              source: 'ai',
            ),
          ],
        },
      );

      final summary = dailySummary(plan, settings, store, dateStr);

      // 验证实际摄入热量扣除了 27 kcal
      expect(summary.mealIntake, 900);
      expect(summary.tempIntake, -27);
      expect(summary.intake, 873); // 900 - 27

      // 验证宏量脂肪扣除了 3g
      expect(summary.intakeFat, 37); // 40 - 3

      // 验证热量缺口增加 27 kcal（2000 - 873 = 1127）
      expect(summary.deficit, 1127);

      // 验证 hasData 判定
      expect(summary.hasData, isTrue);
    });

    test('只有负数损耗记录时 hasData 依然判定为 true，且脂肪不低于 0', () {
      final plan = PlanData.empty();
      final settings = AppSettings(tdee: 2000);
      const dateStr = '2026-10-15';

      final store = RecordStore(
        dayEntries: {
          dateStr: [
            DayEntry(
              id: 'e_loss_only',
              kind: 'meal',
              slot: 'snack',
              time: '15:00',
              content: '逼出油5g',
              calories: -45,
              fat: -5,
              source: 'manual',
            ),
          ],
        },
      );

      final summary = dailySummary(plan, settings, store, dateStr);
      expect(summary.hasData, isTrue);
      expect(summary.intake, -45);
      expect(summary.intakeFat, 0); // 保底 clamp 到 0，不出现负数宏量
    });
  });

  group('AI 配置与测试连接协议健壮性测试', () {
    test('isGeminiProvider 区分 Google 官方协议与第三方 OpenAI 兼容反向代理', () {
      // 官方原生
      expect(
        isGeminiProvider(AiConfig(
          provider: 'gemini',
          endpoint: 'https://generativelanguage.googleapis.com/v1beta',
        )),
        isTrue,
      );

      // 第三方 OpenAI 反向代理
      expect(
        isGeminiProvider(AiConfig(
          provider: 'gemini',
          endpoint: 'https://api.thirdparty-proxy.com/v1',
        )),
        isFalse,
      );

      // DeepSeek
      expect(
        isGeminiProvider(AiConfig(
          provider: 'deepseek',
          endpoint: 'https://api.deepseek.com',
        )),
        isFalse,
      );
    });

    test('DeepSeek 官方预设默认模型为 deepseek-chat，且默认不强制重写', () {
      final deepseekPreset = kAiProviders.firstWhere((p) => p.value == 'deepseek');
      expect(deepseekPreset.model, 'deepseek-chat');
      expect(kRetiredModelMap.containsKey('deepseek-chat'), isFalse);
    });

    test('Gemini 官方预设默认模型为 gemini-2.5-flash', () {
      final geminiPreset = kAiProviders.firstWhere((p) => p.value == 'gemini');
      expect(geminiPreset.model, 'gemini-2.5-flash');
    });

    test('shouldPassThinkingDisabled 仅对 flash/v4 传递，deepseek-chat 绝不传递 thinking 参数', () {
      expect(shouldPassThinkingDisabled('deepseek-chat'), isFalse);
      expect(shouldPassThinkingDisabled('deepseek-reasoner'), isFalse);
      expect(shouldPassThinkingDisabled('deepseek-v4-flash'), isTrue);
      expect(shouldPassThinkingDisabled('kimi-k3'), isFalse);
    });
  });
}
