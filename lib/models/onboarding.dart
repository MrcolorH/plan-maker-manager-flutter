/// 首次引导状态模型（存储键：onboardingState）
library;

/// 体重展示格式化：整数去掉小数（68.0 → '68'），小数保留两位内原样（68.5 → '68.5'，68.55 → '68.55'）
String fmtWeight(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('.00')
      ? s.substring(0, s.length - 3)
      : (s.endsWith('0') ? s.substring(0, s.length - 1) : s);
}

/// 体脂率展示格式化：整数去掉小数（20.0 → '20'），小数保留一位（20.5 → '20.5'）
String fmtBodyFat(double v) {
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// 引导收集的基础信息
class UserProfile {
  String gender; // '' | 'male' | 'female'
  int? age;
  int? height;
  double? weight; // kg（F10 起支持两位小数，与体重记录同口径，同步保持一致）
  double activity; // 活动系数
  double? bodyFat; // 体脂率 %（选填，结合减脂期计算宏量营养目标）

  UserProfile({
    this.gender = '',
    this.age,
    this.height,
    this.weight,
    this.activity = 1.2,
    this.bodyFat,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        gender: json['gender'] is String ? json['gender'] as String : '',
        age: json['age'] is num ? (json['age'] as num).round() : null,
        height: json['height'] is num ? (json['height'] as num).round() : null,
        weight: json['weight'] is num ? (json['weight'] as num).toDouble() : null,
        activity: json['activity'] is num ? (json['activity'] as num).toDouble() : 1.2,
        bodyFat: json['bodyFat'] is num ? (json['bodyFat'] as num).toDouble() : null,
      );

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'age': age,
        'height': height,
        'weight': weight,
        'activity': activity,
        'bodyFat': bodyFat,
      };

  /// 基础信息完整 = 性别/年龄/身高/体重齐
  bool get complete => gender.isNotEmpty && age != null && height != null && weight != null;
}

/// 引导状态
class OnboardingState {
  bool done;

  /// 「重新体验首次引导」置位：true 期间跳过老用户豁免检测，
  /// 直到完成/跳过引导才清除（保证重跑状态跨重启生效）
  bool rerun;
  UserProfile profile;

  OnboardingState({this.done = false, this.rerun = false, UserProfile? profile})
      : profile = profile ?? UserProfile();

  factory OnboardingState.defaults() => OnboardingState();

  factory OnboardingState.fromJson(Map<String, dynamic> json) => OnboardingState(
        done: json['done'] is bool ? json['done'] as bool : false,
        rerun: json['rerun'] is bool ? json['rerun'] as bool : false,
        profile: json['profile'] is Map
            ? UserProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map))
            : UserProfile(),
      );

  Map<String, dynamic> toJson() => {'done': done, 'rerun': rerun, 'profile': profile.toJson()};
}

/// API 用量统计模型（存储键：apiUsage）
class ApiUsage {
  int calls;
  int promptTokens;
  int cacheHitTokens;
  int completionTokens;

  ApiUsage({
    this.calls = 0,
    this.promptTokens = 0,
    this.cacheHitTokens = 0,
    this.completionTokens = 0,
  });

  factory ApiUsage.defaults() => ApiUsage();

  factory ApiUsage.fromJson(Map<String, dynamic> json) => ApiUsage(
        calls: _int(json['calls']),
        promptTokens: _int(json['promptTokens']),
        cacheHitTokens: _int(json['cacheHitTokens']),
        completionTokens: _int(json['completionTokens']),
      );

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'promptTokens': promptTokens,
        'cacheHitTokens': cacheHitTokens,
        'completionTokens': completionTokens,
      };

  static int _int(dynamic v) => v is num ? v.round() : 0;
}

/// DeepSeek V4-Flash 牌价（¥/百万 tokens，2026-09-01 汇率估算）
const Map<String, double> kPrices = {'inputMiss': 1.5, 'inputHit': 0.05, 'output': 4.5};

/// 估算费用（元）
double estimateCost(ApiUsage u) {
  final miss = (u.promptTokens - u.cacheHitTokens) < 0 ? 0 : (u.promptTokens - u.cacheHitTokens);
  return miss / 1e6 * kPrices['inputMiss']! +
      u.cacheHitTokens / 1e6 * kPrices['inputHit']! +
      u.completionTokens / 1e6 * kPrices['output']!;
}
