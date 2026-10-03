/// 当日记录数据：打卡 / 加餐 / 实际热量覆盖 / 临时任务 / 当日条目快照 / 体重记录
/// 与旧版存储结构 1:1 兼容：
///   checkRecords: { date: { "meal:id"/"exercise:id"/"temp:id": { checkedAt } } }
///   extraFoods:   { date: [ { id, name, calories, source, at } ] }（已废弃迁移，仅保留兼容）
///   mealAdjust:   { date: { "meal:id": { calories, note } } }（v1.5 起停写，旧数据保留）
///   tempTasks:    { date: [ { id, type: 'snack'|'exercise', name, time, calories, source } ] }（v1.5 起停写，旧数据保留）
///   dayEntries:   { date: [ DayEntry ] }（F11 当日条目快照：餐食与运动统一，打卡状态仍在 checkRecords）
///   weightRecords:{ baseline?, records }（F10 体重记录与基础消耗快照，见 weight.dart）
library;

import 'weight.dart';

/// 打卡记录 { checkedAt: 时间戳 }
class CheckEntry {
  int checkedAt;
  CheckEntry({required this.checkedAt});

  factory CheckEntry.fromJson(dynamic json) {
    if (json is Map && json['checkedAt'] is num) {
      return CheckEntry(checkedAt: (json['checkedAt'] as num).round());
    }
    return CheckEntry(checkedAt: 0);
  }

  Map<String, dynamic> toJson() => {'checkedAt': checkedAt};
}

/// 临时任务 / 加餐记录项
class TempTask {
  String id;
  String type; // 'snack' | 'exercise'
  String name;
  String time;
  int calories;
  String source;

  TempTask({
    required this.id,
    this.type = 'snack',
    this.name = '',
    this.time = '',
    this.calories = 0,
    this.source = 'manual',
  });

  factory TempTask.fromJson(Map<String, dynamic> json) => TempTask(
        id: json['id'] is String ? json['id'] as String : '',
        type: json['type'] is String ? json['type'] as String : 'snack',
        name: json['name'] is String ? json['name'] as String : '',
        time: json['time'] is String ? json['time'] as String : '',
        calories: json['calories'] is num ? (json['calories'] as num).round() : 0,
        source: json['source'] is String ? json['source'] as String : 'manual',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'time': time,
        'calories': calories,
        'source': source,
      };

  bool get isExercise => type == 'exercise';
}

/// 食物拆解明细（吃了啥、估算份量/重量、估算热量）
class FoodBreakdownItem {
  final String name; // 食物/食材名称，如 "米饭"、"鸡胸肉"
  final String portion; // 估算重量/份量，如 "150g"、"半盘"、"1个"
  final int calories; // 估算热量，如 175

  const FoodBreakdownItem({
    required this.name,
    required this.portion,
    required this.calories,
  });

  factory FoodBreakdownItem.fromJson(Map<String, dynamic> json) => FoodBreakdownItem(
        name: json['name'] is String ? json['name'] as String : '',
        portion: json['portion'] is String
            ? json['portion'] as String
            : (json['weight'] is String ? json['weight'] as String : ''),
        calories: json['calories'] is num ? (json['calories'] as num).round() : 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'portion': portion,
        'calories': calories,
      };
}

/// 当日条目快照（F11：计划 = 模板，快照 = 事实）
/// 餐食与运动统一模型（kind 区分）；打卡状态不在此（仍在 checkRecords，键空间 meal:/exercise:/temp:）
/// 字段口径：content = 食物内容/运动内容；calories = 餐摄入/运动消耗（null=待补录）
/// detached = 内容被改过、与计划脱钩（永不跟随计划变化）；caloriesDirty = 热量/消耗被手改（false 时跟随计划值）
class DayEntry {
  String id;
  String kind; // 'meal' | 'exercise'
  String slot; // breakfast | lunch | dinner | snack（运动为 ''）
  String time; // HH:mm（跟随计划或录入时刻）
  String content;
  int? calories;
  int? protein; // 蛋白质 (g)
  int? carbs;   // 碳水 (g)
  int? fat;     // 脂肪 (g)
  String note;
  String source; // plan | manual | ai | fooddb
  String planItemId; // 关联计划项 id；'' 表示计划外
  bool detached;
  bool caloriesDirty;
  String? detail; // AI 拆解/测算文本描述
  List<FoodBreakdownItem>? items; // 食物与热量拆解表格明细

