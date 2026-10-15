/// 设置模型：与旧版 settings 存储结构 1:1 兼容（存储键：settings）
library;

import 'dart:math';

/// AI 服务配置（单次调用的不可变视图；对应一条 AiProfile 的快照）
class AiConfig {
  String provider;
  String endpoint;
  String apiKey;
  String model;

  AiConfig({
    this.provider = 'deepseek',
    this.endpoint = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-flash',
  });

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        provider: _str(json['provider'], 'deepseek'),
        endpoint: _str(json['endpoint'], 'https://api.deepseek.com'),
        apiKey: _str(json['apiKey']),
        model: _str(json['model'], 'deepseek-flash'),
      );

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
      };

  bool get hasConfig => apiKey.isNotEmpty && endpoint.isNotEmpty;

  static String _str(dynamic v, [String def = '']) => v is String ? v : def;
}

/// AI 服务商配置档案：一次完整配置（provider+endpoint+apiKey+model+createdAt），创建后只读。
/// 见 spec/ai-profile-design.md（多配置管理 + 仅启用一个）。
class AiProfile {
  final String id; // 时间戳毫秒 + 随机后缀，如 '1756953600000-37f2'
  final String provider; // kAiProviders 的 value（deepseek/kimi/mimo/minimax/custom）
  final String endpoint;
  final String apiKey;
  final String model;
  final int createdAt; // 配置时间（毫秒），列表区分同服务商多条配置的唯一依据

  const AiProfile({
    required this.id,
    required this.provider,
    this.endpoint = '',
    this.apiKey = '',
    this.model = '',
    required this.createdAt,
  });

  /// 由编辑表单（AiConfig）新建一条档案：生成 id 与创建时间
  factory AiProfile.create(AiConfig cfg) => AiProfile(
        id: _genProfileId(),
        provider: cfg.provider.trim(),
        endpoint: cfg.endpoint.trim(),
        apiKey: cfg.apiKey.trim(),
        model: cfg.model.trim(),
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

  /// 替换 model 字段（kRetiredModelMap 迁移用，保持其它字段不可变）
  AiProfile copyWithModel(String model) => AiProfile(
        id: id,
        provider: provider,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        createdAt: createdAt,
      );

  factory AiProfile.fromJson(Map<String, dynamic> json) => AiProfile(
        id: _str(json['id']),
        provider: _str(json['provider'], 'deepseek'),
        endpoint: _str(json['endpoint']),
        apiKey: _str(json['apiKey']),
        model: _str(json['model']),
        createdAt: _int(json['createdAt'], 0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'model': model,
        'createdAt': createdAt,
      };

  /// 转为单次调用用的 AiConfig 快照
  AiConfig toAiConfig() => AiConfig(
        provider: provider,
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
      );

  static String _str(dynamic v, [String def = '']) => v is String ? v : def;
  static int _int(dynamic v, [int def = 0]) => v is num ? v.round() : def;
}

/// 生成档案 id：时间戳毫秒 + 随机后缀（同毫秒内可区分多条）
String _genProfileId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rnd = Random().nextInt(0xffff).toRadixString(16).padLeft(4, '0');
  return '$ts-$rnd';
}

/// AI 服务商预设
class AiProviderPreset {
  final String value;
  final String label;
  final String endpoint;
  final String model;
  const AiProviderPreset(this.value, this.label, this.endpoint, this.model);
}

const List<AiProviderPreset> kAiProviders = [
  AiProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-flash'),
  AiProviderPreset('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-flash'),
  AiProviderPreset('kimi', 'Kimi（月之暗面）', 'https://api.moonshot.cn/v1', 'kimi-k3'),
  AiProviderPreset('mimo', 'MiMo（小米）', 'https://api.xiaomimimo.com/v1', 'mimo-v2.5'),
  AiProviderPreset('minimax', 'MiniMax', 'https://api.minimaxi.com/v1', 'MiniMax-M3'),
  AiProviderPreset('custom', '自定义', '', ''),
];

/// Gemini 模型与速率限制选项
class GeminiModelOption {
  final String model;
  final String name;
  final int rpm;
  final String tpm;
  final int rpd;
  final bool recommended;

  const GeminiModelOption({
    required this.model,
    required this.name,
    required this.rpm,
    required this.tpm,
    required this.rpd,
    this.recommended = false,
  });

