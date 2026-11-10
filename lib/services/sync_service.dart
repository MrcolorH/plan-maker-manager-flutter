import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../providers/record_provider.dart';
import 'ai_service.dart';


/// 云端账号与收件箱同步服务 (单例)
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  static const String _keyServerUrl = 'cloud_sync_server_url';
  static const String _keyToken = 'cloud_sync_token';
  static const String _keyUsername = 'cloud_sync_username';
  static const String _keyLastSyncAt = 'cloud_sync_last_at';

  // 默认指向正式域名 (待解析生效后即连)，开发期可切换为本地 http://10.0.2.2:3000 或内网IP
  static const String defaultServerUrl = 'https://api.zhiqing.fun';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  String? _token;
  String? _username;
  String _serverUrl = defaultServerUrl;
  int _lastSyncAt = 0;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;
  String? get currentUsername => _username;
  String get serverUrl => _serverUrl;
  int get lastSyncAt => _lastSyncAt;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_keyServerUrl) ?? defaultServerUrl;
    _token = prefs.getString(_keyToken);
    _username = prefs.getString(_keyUsername);
    _lastSyncAt = prefs.getInt(_keyLastSyncAt) ?? 0;
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, _serverUrl);
  }

  /// 账号注册 (需有效邀请码)
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String inviteCode,
  }) async {
    try {
      final res = await _dio.post(
        '$_serverUrl/api/v1/auth/register',
        data: {
          'username': username,
          'password': password,
          'inviteCode': inviteCode,
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        await _saveAuth(data['token'] as String, username);
        return {'success': true};
      }
      return {'success': false, 'message': '注册失败'};
    } on DioException catch (e) {
      return _handleDioError(e);
    }
  }

  /// 账号登录
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '$_serverUrl/api/v1/auth/login',
        data: {
          'username': username,
          'password': password,
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        await _saveAuth(data['token'] as String, username);
        return {'success': true};
      }
      return {'success': false, 'message': '登录失败'};
    } on DioException catch (e) {
      return _handleDioError(e);
    }
  }

  /// 退出登录
  Future<void> logout() async {
    _token = null;
    _username = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUsername);
  }

  /// 获取 6 位 QQ 绑定配对码 (5分钟有效)
  Future<Map<String, dynamic>> getQqBindCode() async {
    if (!isLoggedIn) return {'success': false, 'message': '请先登录知轻云端账号'};
    try {
      final res = await _dio.post(
        '$_serverUrl/api/v1/account/qq-bind-code',
        options: _authOptions(),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        return {
          'success': true,
          'code': data['code'],
          'expiresIn': data['expiresIn'],
          'tip': data['tip']
        };
      }
      return {'success': false, 'message': '生成绑定码失败'};
    } on DioException catch (e) {
      return _handleDioError(e);
    }
  }

  /// 拉取收件箱并自动注入本地打卡事实源 (核心无感同步方法)
  /// 支持可选传入知轻 [aiConfig]，套用知轻原汁原味的中国营养学会专业提示词 (kCalorieSys) 请 AI 进行结构化语义转换录入
  Future<int> syncInboxToLocal(
    RecordProvider recordProvider, {
    AiConfig? aiConfig,
    void Function(Map<String, dynamic>)? onUsage,
  }) async {
    if (!isLoggedIn) return 0;
    try {
      final res = await _dio.get(
        '$_serverUrl/api/v1/inbox/pending',
        options: _authOptions(),
      );

      if (res.statusCode != 200 || res.data is! Map) return 0;
      final entriesData = (res.data as Map)['entries'] as List?;
      if (entriesData == null || entriesData.isEmpty) return 0;

      final ackIds = <String>[];

      for (final raw in entriesData) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = item['id'] as String;
        final date = item['date'] as String;
        String content = item['content'] as String? ?? '餐品打卡';
        int calories = item['calories'] as int? ?? 0;
        int? protein = item['protein'] as int?;
        int? carbs = item['carbs'] as int?;
        int? fat = item['fat'] as int?;
        final slot = item['slot'] as String? ?? 'lunch';
        final detail = item['detail'] as String?;

        List<FoodBreakdownItem>? breakdownItems;
        if (item['items'] is List) {
          breakdownItems = (item['items'] as List)
              .map((e) => e is Map ? FoodBreakdownItem.fromJson(Map<String, dynamic>.from(e)) : null)
              .whereType<FoodBreakdownItem>()
              .toList();
        }

        // 若云端信箱尚未解析出明细食材 (breakdownItems 为空) 且手机端配置了 AI 服务，在客户端套用提示词进行容灾转换
        final bool needClientAiParse = (breakdownItems == null || breakdownItems.isEmpty || calories <= 0) &&
            aiConfig != null &&
            AiService.instance.hasConfig(aiConfig) &&
            detail != null &&
            detail.trim().length > 15;

        if (needClientAiParse) {
          try {
            final aiRes = await AiService.instance.queryCalorie(
              aiConfig,
              detail,
              onUsage: onUsage,
            );
            final aiCal = aiRes['calories'] as int? ?? 0;
            if (aiCal != 0) {
              calories = aiCal;
              protein = aiRes['protein'] as int? ?? protein;
              carbs = aiRes['carbs'] as int? ?? carbs;
              fat = aiRes['fat'] as int? ?? fat;
              final aiName = aiRes['name'] as String?;
              if (aiName != null && aiName.isNotEmpty && aiName != '食物') {
                content = aiName;
              }
              final aiItems = aiRes['items'] as List<FoodBreakdownItem>?;
              if (aiItems != null && aiItems.isNotEmpty) {
                breakdownItems = aiItems;
              }
            }
          } catch (e) {
            debugPrint('[SyncService] 客户端 AI 转换兜底异常: $e');
          }
        }

        // 统一双重兜底：若未能解出 items 但有 detail 文本，在客户端使用知轻一致的 AiService 规则进行整段文案解析
        if ((breakdownItems == null || breakdownItems.isEmpty) && detail != null && detail.isNotEmpty) {
          final parsed = AiService.parseBreakdownFromText(detail);
          if (parsed.isNotEmpty) {
            breakdownItems = parsed;
          }
        }

        // 统一宏量营养素双重兜底：若服务端返回宏量为 0 但 detail 文本中有总结数据，在客户端进行正则提取
        if ((protein == null || protein == 0) &&
            (carbs == null || carbs == 0) &&
            (fat == null || fat == 0) &&
            detail != null &&
            detail.isNotEmpty) {
          final pMatch = RegExp(r'(?:蛋白质|蛋白|P)\s*[:：约约为\s]*(\d+(?:\.\d+)?)\s*g?', caseSensitive: false).firstMatch(detail);
          if (pMatch != null) protein = double.tryParse(pMatch.group(1) ?? '')?.round();
          final cMatch = RegExp(r'(?:碳水化合物|碳水|C)\s*[:：约约为\s]*(\d+(?:\.\d+)?)\s*g?', caseSensitive: false).firstMatch(detail);
          if (cMatch != null) carbs = double.tryParse(cMatch.group(1) ?? '')?.round();
          final fMatch = RegExp(r'(?:脂肪|油脂|F)\s*[:：约约为\s]*(\d+(?:\.\d+)?)\s*g?', caseSensitive: false).firstMatch(detail);
          if (fMatch != null) fat = double.tryParse(fMatch.group(1) ?? '')?.round();
        }

        // 若总热量为 0 或未解析，而 breakdownItems 存在，自动计算合计
        if (calories <= 0 && breakdownItems != null && breakdownItems.isNotEmpty) {
          calories = breakdownItems.fold<int>(0, (sum, it) => sum + it.calories);
        }

        // 若标题依然是通用打卡且有具体菜品项，自动提炼具体餐品名（如：米饭、煎鸡胸肉、炒绿豆芽）
        if ((content == '餐品打卡' || content.endsWith('打卡')) &&
            breakdownItems != null &&
            breakdownItems.isNotEmpty) {
          final names = breakdownItems.map((e) => e.name).where((n) => n.isNotEmpty).take(3).join('、');
          if (names.isNotEmpty) {
            content = breakdownItems.length > 3 ? '$names等' : names;
          }
        }

        // 调用本地 RecordProvider 原生录入为事实源并自动打卡
        await recordProvider.addDayEntry(
          date,
          kind: 'meal',
          slot: slot,
          content: content,
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
          detail: detail,
          items: breakdownItems,
          source: 'qq_bot',
          autoCheck: true,
        );


        ackIds.add(id);
      }

      // 批量向服务端确认已消费
      if (ackIds.isNotEmpty) {
        await _dio.post(
          '$_serverUrl/api/v1/inbox/ack',
          data: {'ids': ackIds},
          options: _authOptions(),
        );
      }

      _lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyLastSyncAt, _lastSyncAt);

      return ackIds.length;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await logout();
      }
      return 0;
    } catch (_) {
      // 网络或服务器异常静默跳过，绝不阻断 App 运行
      return 0;
    }
  }

  /// 上传全量快照备份至云端 (服务端会自动归档历史版本)
  Future<Map<String, dynamic>> uploadSnapshot({
    required Map<String, dynamic> payload,
    String? deviceName,
    String? reason,
  }) async {
    if (!isLoggedIn) return {'success': false, 'message': '请先登录云端账号'};
    try {
      final res = await _dio.put(
        '$_serverUrl/api/v1/sync/snapshot',
        data: {
          'payload': payload,
          'deviceName': deviceName ?? '知轻手机客户端',
          'clientUpdatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'reason': reason ?? 'manual_backup',
        },
        options: _authOptions(),
      );
      if (res.statusCode == 200) {
        return {'success': true, 'message': (res.data as Map)['message'] ?? '云端备份成功'};
      }
      return {'success': false, 'message': '备份失败'};
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await logout();
      return _handleDioError(e);
    } catch (e) {
      return {'success': false, 'message': '备份异常: $e'};
    }
  }

  /// 从云端拉取全量快照数据
  Future<Map<String, dynamic>> fetchSnapshot() async {
    if (!isLoggedIn) return {'success': false, 'message': '请先登录云端账号'};
    try {
      final res = await _dio.get(
        '$_serverUrl/api/v1/sync/snapshot',
        options: _authOptions(),
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        return {
          'success': true,
          'payload': data['payload'],
          'serverUpdatedAt': data['serverUpdatedAt'],
          'deviceName': data['deviceName'],
        };
      }
      return {'success': false, 'message': '未获取到云端快照'};
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await logout();
      return _handleDioError(e);
    } catch (e) {
      return {'success': false, 'message': '获取快照异常: $e'};
    }
  }

  Options _authOptions() {
    return Options(
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
  }

  Future<void> _saveAuth(String token, String username) async {
    _token = token;
    _username = username;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsername, username);
  }

  Map<String, dynamic> _handleDioError(DioException e) {
    if (e.response?.data is Map) {
      final errObj = (e.response!.data as Map)['error'];
      if (errObj is Map && errObj['message'] != null) {
        return {'success': false, 'message': errObj['message'].toString()};
      }
    }
    return {'success': false, 'message': '网络连接失败，请检查服务地址或网络状态'};
  }
}
