/// 首次引导状态模型（存储键：onboardingState）
library;

/// 引导收集的基础信息
class UserProfile {
  String gender; // '' | 'male' | 'female'
  int? age;
  int? height;
  int? weight;
  double activity; // 活动系数

  UserProfile({
    this.gender = '',
    this.age,
    this.height,
    this.weight,
    this.activity = 1.2,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        gender: json['gender'] is String ? json['gender'] as String : '',
        age: json['age'] is num ? (json['age'] as num).round() : null,
        height: json['height'] is num ? (json['height'] as num).round() : null,
        weight: json['weight'] is num ? (json['weight'] as num).round() : null,
        activity: json['activity'] is num ? (json['activity'] as num).toDouble() : 1.2,
      );

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'age': age,
        'height': height,
        'weight': weight,
        'activity': activity,
      };

  bool get complete => gender.isNotEmpty && age != null && height != null && weight != null;
}

/// 引导状态
class OnboardingState {
  bool done;
  UserProfile profile;

  OnboardingState({this.done = false, UserProfile? profile})
      : profile = profile ?? UserProfile();

  factory OnboardingState.defaults() => OnboardingState();

  factory OnboardingState.fromJson(Map<String, dynamic> json) => OnboardingState(
        done: json['done'] is bool ? json['done'] as bool : false,
        profile: json['profile'] is Map
            ? UserProfile.fromJson(Map<String, dynamic>.from(json['profile'] as Map))
            : UserProfile(),
      );

  Map<String, dynamic> toJson() => {'done': done, 'profile': profile.toJson()};
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