  String get rateLimitSummary => '$rpm RPM · $tpm TPM · $rpd 次/天${recommended ? '（推荐）' : ''}';
  String get dropdownLabel => '$name ($rpm RPM / $rpd RPD${recommended ? ' · 推荐' : ''})';
}

const List<GeminiModelOption> kGeminiModels = [
  GeminiModelOption(
    model: 'gemini-2.5-flash',
    name: 'Gemini 2.5 Flash',
    rpm: 15,
    tpm: '250K',
    rpd: 500,
    recommended: true,
  ),
  GeminiModelOption(
    model: 'gemini-2.0-flash',
    name: 'Gemini 2.0 Flash',
    rpm: 15,
    tpm: '250K',
    rpd: 500,
    recommended: true,
  ),
  GeminiModelOption(
    model: 'gemini-1.5-flash',
    name: 'Gemini 1.5 Flash',
    rpm: 15,
    tpm: '250K',
    rpd: 500,
  ),
  GeminiModelOption(
    model: 'gemini-2.5-pro',
    name: 'Gemini 2.5 Pro',
    rpm: 5,
    tpm: '250K',
    rpd: 50,
  ),
  GeminiModelOption(
    model: 'gemini-1.5-pro',
    name: 'Gemini 1.5 Pro',
    rpm: 5,
    tpm: '250K',
    rpd: 50,
  ),
  GeminiModelOption(
    model: 'gemini-2.5-flash-lite',
    name: 'Gemini 2.5 Flash Lite',
    rpm: 10,
    tpm: '250K',
    rpd: 20,
  ),
  GeminiModelOption(
    model: 'gemini-3.1-flash-lite',
    name: 'Gemini 3.1 Flash Lite (实验/预览)',
    rpm: 15,
    tpm: '250K',
    rpd: 500,
  ),
  GeminiModelOption(
    model: 'gemini-3.8-flash',
    name: 'Gemini 3.8 Flash (实验/预览)',
    rpm: 5,
    tpm: '250K',
    rpd: 20,
  ),
];

/// 已退役的旧模型名 → 当前可用模型名
const Map<String, String> kRetiredModelMap = {
  // DeepSeek 官方支持的标准 API 模型名为 deepseek-flash 与 deepseek-v4-pro；
  // 此处自动平滑迁移旧版或误传入的别名配置
  'deepseek-chat': 'deepseek-flash',
  'deepseek-reasoner': 'deepseek-flash',
  'deepseek-v4.1-flash': 'deepseek-flash',
  'deepseek-v4-flash': 'deepseek-flash',
  'deepseek-v4-flash-vision-exp': 'deepseek-flash',
};

/// 模型退役自动迁移辅助函数
String migrateRetiredModel(String model) => kRetiredModelMap[model.trim()] ?? model;

/// 全部设置
class AppSettings {
  int tdee; // 基础消耗（不含运动）
  int bmr; // 基础代谢（>0 时统计用 bmr×1.2 作基础消耗）
  int dailyCalorieTarget;
  bool reminderEnabled;
  int reminderAdvance; // 分钟
  bool autoBackupEnabled; // 本地自动备份开关（默认关；开启后持久化，除非手动关闭/清空数据否则保持，见 spec/backup-design.md §11）
  List<AiProfile> aiProfiles; // 服务商配置档案列表（≥0 条）
  String activeAiProfileId; // 当前启用的档案 id；空串 = 未启用任何配置

  AppSettings({
    this.tdee = 2000,
    this.bmr = 0,
    this.dailyCalorieTarget = 1400,
    this.reminderEnabled = true,
    this.reminderAdvance = 0,
    this.autoBackupEnabled = false,
    List<AiProfile>? aiProfiles,
    this.activeAiProfileId = '',
  }) : aiProfiles = aiProfiles ?? [];

  factory AppSettings.defaults() => AppSettings();

  /// 当前激活的档案（activeAiProfileId 指向的），不存在时 null
  AiProfile? get activeProfile {
    if (activeAiProfileId.isEmpty) return null;
    for (final p in aiProfiles) {
      if (p.id == activeAiProfileId) return p;
    }
    return null;
  }

