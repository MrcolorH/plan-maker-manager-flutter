/// AI 服务（OpenAI 兼容）：计划文档转 JSON / 食物热量查询 / 运动消耗估算 / 余额查询
/// 与旧版 ai.js 逻辑对齐，HTTP 层改用 dio
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data/templates.dart';
import '../models/onboarding.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../utils/date_utils.dart';

const String kCalorieSys = '''你是中国营养学会专业营养师。用户描述一份食物或饮品（可能是单品，也可能是多食物组合，或带家常烹饪/分食描述的一整段话），请科学精确估算总热量及三大营养素。

【核心估算规则】
1. 多食物完整合并：若输入包含多种食物（如「米饭+鸡蛋+鸡腿+炒茄子」或「一碗米饭，半盘炒菜」），必须全面识别所有食材并累加合并总热量与三大营养素，绝不能只计算某一项而遗漏其他！
2. 真实家常烹饪用油常识（严禁机械盲目加油）：
   - 普通家常炒菜（整盘生重约250-350g）：中国家庭常态整盘放油约8-12g（约一平汤匙；清淡小炒仅5-8g底油滑锅；吸油蔬菜如家常炒茄子、干煸豆角整盘放油约12-15g）。装盘出锅后，盘底与菜汤会残留20%-35%余油不被摄入；
   - 餐厅外卖/重油滑炒：整份油量约12-18g；只有明确油炸时才考虑18g以上；
   - 水煮/清蒸/凉拌/白灼：用油按0-3g计算。
3. 多人共食与分摊比例折算（关键铁律）：
   - 当用户描述与家人共吃、按比例食用（如「1/4盘炒菜」「半盘」「吃了几口」「尝了一点」）时，所有成分（主料、配料、实际摄入油量、总脂肪及各营养素）必须严格等比例折算！
   - 典型示例：整盘家常炒茄子整盘摄入油约10-12g，若用户吃 1/4 盘，则实际摄入油量仅约 2.5-3g（脂肪约2.5-3g，折合22-27kcal），茄子本身约15kcal，1/4盘总热量仅约40-45kcal！
   - 严禁违背常识：绝对不可直接给「1/4盘炒菜」算8-15g油（否则倒推整盘高达32-60g纯油，相当于油炸或浸油，严重脱离家常事实）！
4. 严格遵循能量守恒：总热量 ≈ 蛋白质*4 + 碳水*4 + 脂肪*9。肉类按熟重计算。
5. 【总计数值绝对一致（严禁前后矛盾）】：
   calories 字段数值必须与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！detail 内部各项数值相加之和也必须严格等于该合计，绝对不允许 detail 里的合计与 calories 字段出现任何偏差！

严格只返回一个 JSON 对象，不要输出任何其他文字或 markdown 代码块：
{"name":"规范食物名或多食物组合名","calories":总热量整数kcal,"protein":蛋白质克数整数g,"carbs":碳水克数整数g,"fat":脂肪克数整数g,"unit":"份量描述（如：1/4盘、1碗+1个等）","detail":"过程详解与分项拆解，如：米饭100g≈116，炒茄子1/4盘(含油约2.5g)≈45，合计161","confidence":0到1}
描述模糊时 confidence 给低值。''';

const String kMealEstSys = '''你是减脂临床营养与食物成分分析专家。用户会描述这一餐实际吃了什么（可能是完整菜名、食材用量，或是"原计划+今天少了/多了什么"的大白话描述，带备注）。
请按中国常见食物热量与烹饪常识精确估算。
规则：
1. 真实烹饪用油与分食折算：
   - 普通家常炒菜一整盘（250-350g）整盘用油约8-12g（清淡小炒5-8g，吸油菜如炒茄子整盘约12-15g），盘底残留余油不吃；外卖重油菜整份约12-18g；凉拌水煮清蒸少油或无油（0-3g）；
   - 若多人共食或按比例分吃（如吃 1/4 盘、半盘、吃了几口），食材用量与摄入油量必须严格等比例缩减！例如 1/4 盘家常炒茄子摄入油量仅约 2.5-3g，严禁将单人整份底油直接套给 1/4 盘（否则倒推整盘高达32g油，脱离常识）；
2. 多食物与复合描述必须全面合并计算，不漏掉任何一项食材；
3. 严格核验能量守恒：总热量必须约等于 (蛋白质*4 + 碳水*4 + 脂肪*9)；
4. 【总计数值绝对一致（严禁前后矛盾）】：
   calories 字段数值必须与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！detail 内部各项数值相加之和也必须严格等于该合计，绝对不允许 detail 里的合计与 calories 字段出现任何偏差！
5. 【拆分成分明细列表】：
   识别出该餐实际包含的所有主要食物/食材（如米饭、去皮鸡肉、青椒、烹调用油等），输出在 items 数组中，每项包含：
   - name: 食物/食材名称（如"米饭"、"鸡胸肉"）
   - portion: 估算重量或份量描述（如"150g"、"半盘"、"1个"）
   - calories: 该项预估热量整数（kcal）
6. 严格只返回一个 JSON 对象，不要输出任何其他文字或代码块：
{"calories":实际总热量整数kcal,"protein":蛋白质整数g,"carbs":碳水整数g,"fat":脂肪整数g,"items":[{"name":"食物名","portion":"估算重量或份量","calories":该项热量整数}],"detail":"一句话分项拆解，如：米饭100g≈116，炒茄子1/4盘(含油约2.5g)≈45，合计161"}
描述模糊时按常规份量估算。''';

