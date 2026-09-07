/// AI 服务（OpenAI 兼容）：计划文档转 JSON / 食物热量查询 / 运动消耗估算 / 余额查询
/// 与旧版 ai.js 逻辑对齐，HTTP 层改用 dio
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data/templates.dart';
import '../models/onboarding.dart';
import '../models/settings.dart';
import '../utils/date_utils.dart';

const String kCalorieSys = '''你是食物热量估算助手。用户描述一份食物或套餐，请估算总热量。
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"name":"食物名","calories":总热量整数kcal,"unit":"份量描述","confidence":0到1}
描述含多种食物时合并估算总值。无法判断时 confidence 给低值。''';

const String kMealEstSys = '''你是营养估算助手。用户会描述这一餐实际吃了什么——可能是完整菜名或食物清单，也可能是"计划的餐食 + 今天少了/换了/多了什么"的口语描述，还可能带份量备注。
请根据中国常见食物热量常识，估算这一餐的实际总热量。
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"calories":实际总热量整数kcal,"detail":"一句话拆解，如：黄焖鸡米饭1份≈640，可乐没喝0，合计640"}
描述模糊时按常见份量估。''';

/// FR6.9：计划条目编辑器专用——输入是结构化食材清单（含用量）+ 做法步骤，非口语描述
const String kItemCalSys = '''你是减脂计划餐食的热量估算助手。用户给出一份计划餐食的结构化描述：餐名、食材清单（含用量）、做法步骤、备注。
请按中国常见食物热量，对食材清单逐项按给出的用量估算；做法步骤中提到的烹饪用油/糖/酱料/勾芡等隐藏热量必须计入；未标注用量的食材按常见份量估算。
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"calories":整餐总热量整数kcal,"detail":"一句话拆解，如：鸡胸肉150g≈250，橄榄油10g≈90，合计340"}
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

  /// 通用 chat/completions 调用 → 返回助手回复文本
  /// 默认接收超时 60s：DeepSeek 高峰期非流式生成经常 >20s，20s 过紧会误报「网络超时」
  Future<String> chat(AiConfig config, List<Map<String, String>> messages,
      {int timeoutMs = 60000, void Function(Map<String, dynamic> usage)? onUsage}) async {
    if (config.apiKey.isEmpty || config.endpoint.isEmpty) {
      throw Exception('未配置 AI：请到「设置 → AI 服务」填写 API Key');
    }
    final base = normalizeEndpoint(config.endpoint);
    final model = config.model.isEmpty ? 'deepseek-v4-flash' : config.model;
    final sw = Stopwatch()..start();
    debugPrint('[AiService] >>> $base/chat/completions model=$model '
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
          // deepseek-v4-flash / v4-pro 默认开启思考模式（effort=high）：
          // 估算热量/消耗这类结构化小任务会被内部链式推理拖慢到数十秒，
          // 显式禁用思考模式换取秒级响应（非 DeepSeek 服务商不传此字段）
          if (isDeepSeek) 'thinking': {'type': 'disabled'},
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey}'},
          // 接收超时按调用场景定（如生成计划 90s），连接超时全局固定 15s
          receiveTimeout: Duration(milliseconds: timeoutMs),
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

  bool hasConfig(AiConfig config) => config.hasConfig;

  /// 食物热量查询
  Future<Map<String, dynamic>> queryCalorie(AiConfig config, String foodDesc,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kCalorieSys},
        {'role': 'user', 'content': '食物描述：$foodDesc'},
      ],
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动录入热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 20000) throw Exception('AI 返回的热量数值异常，请手动录入');
    return {
      'name': (obj['name'] is String && (obj['name'] as String).isNotEmpty) ? obj['name'] : '食物',
      'calories': cal.round(),
      'unit': obj['unit'] is String ? obj['unit'] : '',
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

  /// 一餐实际热量估算（支持"计划+少了什么"的口语描述），resolve { calories, detail }
  Future<Map<String, dynamic>> estimateMeal(AiConfig config, String desc,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kMealEstSys},
        {'role': 'user', 'content': '这一餐的描述：$desc'},
      ],
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 5000) throw Exception('AI 估算的热量超出合理范围，请手动填写');
    return {
      'calories': cal.round(),
      'detail': obj['detail'] is String ? obj['detail'] : '',
    };
  }

  /// FR6.9：计划条目编辑器整餐热量估算——输入为结构化食材清单（含用量）+ 做法步骤 + 备注，
  /// 专用提示词强调按用量逐项估算并计入烹饪隐藏热量；resolve { calories, detail }
  Future<Map<String, dynamic>> estimateItemMeal(AiConfig config, String desc,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kItemCalSys},
        {'role': 'user', 'content': '计划餐食的描述：\n$desc'},
      ],
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 5000) throw Exception('AI 估算的热量超出合理范围，请手动填写');
    return {
      'calories': cal.round(),
      'detail': obj['detail'] is String ? obj['detail'] : '',
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