  DayEntry({
    required this.id,
    this.kind = 'meal',
    this.slot = '',
    this.time = '',
    this.content = '',
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.note = '',
    this.source = 'manual',
    this.planItemId = '',
    this.detached = false,
    this.caloriesDirty = false,
    this.detail,
    this.items,
  });

  factory DayEntry.fromJson(Map<String, dynamic> json) => DayEntry(
        id: _str(json['id']),
        kind: _str(json['kind']) == 'exercise' ? 'exercise' : 'meal',
        slot: _str(json['slot']),
        time: _str(json['time']),
        content: _str(json['content']),
        calories: json['calories'] is num ? (json['calories'] as num).round() : null,
        protein: json['protein'] is num ? (json['protein'] as num).round() : null,
        carbs: json['carbs'] is num ? (json['carbs'] as num).round() : null,
        fat: json['fat'] is num ? (json['fat'] as num).round() : null,
        note: _str(json['note']),
        source: _str(json['source']).isNotEmpty ? _str(json['source']) : 'manual',
        planItemId: _str(json['planItemId']),
        detached: json['detached'] is bool ? json['detached'] as bool : false,
        caloriesDirty: json['caloriesDirty'] is bool ? json['caloriesDirty'] as bool : false,
        detail: json['detail'] is String ? json['detail'] as String : null,
        items: (json['items'] as List?)
            ?.map((e) => e is Map ? FoodBreakdownItem.fromJson(Map<String, dynamic>.from(e)) : null)
            .whereType<FoodBreakdownItem>()
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'slot': slot,
        'time': time,
        'content': content,
        'calories': calories,
        if (protein != null) 'protein': protein,
        if (carbs != null) 'carbs': carbs,
        if (fat != null) 'fat': fat,
        'note': note,
        'source': source,
        'planItemId': planItemId,
        'detached': detached,
        'caloriesDirty': caloriesDirty,
        if (detail != null) 'detail': detail,
        if (items != null) 'items': items!.map((e) => e.toJson()).toList(),
      };

  /// 是否计划来源条目
  bool get isPlan => source == 'plan';

  static String _str(dynamic v) => v is String ? v : '';
}

/// 实际热量覆盖值
class AdjustEntry {
  int calories;
  String note;
  AdjustEntry({required this.calories, this.note = ''});

  factory AdjustEntry.fromJson(Map<String, dynamic> json) => AdjustEntry(
        calories: json['calories'] is num ? (json['calories'] as num).round() : 0,
        note: json['note'] is String ? json['note'] as String : '',
      );

  Map<String, dynamic> toJson() => {'calories': calories, 'note': note};
}

/// 记录聚合仓库（对应旧版 record.js 的 4 个 reactive 单例）
class RecordStore {
  /// { date: { "meal:id"/"exercise:id"/"temp:id": CheckEntry } }
  Map<String, Map<String, CheckEntry>> checkRecords;

  /// { date: `List<TempTask>` }（旧版加餐记录，已废弃迁移但保留兼容读写）
  Map<String, List<dynamic>> extraFoods;

  /// { date: { "meal:id": AdjustEntry } }
  Map<String, Map<String, AdjustEntry>> mealAdjust;

  /// { date: `List<TempTask>` }（v1.5 起停写，旧数据保留兼容读写）
  Map<String, List<TempTask>> tempTasks;

  /// { date: `List<DayEntry>` }（F11 当日条目快照，不参与 400 天裁剪）
  Map<String, List<DayEntry>> dayEntries;

