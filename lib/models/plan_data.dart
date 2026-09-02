/// 计划数据模型：与旧版 uni-app 的 planData 存储结构 1:1 兼容
/// 存储键：planData
library;

/// 食材清单项
class DetailItem {
  String item;
  String amount;

  DetailItem({this.item = '', this.amount = ''});

  factory DetailItem.fromJson(Map<String, dynamic> json) => DetailItem(
        item: _str(json['item']),
        amount: _str(json['amount']),
      );

  Map<String, dynamic> toJson() => {'item': item, 'amount': amount};

  static String _str(dynamic v) => v is String ? v : '';
}

/// 餐食做法步骤（字符串数组，直接用 `List<String>` 表达）
/// 训练内容项
class ContentItem {
  String item;
  String detail;
  int minutes;

  ContentItem({this.item = '', this.detail = '', this.minutes = 0});

  factory ContentItem.fromJson(Map<String, dynamic> json) => ContentItem(
        item: _str(json['item']),
        detail: _str(json['detail']),
        minutes: _num(json['minutes']).round(),
      );

  Map<String, dynamic> toJson() => {'item': item, 'detail': detail, 'minutes': minutes};

  static String _str(dynamic v) => v is String ? v : '';
  static num _num(dynamic v) => v is num ? v : 0;
}

/// 餐食计划项
class MealItem {
  String id;
  String type; // breakfast | lunch | dinner | snack
  String name;
  String time; // HH:mm
  int? calories; // null = 自由餐
  List<int> days;
  bool reminder;
  String note;
  List<DetailItem> details;
  List<String> steps;
  List<String> dates;
  String startDate;
  String endDate;

  MealItem({
    required this.id,
    this.type = 'lunch',
    this.name = '',
    this.time = '12:00',
    this.calories,
    List<int>? days,
    this.reminder = true,
    this.note = '',
    List<DetailItem>? details,
    List<String>? steps,
    List<String>? dates,
    this.startDate = '',
    this.endDate = '',
  })  : days = days ?? [],
        details = details ?? [],
        steps = steps ?? [],
        dates = dates ?? [];