/// FR6.9：计划条目编辑器专用——输入是结构化食材清单（含用量）+ 做法步骤，非口语描述
const String kItemCalSys = '''你是减脂计划餐食的热量与宏量营养素估算助手。用户给出一份计划餐食的结构化描述：餐名、食材清单（含用量）、做法步骤、备注。
请按中国常见食物热量成分，对食材清单逐项按给出的用量估算；做法步骤中提到的烹饪用油/糖/酱料等隐藏热量必须计入；未标注用量的食材按常见份量估算。
【烹饪用油常识】普通家常炒菜整盘用油约8-12g（清淡小炒5-8g，吸油菜12-15g）；若为分食（如吃几分之几盘）油量必须按比例等比缩减。
严格遵循营养守恒：总热量 ≈ 蛋白质*4 + 碳水*4 + 脂肪*9。
【总计数值绝对一致】：calories 字段数值必须与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"calories":整餐总热量整数kcal,"protein":蛋白质整数g,"carbs":碳水整数g,"fat":脂肪整数g,"detail":"一句话拆解，如：鸡胸肉150g≈200(P45g)，橄榄油5g≈45，米饭150g≈175，合计420"}
备注中提到的替代/增减（如"不放糖"）以备注为准。''';

const String kBurnEstSys = '''你是运动消耗估算助手。用户会描述一次实际做的运动（项目 + 时长/距离/强度，可能带备注）。
请结合用户的基础资料（性别/年龄/身高/体重，若提供）按运动强度（MET 参照）估算总消耗；未提供体重时按 65kg 成人估算。
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"name":"运动名（10字内）","calories":消耗整数kcal,"detail":"一句话拆解，如：慢跑40分钟≈300 kcal"}
描述模糊时按常见强度估。''';

const String kGuidePlanSys = '''你是减脂计划生成助手。用户会描述想吃的餐食和想做的运动（可能是一整段大白话，也可能是逐条列表），请把它生成为结构化计划 JSON。

只输出一个 JSON 对象，不要输出任何解释文字，不要 markdown 代码块围栏。

JSON 结构：
{
  "version": "1.0",
  "meta": { "planName": "我的减脂计划", "dailyCalorieTarget": 每日目标摄入kcal数字 },
  "meals": [
    { "type": "breakfast/lunch/dinner/snack四选一", "name": "餐名", "time": "HH:mm", "calories": 热量kcal数字或null, "days": [1,2,3], "note": "" }
  ],
  "exercises": [
    { "name": "训练名", "time": "HH:mm", "duration": 总分钟数字, "caloriesBurned": 消耗kcal数字, "days": [1,3,5], "note": "" }
  ]
}

生成规则：
1. 按用户描述拆分条目：早/午/晚/加餐分别一条；计划外运动放 exercises。不遗漏用户提到的任何内容，也不要凭空添加用户没提的条目
2. days 用数字表示星期几：1=周一 … 7=周日；「每天」或未提及 = [1,2,3,4,5,6,7]；「周一到周五」= [1,2,3,4,5]
3. 用户已给出的时间/热量/星期等信息必须原样保留；未给出的按常识补全：早餐07:30、午餐12:00、加餐16:00、晚餐18:00、运动18:30
4. 热量/消耗按中国常见食物与运动强度估算，给合理整数；用户明确说热量不固定（如自由餐/作弊餐）calories 填 null
5. 用户提供了体重时，运动消耗按该体重估算
6. name 用简洁中文（20字内）；meta.dailyCalorieTarget 填用户给定的目标摄入，未给定则省略''';