  /// 生效的 AI 配置（供所有 AI 调用点使用）。
  /// endpoint/key/model 作为整体随激活档案切换，杜绝 "A 的 provider + B 的 endpoint" 脏配置。
  AiConfig get ai {
    final p = activeProfile;
    if (p == null) return AiConfig(); // 未配置：保持现有默认值行为
    return p.toAiConfig();
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // 1) 优先读新格式 aiProfiles
    final List<AiProfile> profiles = [
      for (final e in (json['aiProfiles'] is List ? json['aiProfiles'] as List : const []))
        if (e is Map) AiProfile.fromJson(Map<String, dynamic>.from(e)),
    ];

    // 2) 旧版本：只有单条 ai 字段 → 一次性迁移为一条档案（迁移时刻近似配置时间）
    if (profiles.isEmpty && json['ai'] is Map) {
      final old = AiConfig.fromJson(Map<String, dynamic>.from(json['ai'] as Map));
      if (old.apiKey.isNotEmpty) {
        profiles.add(AiProfile(
          id: _genProfileId(),
          provider: old.provider,
          endpoint: old.endpoint,
          apiKey: old.apiKey,
          model: old.model,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }

    // 3) 校验激活指针：不在列表中则回退到第一条 / 清空
    var activeId = json['activeAiProfileId'] is String ? json['activeAiProfileId'] as String : '';
    if (activeId.isNotEmpty && !profiles.any((p) => p.id == activeId)) activeId = '';
    if (activeId.isEmpty && profiles.isNotEmpty) activeId = profiles.first.id;

    return AppSettings(
      tdee: _int(json['tdee'], 2000),
      bmr: _int(json['bmr'], 0),
      dailyCalorieTarget: _int(json['dailyCalorieTarget'], 1400),
      reminderEnabled: json['reminderEnabled'] is bool ? json['reminderEnabled'] as bool : true,
      reminderAdvance: _int(json['reminderAdvance'], 0),
      autoBackupEnabled: json['autoBackupEnabled'] is bool
          ? json['autoBackupEnabled'] as bool
          : false, // 老版本存储无此字段 → 默认关，由用户在设置页主动开启
      aiProfiles: profiles,
      activeAiProfileId: activeId,
    );
  }

  Map<String, dynamic> toJson() {
    // 冗余写出激活档案为旧字段 ai：老版本 App 读新备份时字段不缺（降级兼容）；
    // 同时让各调用点（today/stats/food/import 直接引用 settings.ai）零改动。
    final p = activeProfile;
    final legacyAi = p == null
        ? AiConfig().toJson()
        : AiConfig(provider: p.provider, endpoint: p.endpoint, apiKey: p.apiKey, model: p.model).toJson();
    return {
      'tdee': tdee,
      'bmr': bmr,
      'dailyCalorieTarget': dailyCalorieTarget,
      'reminderEnabled': reminderEnabled,
      'reminderAdvance': reminderAdvance,
      'autoBackupEnabled': autoBackupEnabled,
      'ai': legacyAi,
      'aiProfiles': aiProfiles.map((x) => x.toJson()).toList(),
      'activeAiProfileId': activeAiProfileId,
    };
  }

  static int _int(dynamic v, int def) => v is num ? v.round() : def;
}

/// Mifflin-St Jeor 公式估算 BMR（基础代谢）；weight 支持两位小数（F10 体重记录）
int estimateBmr({required String gender, required int height, required num weight, required int age}) {
  return (10 * weight + 6.25 * height - 5 * age + (gender == 'male' ? 5 : -161)).round();
}

/// 按活动系数估算 TDEE（仅用于定每日目标摄入参考，不参与当日缺口统计）
int estimateTdee({required String gender, required int height, required num weight, required int age, required double activity}) {
  return (estimateBmr(gender: gender, height: height, weight: weight, age: age) * activity).round();
}

/// 推荐每日目标摄入 = 参考总消耗(BMR×活动系数) − 400，下限保护（女 1200 / 男 1500）
int recommendTarget(int bmr, double activity, String gender) {
  if (bmr <= 0) return 0;
  final floor = gender == 'male' ? 1500 : 1200;
  final v = (bmr * (activity <= 0 ? 1.2 : activity)).round() - 400;
  return v < floor ? floor : v;
}