  factory MealItem.fromJson(Map<String, dynamic> json) {
    return MealItem(
      id: _str(json['id']),
      type: _str(json['type']),
      name: _str(json['name']),
      time: _str(json['time']),
      calories: json['calories'] is num ? (json['calories'] as num).round() : null,
      days: _intList(json['days']),
      reminder: json['reminder'] is bool ? json['reminder'] as bool : true,
      note: _str(json['note']),
      details: (json['details'] is List)
          ? (json['details'] as List)
              .whereType<Map>()
              .map((e) => DetailItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
      steps: (json['steps'] is List) ? (json['steps'] as List).map((e) => e.toString()).toList() : [],
      dates: _strList(json['dates']),
      startDate: _str(json['startDate']),
      endDate: _str(json['endDate']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'time': time,
        'calories': calories,
        'days': days,
        'reminder': reminder,
        'note': note,
        'details': details.map((e) => e.toJson()).toList(),
        'steps': steps,
        'dates': dates,
        'startDate': startDate,
        'endDate': endDate,
      };

  static String _str(dynamic v) => v is String ? v : '';
  static List<String> _strList(dynamic v) => v is List ? v.whereType<String>().toList() : [];
  static List<int> _intList(dynamic v) =>
      v is List ? v.whereType<num>().map((e) => e.round()).toList() : [];
}

/// 运动计划项
class ExerciseItem {
  String id;
  String name;
  String time;
  int duration;
  int caloriesBurned;
  List<int> days;
  List<String> dates;
  String startDate;
  String endDate;
  bool reminder;
  String note;
  List<ContentItem> content;

  ExerciseItem({
    required this.id,
    this.name = '',
    this.time = '18:00',
    this.duration = 30,
    this.caloriesBurned = 0,
    List<int>? days,
    List<String>? dates,
    this.startDate = '',
    this.endDate = '',
    this.reminder = true,
    this.note = '',
    List<ContentItem>? content,
  })  : days = days ?? [],
        dates = dates ?? [],
        content = content ?? [];

  factory ExerciseItem.fromJson(Map<String, dynamic> json) {
    return ExerciseItem(
      id: _str(json['id']),
      name: _str(json['name']),
      time: _str(json['time']),
      duration: json['duration'] is num ? (json['duration'] as num).round() : 30,
      caloriesBurned: json['caloriesBurned'] is num ? (json['caloriesBurned'] as num).round() : 0,
      days: _intList(json['days']),
      dates: _strList(json['dates']),
      startDate: _str(json['startDate']),
      endDate: _str(json['endDate']),
      reminder: json['reminder'] is bool ? json['reminder'] as bool : true,
      note: _str(json['note']),
      content: (json['content'] is List)
          ? (json['content'] as List)
              .whereType<Map>()
              .map((e) => ContentItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'time': time,
        'duration': duration,
        'caloriesBurned': caloriesBurned,
        'days': days,
        'dates': dates,
        'startDate': startDate,
        'endDate': endDate,
        'reminder': reminder,
        'note': note,
        'content': content.map((e) => e.toJson()).toList(),
      };

  static String _str(dynamic v) => v is String ? v : '';
  static List<String> _strList(dynamic v) => v is List ? v.whereType<String>().toList() : [];
  static List<int> _intList(dynamic v) =>
      v is List ? v.whereType<num>().map((e) => e.round()).toList() : [];
}

/// 计划 meta 元信息
class PlanMeta {
  String planName;
  String startDate;
  String endDate;
  String startedAt; // 计划开始日（首次导入当天 / 迁移回填）
  double? baseWeight;
  double? targetWeight;
  double? dailyCalorieTarget;
  double? tdee;

  PlanMeta({
    this.planName = '',
    this.startDate = '',
    this.endDate = '',
    this.startedAt = '',
    this.baseWeight,
    this.targetWeight,
    this.dailyCalorieTarget,
    this.tdee,
  });

  factory PlanMeta.fromJson(Map<String, dynamic> json) => PlanMeta(
        planName: _str(json['planName']),
        startDate: _str(json['startDate']),
        endDate: _str(json['endDate']),
        startedAt: _str(json['startedAt']),
        baseWeight: _num(json['baseWeight']),
        targetWeight: _num(json['targetWeight']),
        dailyCalorieTarget: _num(json['dailyCalorieTarget']),
        tdee: _num(json['tdee']),
      );

  Map<String, dynamic> toJson() => {
        'planName': planName,
        'startDate': startDate,
        'endDate': endDate,
        'startedAt': startedAt,
        'baseWeight': baseWeight,
        'targetWeight': targetWeight,
        'dailyCalorieTarget': dailyCalorieTarget,
        'tdee': tdee,
      };

  static String _str(dynamic v) => v is String ? v : '';
  static double? _num(dynamic v) => v is num ? v.toDouble() : null;
}

/// 空计划模板
PlanMeta emptyPlanMeta() => PlanMeta();

/// 整个计划数据
class PlanData {
  String version;
  PlanMeta meta;
  List<MealItem> meals;
  List<ExerciseItem> exercises;
  List<String> deletedIds;

  PlanData({
    this.version = '1.0',
    PlanMeta? meta,
    List<MealItem>? meals,
    List<ExerciseItem>? exercises,
    List<String>? deletedIds,
  })  : meta = meta ?? PlanMeta(),
        meals = meals ?? [],
        exercises = exercises ?? [],
        deletedIds = deletedIds ?? [];

  factory PlanData.empty() => PlanData();

  factory PlanData.fromJson(Map<String, dynamic> json) => PlanData(
        version: _str(json['version']),
        meta: json['meta'] is Map
            ? PlanMeta.fromJson(Map<String, dynamic>.from(json['meta'] as Map))
            : PlanMeta(),
        meals: (json['meals'] is List)
            ? (json['meals'] as List)
                .whereType<Map>()
                .map((e) => MealItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        exercises: (json['exercises'] is List)
            ? (json['exercises'] as List)
                .whereType<Map>()
                .map((e) => ExerciseItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : [],
        deletedIds: (json['deletedIds'] is List)
            ? (json['deletedIds'] as List).whereType<String>().toList()
            : [],
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'meta': meta.toJson(),
        'meals': meals.map((e) => e.toJson()).toList(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'deletedIds': deletedIds,
      };

  bool get hasPlan => meals.isNotEmpty || exercises.isNotEmpty;

  static String _str(dynamic v) => v is String ? v : '';
}