/// HTTP 状态码 → 中文提示
String httpErrorMsg(int code) {
  const map = {
    400: '请求被拒绝（400）：请检查模型名是否正确',
    401: 'API Key 无效或已过期（401）：请检查 Key 是否复制完整',
    402: '账户余额不足（402）：请到服务商官网充值',
    403: '无访问权限（403）：请检查 Key 的权限',
    404: '接口地址或模型名不存在（404）：请检查接口地址与模型名',
    429: '请求过于频繁（429）：请稍后再试',
    500: 'AI 服务内部错误（500）：请稍后再试',
    503: 'AI 服务繁忙（503）：请稍后再试',
  };
  return map[code] ?? 'AI 服务返回异常状态码 $code';
}

String netErrorMsg(Object? err) {
  final m = err?.toString() ?? '';
  if (m.contains('timeout') || m.contains('TimedOut')) return 'AI 请求超时：服务端生成较慢或网络波动，请稍后重试';
  if (m.contains('cancel')) return '请求已取消，请重试';
  // 域名解析失败：设备断网 / 无网络权限（旧安装包缺 INTERNET 权限时也会这样）
  if (m.contains('Failed host lookup') ||
      m.contains('Connection failed') ||
      m.contains('errno = 13')) {
    return '无法连接 AI 服务：请检查网络是否可用，若网络正常仍报此错，请重新安装最新打包';
  }
  return '网络异常：请检查网络后重试';
}

