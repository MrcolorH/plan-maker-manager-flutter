import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/services/ai_service.dart';

void main() {
  group('Google Gemini 协议与配置判定', () {
    test('isGeminiProvider 正确识别 provider 与 endpoint', () {
      expect(isGeminiProvider(AiConfig(provider: 'gemini')), isTrue);
      expect(isGeminiProvider(AiConfig(provider: 'Google')), isTrue);
      expect(
        isGeminiProvider(AiConfig(
          provider: 'custom',
          endpoint: 'https://generativelanguage.googleapis.com/v1beta',
        )),
        isTrue,
      );
      expect(
        isGeminiProvider(AiConfig(
          provider: 'custom',
          endpoint: 'https://myproxy.com/v1beta/models/gemini-2.5-flash:generateContent',
        )),
        isTrue,
      );
      expect(isGeminiProvider(AiConfig(provider: 'deepseek')), isFalse);
      expect(isGeminiProvider(AiConfig(provider: 'kimi')), isFalse);
    });

    test('buildGeminiUrl 规范化与模型 URL 组装', () {
      // 标准 v1beta 端点
      expect(
        buildGeminiUrl('https://generativelanguage.googleapis.com/v1beta', 'gemini-3.1-flash-lite'),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent',
      );
      // 根域名自动追加 v1beta
      expect(
        buildGeminiUrl('https://generativelanguage.googleapis.com', 'gemini-3.8-flash'),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent',
      );
      // 误粘贴完整带有 :generateContent 的地址
      expect(
        buildGeminiUrl(
          'https://generativelanguage.googleapis.com/v1beta/models/old-model:generateContent',
          'gemini-3.5-flash-lite',
        ),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent',
      );
      // 误粘贴带有 /chat/completions 后缀
      expect(
        buildGeminiUrl(
          'https://myproxy.com/v1beta/chat/completions',
          'gemini-2.5-flash',
        ),
        'https://myproxy.com/v1beta/models/gemini-2.5-flash:generateContent',
      );
    });

    test('buildGeminiRequestBody 转换 systemInstruction 与 contents', () {
      final messages = [
        {'role': 'system', 'content': '你是一个营养师助手'},
        {'role': 'user', 'content': '一个苹果多少热量？'},
        {'role': 'assistant', 'content': '大约 52 kcal'},
        {'role': 'user', 'content': '那两个呢？'},
      ];

      final body = buildGeminiRequestBody(messages);

      // 验证 systemInstruction
      expect(body.containsKey('systemInstruction'), isTrue);
      final sysParts = body['systemInstruction']['parts'] as List;
      expect(sysParts.first['text'], '你是一个营养师助手');

      // 验证 contents 映射
      final contents = body['contents'] as List;
      expect(contents.length, 3);
      expect(contents[0]['role'], 'user');
      expect((contents[0]['parts'] as List).first['text'], '一个苹果多少热量？');
      expect(contents[1]['role'], 'model');
      expect((contents[1]['parts'] as List).first['text'], '大约 52 kcal');
      expect(contents[2]['role'], 'user');
      expect((contents[2]['parts'] as List).first['text'], '那两个呢？');

      // 验证 generationConfig
      expect(body['generationConfig']['temperature'], 0.2);
    });

    test('parseGeminiResponse 正常解析与 usage 回调', () {
      final fakeResponse = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '{"name":"苹果","calories":52}'}
              ],
              'role': 'model'
            },
            'finishReason': 'STOP'
          }
        ],
        'usageMetadata': {
          'promptTokenCount': 15,
          'candidatesTokenCount': 25,
          'totalTokenCount': 40
        }
      };

      Map<String, dynamic>? capturedUsage;
      final text = parseGeminiResponse(fakeResponse, onUsage: (u) => capturedUsage = u);

      expect(text, '{"name":"苹果","calories":52}');
      expect(capturedUsage, isNotNull);
      expect(capturedUsage!['prompt_tokens'], 15);
      expect(capturedUsage!['completion_tokens'], 25);
      expect(capturedUsage!['total_tokens'], 40);
    });
  });

  group('Gemini 模型列表与速率限制定义', () {
    test('kGeminiModels 包含主要模型与推荐配置', () {
      expect(kGeminiModels.isNotEmpty, isTrue);

      final flash25 = kGeminiModels.firstWhere((m) => m.model == 'gemini-2.5-flash');
      expect(flash25.rpm, 15);
      expect(flash25.rpd, 500);
      expect(flash25.recommended, isTrue);

      final flash38 = kGeminiModels.firstWhere((m) => m.model == 'gemini-3.8-flash');
      expect(flash38.rpm, 5);
      expect(flash38.rpd, 20);
    });

    test('kAiProviders 包含 Google Gemini 预设', () {
      final geminiPreset = kAiProviders.firstWhere((p) => p.value == 'gemini');
      expect(geminiPreset.label, 'Google Gemini');
      expect(geminiPreset.endpoint, 'https://generativelanguage.googleapis.com/v1beta');
      expect(geminiPreset.model, 'gemini-2.5-flash');
    });

    test('AI 估算 Prompt 明确区分家常菜用油常识、分食比例与总计绝对一致性要求', () {
      // 检查加餐估算 Prompt
      expect(kCalorieSys, contains('多食物完整合并'));
      expect(kCalorieSys, contains('8-12g'));
      expect(kCalorieSys, contains('1/4盘'));
      expect(kCalorieSys, contains('等比例折算'));
      expect(kCalorieSys, contains('detail'));
      expect(kCalorieSys, contains('总计数值绝对一致'));

      // 检查餐食估算 Prompt
      expect(kMealEstSys, contains('8-12g'));
      expect(kMealEstSys, contains('1/4 盘'));
      expect(kMealEstSys, contains('等比例缩减'));
      expect(kMealEstSys, contains('总计数值绝对一致'));
    });

    test('reconcileCalorieAndDetail 校准与对齐 AI 热量数值与拆解文本', () {
      // 1. 完全一致时原样返回
      final r1 = reconcileCalorieAndDetail(161, '米饭100g≈116，炒茄子1/4盘≈45，合计161');
      expect(r1.$1, 161);
      expect(r1.$2, '米饭100g≈116，炒茄子1/4盘≈45，合计161');

      // 2. detail 末尾合计与顶层 calories 存在细化差异时，自动对齐（以拆解细化的 515 为准，校准顶层 calories）
      final r2 = reconcileCalorieAndDetail(480, '黄焖鸡熟鸡肉120g≈190，米饭150g≈175，烹饪油酱汁≈150，合计515');
      expect(r2.$1, 515);
      expect(r2.$2, contains('合计515'));

      // 3. detail 带有带单位的合计，如 "合计 515 kcal"
      final r3 = reconcileCalorieAndDetail(500, '鸡肉≈200，米饭≈175，油≈140，合计 515 kcal');
      expect(r3.$1, 515);

      // 4. detail 没有结尾合计词，但包含分项，自动补齐规范合计
      final r4 = reconcileCalorieAndDetail(230, '米饭150g≈175，青菜100g≈55');
      expect(r4.$1, 230);
      expect(r4.$2, '米饭150g≈175，青菜100g≈55，合计约 230 kcal');

      // 5. detail 为空，给出规范兜底
      final r5 = reconcileCalorieAndDetail(300, '');
      expect(r5.$1, 300);
      expect(r5.$2, '总热量约 300 kcal');

      // 6. 极端悬殊差异时，将 detail 结尾修正为输入框采纳的数值，确保前后绝对一致
      final r6 = reconcileCalorieAndDetail(300, '整只烤鸡大餐，合计 1500 kcal');
      expect(r6.$1, 300);
      expect(r6.$2, contains('合计 300 kcal'));
    });
  });
}
