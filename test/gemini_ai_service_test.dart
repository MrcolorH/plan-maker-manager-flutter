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

      final flashLite31 = kGeminiModels.firstWhere((m) => m.model == 'gemini-3.1-flash-lite');
      expect(flashLite31.rpm, 15);
      expect(flashLite31.rpd, 500);
      expect(flashLite31.recommended, isTrue);

      final flash38 = kGeminiModels.firstWhere((m) => m.model == 'gemini-3.8-flash');
      expect(flash38.rpm, 5);
      expect(flash38.rpd, 20);
    });

    test('kAiProviders 包含 Google Gemini 预设', () {
      final geminiPreset = kAiProviders.firstWhere((p) => p.value == 'gemini');
      expect(geminiPreset.label, 'Google Gemini');
      expect(geminiPreset.endpoint, 'https://generativelanguage.googleapis.com/v1beta');
      expect(geminiPreset.model, 'gemini-3.1-flash-lite');
    });
  });
}