  /// 体重记录（F10：{ baseline, records }，一天一条，不参与 400 天裁剪）
  WeightData weightRecords;

  RecordStore({
    Map<String, Map<String, CheckEntry>>? checkRecords,
    Map<String, List<dynamic>>? extraFoods,
    Map<String, Map<String, AdjustEntry>>? mealAdjust,
    Map<String, List<TempTask>>? tempTasks,
    Map<String, List<DayEntry>>? dayEntries,
    WeightData? weightRecords,
  })  : checkRecords = checkRecords ?? {},
        extraFoods = extraFoods ?? {},
        mealAdjust = mealAdjust ?? {},
        tempTasks = tempTasks ?? {},
        dayEntries = dayEntries ?? {},
        weightRecords = weightRecords ?? WeightData.empty();

  factory RecordStore.empty() => RecordStore();

  /// 从存储 JSON 反序列化（5 个顶层键）
  factory RecordStore.fromJson(Map<String, dynamic> json) {
    final checks = <String, Map<String, CheckEntry>>{};
    if (json['checkRecords'] is Map) {
      (json['checkRecords'] as Map).forEach((date, dayMap) {
        if (dayMap is Map) {
          checks[date.toString()] = dayMap.map((k, v) =>
              MapEntry(k.toString(), CheckEntry.fromJson(v)));
        }
      });
    }
    final foods = <String, List<dynamic>>{};
    if (json['extraFoods'] is Map) {
      (json['extraFoods'] as Map).forEach((date, list) {
        if (list is List) foods[date.toString()] = list;
      });
    }
    final adjusts = <String, Map<String, AdjustEntry>>{};
    if (json['mealAdjust'] is Map) {
      (json['mealAdjust'] as Map).forEach((date, dayMap) {
        if (dayMap is Map) {
          adjusts[date.toString()] = dayMap.map(
              (k, v) => MapEntry(k.toString(), AdjustEntry.fromJson(Map<String, dynamic>.from(v as Map))));
        }
      });
    }
    final temps = <String, List<TempTask>>{};
    if (json['tempTasks'] is Map) {
      (json['tempTasks'] as Map).forEach((date, list) {
        if (list is List) {
          temps[date.toString()] = list
              .whereType<Map>()
              .map((e) => TempTask.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      });
    }
    final entries = <String, List<DayEntry>>{};
    if (json['dayEntries'] is Map) {
      (json['dayEntries'] as Map).forEach((date, list) {
        if (list is List) {
          entries[date.toString()] = list
              .whereType<Map>()
              .map((e) => DayEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      });
    }
    return RecordStore(
      checkRecords: checks,
      extraFoods: foods,
      mealAdjust: adjusts,
      tempTasks: temps,
      dayEntries: entries,
      weightRecords: json['weightRecords'] is Map
          ? WeightData.fromJson(Map<String, dynamic>.from(json['weightRecords'] as Map))
          : WeightData.empty(),
    );
  }

  Map<String, dynamic> toJson() => {
        'checkRecords': checkRecords.map((d, m) =>
            MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))),
        'extraFoods': extraFoods,
        'mealAdjust': mealAdjust.map((d, m) =>
            MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))),
        'tempTasks': tempTasks.map((d, list) =>
            MapEntry(d, list.map((e) => e.toJson()).toList())),
        'dayEntries': dayEntries.map((d, list) =>
            MapEntry(d, list.map((e) => e.toJson()).toList())),
        'weightRecords': weightRecords.toJson(),
      };

  // ---------- 查询 ----------
  bool isChecked(String date, String type, String id) {
    return checkRecords[date]?.containsKey('$type:$id') ?? false;
  }

  List<TempTask> getTempTasks(String date) => tempTasks[date] ?? [];

  AdjustEntry? getAdjust(String date, String type, String id) {
    return mealAdjust[date]?['$type:$id'];
  }
}