/// 规范化接口地址：去首尾空白与斜杠，剥离误粘贴的 /chat/completions 后缀
String normalizeEndpoint(String raw) {
  var e = raw.trim();
  e = e.replaceAll(RegExp(r'/chat/completions/?$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r'/+$'), '');
  return e;
}

/// 从 AI 回复文本中容错提取 JSON 对象（剥离围栏/杂文字）
Map<String, dynamic>? extractJsonObj(String? text) {
  if (text is! String) return null;
  var t = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false).firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  final s = t.indexOf('{');
  final e = t.lastIndexOf('}');
  if (s < 0 || e <= s) return null;
  try {
    final v = jsonDecode(t.substring(s, e + 1));
    return (v is Map) ? Map<String, dynamic>.from(v) : null;
  } catch (_) {
    return null;
  }
}

/// 判断是否为 Google Gemini 协议
bool isGeminiProvider(AiConfig config) {
  final p = config.provider.trim().toLowerCase();
  if (p == 'gemini' || p == 'google') return true;
  final ep = config.endpoint.toLowerCase();
  return ep.contains('generativelanguage.googleapis.com') || ep.contains(':generatecontent');
}

/// 规范化 Gemini 端点并组装 generateContent 完整 URL
String buildGeminiUrl(String rawEndpoint, String model) {
  var e = rawEndpoint.trim();
  e = e.replaceAll(RegExp(r'/models/[^/:]+:generateContent.*$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r':generateContent.*$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r'/chat/completions/?$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r'/+$'), '');
  if (e.isEmpty) {
    e = 'https://generativelanguage.googleapis.com/v1beta';
  } else if (!e.contains('/v1') && !e.contains('/v1beta')) {
    e = '$e/v1beta';
  }
  final m = model.trim().isEmpty ? 'gemini-3.1-flash-lite' : model.trim();
  return '$e/models/$m:generateContent';
}

/// 提取 Gemini 请求体（适配 systemInstruction 与 contents）
Map<String, dynamic> buildGeminiRequestBody(List<Map<String, String>> messages) {
  final systemParts = <Map<String, String>>[];
  final contents = <Map<String, dynamic>>[];

  for (final m in messages) {
    final role = m['role'] ?? 'user';
    final text = m['content'] ?? '';
    if (text.isEmpty) continue;

    if (role == 'system') {
      systemParts.add({'text': text});
    } else {
      final gRole = (role == 'assistant' || role == 'model') ? 'model' : 'user';
      contents.add({
        'role': gRole,
        'parts': [{'text': text}],
      });
    }
  }

  if (contents.isEmpty && systemParts.isNotEmpty) {
    contents.add({
      'role': 'user',
      'parts': [{'text': systemParts.map((p) => p['text']).join('\n\n')}],
    });
    systemParts.clear();
  }

  final body = <String, dynamic>{
    'contents': contents,
    'generationConfig': {
      'temperature': 0.2,
    },
  };

  if (systemParts.isNotEmpty) {
    body['systemInstruction'] = {
      'parts': systemParts,
    };
  }

  return body;
}

/// 解析 Gemini 响应并累计 usage
String parseGeminiResponse(
  Map<String, dynamic> data, {
  void Function(Map<String, dynamic> usage)? onUsage,
}) {
  if (data['usageMetadata'] is Map) {
    final u = data['usageMetadata'] as Map;
    onUsage?.call({
      'prompt_tokens': u['promptTokenCount'] ?? 0,
      'completion_tokens': u['candidatesTokenCount'] ?? 0,
      'total_tokens': u['totalTokenCount'] ?? 0,
    });
  }

  final candidates = data['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    final feedback = data['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw Exception('Gemini 拒绝响应：${feedback['blockReason']}');
    }
    throw Exception('AI 未返回内容，请重试');
  }

  final cand = candidates[0];
  if (cand is Map) {
    final contentMap = cand['content'];
    if (contentMap is Map && contentMap['parts'] is List) {
      final parts = contentMap['parts'] as List;
      final text = parts
          .whereType<Map>()
          .map((p) => p['text'])
          .whereType<String>()
          .join('');
      if (text.isNotEmpty) return text;
    }
    final finishReason = cand['finishReason'];
    if (finishReason != null && finishReason != 'STOP') {
      throw Exception('Gemini 响应未完成：$finishReason');
    }
  }
  throw Exception('AI 未返回内容，请重试');
}

String _extractGeminiError(dynamic data, int? statusCode) {
  if (data is Map && data['error'] is Map) {
    final err = data['error'] as Map;
    final msg = err['message']?.toString() ?? '';
    final status = err['status']?.toString() ?? '';
    if (msg.contains('API key not valid')) {
      return 'Google API Key 无效或格式不正确，请核对后再试';
    }
    if (msg.contains('location') || msg.contains('not supported')) {
      return '当前网络地区暂不支持 Google API，请切换网络环境';
    }
    if (status == 'RESOURCE_EXHAUSTED' || statusCode == 429) {
      return '已超出 Gemini 速率限制（429）：请稍后再试或在设置中换用额度更高的模型（如 Gemini 3.1 Flash Lite）';
    }
    if (msg.isNotEmpty) return 'Gemini 错误（$status）：$msg';
  }
  return httpErrorMsg(statusCode ?? 0);
}

/// 校准与对齐 AI 返回的总热量与拆解详情，确保 100% 绝对一致，消除前后打架
(int, String) reconcileCalorieAndDetail(int rawCal, String? rawDetail) {
  var detail = (rawDetail ?? '').trim();
  if (detail.isEmpty) {
    return (rawCal, '总热量约 $rawCal kcal');
  }

  // 匹配 detail 末尾或其中的合计表达，如：
  // "合计161", "合计 161", "合计约161", "合计：161", "总计 161", "共计161", "共约 161", "＝161", "= 161"
  final sumRegex = RegExp(
    r'(?:合计|总计|共计|共约|合计约|总计约|小计|＝|=)\s*[:：]?\s*≈?\s*(\d+)\s*(?:kcal|大卡)?',
    caseSensitive: false,
  );

  final matches = sumRegex.allMatches(detail).toList();
  if (matches.isNotEmpty) {
    final lastMatch = matches.last;
    final parsedCal = int.tryParse(lastMatch.group(1) ?? '');
    if (parsedCal != null && parsedCal > 0) {
      if (parsedCal != rawCal) {
        // 当 detail 的合计值与顶层 calories 字段不一致时：
        // 若差异在合理范围（<=150 kcal 或 25% 比例内），说明 detail 的分项累加推导更细致，以 detail 的加总值为准
        final diff = (parsedCal - rawCal).abs();
        if (diff <= 150 || (rawCal > 0 && diff / rawCal <= 0.25)) {
          rawCal = parsedCal;
        } else {
          // 若差异过大，强制将 detail 末尾的合计修正为 rawCal，确保两者绝对一致
          detail = '${detail.substring(0, lastMatch.start)}合计 $rawCal kcal${detail.substring(lastMatch.end)}';
        }
      }
    }
  } else {
    // 若 detail 没写合计后缀，且含有多项拆解，自动在末尾追加规范合计
    if (detail.contains('+') || detail.contains('，') || detail.contains(',') || detail.contains('≈')) {
      detail = '$detail，合计约 $rawCal kcal';
    }
  }

  return (rawCal, detail);
}

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  /// 全局单例 Dio：底层 HttpClient 复用连接池（keep-alive），
  /// 避免每次调用重新 DNS + TCP + TLS 握手（移动网络下可省几百毫秒）
  Dio? _dio;
  Dio _client() {
    if (_dio != null) return _dio!;
    _dio = Dio(BaseOptions(
      contentType: 'application/json',
      // 连接建立上限：与接收超时分离，避免黑洞连接（如 IPv6 不通）长时间挂住
      connectTimeout: const Duration(seconds: 15),
    ));
    return _dio!;
  }

  /// 通用 chat 调用：根据 provider 自动分流 OpenAI 兼容 或 Google Gemini 原生 REST
  Future<String> chat(AiConfig config, List<Map<String, String>> messages,
      {int timeoutMs = 60000, bool enableThinking = false, void Function(Map<String, dynamic> usage)? onUsage}) async {
    if (config.apiKey.isEmpty || config.endpoint.isEmpty) {
      throw Exception('未配置 AI：请到「设置 → AI 服务」填写 API Key');
    }

    if (isGeminiProvider(config)) {
      return _chatGemini(
        config,
        messages,
        timeoutMs: timeoutMs,
        onUsage: onUsage,
      );
    }

    final base = normalizeEndpoint(config.endpoint);
    final model = config.model.isEmpty ? 'deepseek-v4-flash' : config.model;
    final sw = Stopwatch()..start();
    debugPrint('[AiService] >>> $base/chat/completions model=$model thinking=$enableThinking '
        'msg=${messages.map((m) => '${m['role']}:${(m['content'] ?? '').length}字').join(' | ')}');
    try {
      final isDeepSeek = config.provider == 'deepseek' ||
          RegExp(r'deepseek', caseSensitive: false).hasMatch(base);
      final res = await _client().post(
        '$base/chat/completions',
        data: {
          'model': model,
          'temperature': 0.2,
          'messages': messages,
          // 仅在显式不开启思考模式时给 DeepSeek 传 disabled；开启思考模式时不传 disabled（让模型进入 chain-of-thought 推理）
          if (isDeepSeek && !enableThinking) 'thinking': {'type': 'disabled'},
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey}'},
          // 深度思考模式放宽到 90s 超时，普通模式 60s
          receiveTimeout: Duration(milliseconds: enableThinking ? 90000 : timeoutMs),
        ),
      );
      debugPrint('[AiService] <<< HTTP ${res.statusCode} 耗时 ${sw.elapsedMilliseconds}ms');
      if (res.statusCode != 200) throw Exception(httpErrorMsg(res.statusCode ?? 0));
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
      // 累计本 App 的 API 用量（tokens/次数）
      final usage = data['usage'];
      if (usage is Map) {
        onUsage?.call(Map<String, dynamic>.from(usage));
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) throw Exception('AI 未返回内容，请重试');
      final ch = choices[0];
      final content = (ch is Map) ? (ch['message'] is Map ? (ch['message'] as Map)['content'] : null) : null;
      if (content is! String || content.isEmpty) throw Exception('AI 未返回内容，请重试');
      return content;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      debugPrint('[AiService] !!! DioException type=${e.type} '
          'status=$code 耗时 ${sw.elapsedMilliseconds}ms err=${e.error} msg=${e.message}');
      if (e.response?.data != null) debugPrint('[AiService] !!! body=${e.response?.data}');
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('连接 AI 服务超时：请检查网络后重试');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('AI 响应超时：服务端生成较慢，请稍后重试或手动填写');
      }
      if (e.type == DioExceptionType.cancel) throw Exception('请求已取消，请重试');
      throw Exception(netErrorMsg(e.error ?? e.message));
    } catch (e) {
      debugPrint('[AiService] ??? 未知异常 耗时 ${sw.elapsedMilliseconds}ms: $e');
      if (e is Exception && e.toString().contains('网络超时')) rethrow;
      if (e is Exception && e.toString().contains('请求已取消')) rethrow;
      rethrow;
    }
  }

  /// Google Gemini 原生 REST 协议调用（generateContent）
  Future<String> _chatGemini(
    AiConfig config,
    List<Map<String, String>> messages, {
    int timeoutMs = 60000,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    final model = config.model.trim().isEmpty ? 'gemini-3.1-flash-lite' : config.model.trim();
    final url = buildGeminiUrl(config.endpoint, model);
    final reqBody = buildGeminiRequestBody(messages);
    final sw = Stopwatch()..start();
    debugPrint('[AiService:Gemini] >>> POST $url model=$model '
        'msg=${messages.map((m) => '${m['role']}:${(m['content'] ?? '').length}字').join(' | ')}');

    try {
      final res = await _client().post(
        url,
        data: reqBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': config.apiKey.trim(),
          },
          receiveTimeout: Duration(milliseconds: timeoutMs),
        ),
      );
      debugPrint('[AiService:Gemini] <<< HTTP ${res.statusCode} 耗时 ${sw.elapsedMilliseconds}ms');
      if (res.statusCode != 200) {
        throw Exception(_extractGeminiError(res.data, res.statusCode));
      }
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      return parseGeminiResponse(data, onUsage: onUsage);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      debugPrint('[AiService:Gemini] !!! DioException type=${e.type} '
          'status=$code 耗时 ${sw.elapsedMilliseconds}ms err=${e.error} msg=${e.message}');
      if (e.response?.data != null) {
        debugPrint('[AiService:Gemini] !!! body=${e.response?.data}');
        throw Exception(_extractGeminiError(e.response?.data, code));
      }
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('连接 Google AI 服务超时：请检查网络后重试');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Gemini 响应超时：服务端生成较慢，请稍后重试或手动填写');
      }
      if (e.type == DioExceptionType.cancel) throw Exception('请求已取消，请重试');
      throw Exception(netErrorMsg(e.error ?? e.message));
    } catch (e) {
      debugPrint('[AiService:Gemini] ??? 未知异常 耗时 ${sw.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  bool hasConfig(AiConfig config) => config.hasConfig;

  /// 食物热量及营养素查询（支持本地缓存）
  Future<Map<String, dynamic>> queryCalorie(AiConfig config, String foodDesc,
      {bool enableThinking = false, void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kCalorieSys},
        {'role': 'user', 'content': '食物描述：$foodDesc'},
      ],
      enableThinking: enableThinking,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动录入热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 20000) throw Exception('AI 返回的热量数值异常，请手动录入');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    return {
      'name': (obj['name'] is String && (obj['name'] as String).isNotEmpty) ? obj['name'] : '食物',
      'calories': reconciled.$1,
      'protein': num.tryParse('${obj['protein']}')?.round(),
      'carbs': num.tryParse('${obj['carbs']}')?.round(),
      'fat': num.tryParse('${obj['fat']}')?.round(),
      'unit': obj['unit'] is String ? obj['unit'] : '',
      'detail': reconciled.$2,
      'confidence': obj['confidence'] is num ? obj['confidence'] : 0.5,
    };
  }

  /// 计划文档 → 计划 JSON（AI 导入）
  Future<Map<String, dynamic>> generatePlan(AiConfig config, String docText,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kPlanConvertPrompt},
        {'role': 'user', 'content': '今天是 ${dateCn(todayStr())}（${todayStr()}）。计划文档：\n$docText'},
      ],
      timeoutMs: 90000,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 未返回有效的 JSON，请重试；多次失败可换更完整的计划文档');
    // AI 偶尔漏写或写错 version，直接修正
    obj['version'] = '1.0';
    return obj;
  }

  /// 测试连接
  Future<void> testAI(AiConfig config, {void Function(Map<String, dynamic>)? onUsage}) async {
    await queryCalorie(config, '一个水煮蛋', onUsage: onUsage);
  }

  /// 从文本描述中容错解析食物拆解明细表格（兜底与历史兼容）
  static List<FoodBreakdownItem> parseBreakdownFromText(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final clean = text.trim();
    final content = clean.replaceAll(RegExp(r'^(?:AI\s*拆解|食物库(?:组合|命中)?|分项拆解)[：:]\s*'), '');

    // 括号感知的顶层切分（避免切碎括号内的逗号，如 "牛肉面(1碗, 550kcal)"）
    final segments = <String>[];
    var depth = 0;
    var current = StringBuffer();
    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '(' || char == '（') {
        depth++;
        current.write(char);
      } else if (char == ')' || char == '）') {
        if (depth > 0) depth--;
        current.write(char);
      } else if (depth == 0 && (char == '，' || char == ',' || char == ';' || char == '；' || char == '+' || char == '\n' || char == '\r')) {
        final s = current.toString().trim();
        if (s.isNotEmpty) segments.add(s);
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    final rem = current.toString().trim();
    if (rem.isNotEmpty) segments.add(rem);

    final results = <FoodBreakdownItem>[];

    for (final rawSeg in segments) {
      final seg = rawSeg.trim();
      if (seg.isEmpty) continue;
      if (RegExp(r'^(?:合计|总计|共计)\s*(?:约|≈)?\s*\d+').hasMatch(seg)) continue;

      // 1. 本地食物库格式：如 "牛肉面(1碗, 550kcal)" 或 "葡式蛋挞(1个, 290kcal)"
      final mDb = RegExp(r'^([^\(（]+)[\(（]([^\,，]+)[\,，]\s*(\d+)\s*(?:kcal)?[\)）]?$', caseSensitive: false).firstMatch(seg);
      if (mDb != null) {
        final name = mDb.group(1)?.trim() ?? '';
        final portion = mDb.group(2)?.trim() ?? '';
        final cal = int.tryParse(mDb.group(3) ?? '') ?? 0;
        if (name.isNotEmpty) {
          results.add(FoodBreakdownItem(name: name, portion: portion, calories: cal));
          continue;
        }
      }

      // 2. 带 ≈、=、: 的拆解格式，如 "米饭100g≈116" 或 "炒茄子1/4盘(含油约2.5g)≈45" 或 "鸡胸肉150g≈200(P45g)"
      // 从后往前找最后一个分隔符（避免食物括号内备注中的冒号等干扰）
      final allSeps = RegExp(r'[≈=：:]').allMatches(seg).toList();
      if (allSeps.isNotEmpty) {
        final lastSep = allSeps.last;
        final left = seg.substring(0, lastSep.start).trim();
        final right = seg.substring(lastSep.end).trim();
        final calMatch = RegExp(r'^\s*(\d+)').firstMatch(right);
        if (calMatch != null) {
          final cal = int.tryParse(calMatch.group(1) ?? '') ?? 0;
          final pMatch = RegExp(r'([\d\.\/]+[^\d\s\(\)（）]+(?:\([^\)]+\)|（[^）]+）)?)\s*$').firstMatch(left);
          if (pMatch != null) {
            final portion = pMatch.group(1)?.trim() ?? '';
            final name = left.substring(0, pMatch.start).trim();
            results.add(FoodBreakdownItem(
              name: name.isNotEmpty ? name : left,
              portion: portion,
              calories: cal,
            ));
            continue;
          } else {
            results.add(FoodBreakdownItem(name: left, portion: '', calories: cal));
            continue;
          }
        }
      }

      // 3. 通用兜底：提取末尾数字为热量
      final endCal = RegExp(r'(\d+)\s*(?:kcal)?\s*$', caseSensitive: false).firstMatch(seg);
      if (endCal != null) {
        final cal = int.tryParse(endCal.group(1) ?? '') ?? 0;
        final left = seg.substring(0, endCal.start).trim();
        results.add(FoodBreakdownItem(name: left, portion: '', calories: cal));
      }
    }
    return results;
  }

  /// 提取/转换 AI 返回的 items 结构，若缺失则降级从 detail 文本解析
  static List<FoodBreakdownItem> parseBreakdownItems(dynamic rawItems, String? fallbackDetail) {
    if (rawItems is List && rawItems.isNotEmpty) {
      final list = <FoodBreakdownItem>[];
      for (final it in rawItems) {
        if (it is Map) {
          final name = '${it['name'] ?? ''}'.trim();
          final portion = '${it['portion'] ?? it['weight'] ?? ''}'.trim();
          final cal = num.tryParse('${it['calories']}')?.round() ?? 0;
          if (name.isNotEmpty) {
            list.add(FoodBreakdownItem(name: name, portion: portion, calories: cal));
          }
        }
      }
      if (list.isNotEmpty) return list;
    }
    return parseBreakdownFromText(fallbackDetail);
  }

  /// 一餐实际热量与三大营养素估算（支持"计划+少了什么"的口语描述及深度思考），resolve { calories, protein, carbs, fat, detail, items }
  Future<Map<String, dynamic>> estimateMeal(AiConfig config, String desc,
      {bool enableThinking = false, void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kMealEstSys},
        {'role': 'user', 'content': '这一餐的描述：$desc'},
      ],
      enableThinking: enableThinking,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 5000) throw Exception('AI 估算的热量超出合理范围，请手动填写');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    final items = parseBreakdownItems(obj['items'], reconciled.$2);
    return {
      'calories': reconciled.$1,
      'protein': num.tryParse('${obj['protein']}')?.round(),
      'carbs': num.tryParse('${obj['carbs']}')?.round(),
      'fat': num.tryParse('${obj['fat']}')?.round(),
      'detail': reconciled.$2,
      'items': items,
    };
  }

  /// FR6.9：计划条目编辑器整餐热量估算——输入为结构化食材清单（含用量）+ 做法步骤 + 备注，
  /// 专用提示词强调按用量逐项估算并计入烹饪隐藏热量与三大营养素；resolve { calories, protein, carbs, fat, detail }
  Future<Map<String, dynamic>> estimateItemMeal(AiConfig config, String desc,
      {bool enableThinking = false, void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kItemCalSys},
        {'role': 'user', 'content': '计划餐食的描述：\n$desc'},
      ],
      enableThinking: enableThinking,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 5000) throw Exception('AI 估算的热量超出合理范围，请手动填写');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    return {
      'calories': reconciled.$1,
      'protein': num.tryParse('${obj['protein']}')?.round(),
      'carbs': num.tryParse('${obj['carbs']}')?.round(),
      'fat': num.tryParse('${obj['fat']}')?.round(),
      'detail': reconciled.$2,
    };
  }

  /// 一次运动的消耗估算（支持"项目+时长"的口语描述），resolve { name, calories, detail }
  /// F10：携带个人基础资料（性别/年龄/身高/体重）按强度（MET 参照）估算
  Future<Map<String, dynamic>> estimateBurn(
    AiConfig config,
    String desc, {
    num? weight,
    String? gender, // 'male' | 'female'
    int? age,
    int? height,
    void Function(Map<String, dynamic>)? onUsage,
  }) async {
    final parts = <String>[];
    final g = gender == 'male' ? '男性' : (gender == 'female' ? '女性' : '');
    if (g.isNotEmpty) parts.add(g);
    if (age != null && age > 0) parts.add('$age岁');
    if (height != null && height > 0) parts.add('身高${height}cm');
    if (weight != null && weight > 0 && weight < 300) parts.add('体重约${fmtWeight(weight.toDouble())}kg');
    final user = parts.isEmpty
        ? '运动的描述：$desc'
        : '运动的描述：$desc；用户资料：${parts.join('，')}';
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kBurnEstSys},
        {'role': 'user', 'content': user},
      ],
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写消耗');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 5000) throw Exception('AI 估算的消耗超出合理范围，请手动填写');
    return {
      'name': (obj['name'] is String && (obj['name'] as String).isNotEmpty) ? obj['name'] : '运动',
      'calories': cal.round(),
      'detail': obj['detail'] is String ? obj['detail'] : '',
    };
  }

  /// 余额查询（DeepSeek /user/balance 接口）
  Future<Map<String, dynamic>> queryBalance(AiConfig config) async {
    if (config.apiKey.isEmpty) throw Exception('未配置 API Key，请先到「设置 → AI 服务」填写');
    final isDeepSeek = config.provider == 'deepseek' || RegExp(r'deepseek', caseSensitive: false).hasMatch(config.endpoint);
    if (!isDeepSeek) throw Exception('当前服务商暂不支持余额查询（仅 DeepSeek 支持）');
    final base = normalizeEndpoint(config.endpoint);
    try {
      final res = await _client().get(
        '$base/user/balance',
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey}'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (res.statusCode != 200) throw Exception(httpErrorMsg(res.statusCode ?? 0));
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      final infos = data['balance_infos'];
      if (infos is! List || infos.isEmpty) throw Exception('服务未返回余额信息');
      return data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      throw Exception(netErrorMsg(e.error ?? e.message));
    }
  }

  /// 引导页「AI 创造计划」：把用户的描述/条目列表生成为计划 JSON
  Future<Map<String, dynamic>> generatePlanFromInput(AiConfig config, String inputText, UserProfile profile,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final p = profile;
    final meta = <String>[];
    if (p.gender.isNotEmpty) meta.add(p.gender == 'male' ? '男性' : '女性');
    if (p.age != null) meta.add('${p.age}岁');
    if (p.height != null) meta.add('身高${p.height}cm');
    if (p.weight != null) meta.add('体重约${fmtWeight(p.weight!)}kg');
    final user = '今天是 ${dateCn(todayStr())}（${todayStr()}）。'
        '${meta.isNotEmpty ? '用户资料：${meta.join('，')}。' : ''}'
        '用户的需求描述：\n$inputText';
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kGuidePlanSys},
        {'role': 'user', 'content': user},
      ],
      timeoutMs: 90000,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 未返回有效的 JSON，请重试或改用手动模式');
    obj['version'] = '1.0';
    return obj;
  }
}
