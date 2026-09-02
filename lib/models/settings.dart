/// 设置模型：与旧版 settings 存储结构 1:1 兼容（存储键：settings）
library;

/// AI 服务配置
class AiConfig {
  String provider;
  String endpoint;
  String apiKey;
  String model;

  AiConfig({
    this.provider = 'deepseek',
    this.endpoint = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-v4-flash',
  });

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        provider: _str(json['provider'], 'deepseek'),
        endpoint: _str(json['endpoint'], 'https://api.deepseek.com'),
        apiKey: _str(json['apiKey']),
        model: _str(json['model'], 'deepseek-v4-flash'),
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

/// AI 服务商预设
class AiProviderPreset {
  final String value;
  final String label;
  final String endpoint;
  final String model;
  const AiProviderPreset(this.value, this.label, this.endpoint, this.model);
}

const List<AiProviderPreset> kAiProviders = [
  AiProviderPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-v4-flash'),
  AiProviderPreset('kimi', 'Kimi（月之暗面）', 'https://api.moonshot.cn/v1', 'kimi-k3'),
  AiProviderPreset('mimo', 'MiMo（小米）', 'https://api.xiaomimimo.com/v1', 'mimo-v2.5'),
  AiProviderPreset('minimax', 'MiniMax', 'https://api.minimaxi.com/v1', 'MiniMax-M3'),
  AiProviderPreset('custom', '自定义', '', ''),
];

/// 已退役的 DeepSeek 旧模型名 → 当前可用模型名
const Map<String, String> kRetiredModelMap = {
  'deepseek-chat': 'deepseek-v4-flash',
  'deepseek-reasoner': 'deepseek-v4-pro',
};

/// 全部设置
class AppSettings {
  int tdee; // 基础消耗（不含运动）
  int bmr; // 基础代谢（>0 时统计用 bmr×1.2 作基础消耗）
  int dailyCalorieTarget;
  bool reminderEnabled;
  int reminderAdvance; // 分钟
  AiConfig ai;

  AppSettings({
    this.tdee = 2000,
    this.bmr = 0,
    this.dailyCalorieTarget = 1400,
    this.reminderEnabled = true,
    this.reminderAdvance = 0,
    AiConfig? ai,
  }) : ai = ai ?? AiConfig();

  factory AppSettings.defaults() => AppSettings();

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        tdee: _int(json['tdee'], 2000),
        bmr: _int(json['bmr'], 0),
        dailyCalorieTarget: _int(json['dailyCalorieTarget'], 1400),
        reminderEnabled: json['reminderEnabled'] is bool
            ? json['reminderEnabled'] as bool
            : true,
        reminderAdvance: _int(json['reminderAdvance'], 0),
        ai: json['ai'] is Map
            ? AiConfig.fromJson(Map<String, dynamic>.from(json['ai'] as Map))
            : AiConfig(),
      );

  Map<String, dynamic> toJson() => {
        'tdee': tdee,
        'bmr': bmr,
        'dailyCalorieTarget': dailyCalorieTarget,
        'reminderEnabled': reminderEnabled,
        'reminderAdvance': reminderAdvance,
        'ai': ai.toJson(),
      };

  static int _int(dynamic v, int def) => v is num ? v.round() : def;
}

/// Mifflin-St Jeor 公式估算 BMR（基础代谢）
int estimateBmr({required String gender, required int height, required int weight, required int age}) {
  return (10 * weight + 6.25 * height - 5 * age + (gender == 'male' ? 5 : -161)).round();
}

/// 按活动系数估算 TDEE（仅用于定每日目标摄入参考，不参与当日缺口统计）
int estimateTdee({required String gender, required int height, required int weight, required int age, required double activity}) {
  return (estimateBmr(gender: gender, height: height, weight: weight, age: age) * activity).round();
}

/// 推荐每日目标摄入 = 参考总消耗(BMR×活动系数) − 400，下限保护（女 1200 / 男 1500）
int recommendTarget(int bmr, double activity, String gender) {
  if (bmr <= 0) return 0;
  final floor = gender == 'male' ? 1500 : 1200;
  final v = (bmr * (activity <= 0 ? 1.2 : activity)).round() - 400;
  return v < floor ? floor : v;
}
