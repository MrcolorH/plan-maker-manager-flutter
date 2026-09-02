/// 当日记录数据：打卡 / 加餐 / 实际热量覆盖 / 临时任务
/// 与旧版存储结构 1:1 兼容：
///   checkRecords: { date: { "meal:id"/"exercise:id"/"temp:id": { checkedAt } } }
///   extraFoods:   { date: [ { id, name, calories, source, at } ] }（已废弃迁移，仅保留兼容）
///   mealAdjust:   { date: { "meal:id": { calories, note } } }
///   tempTasks:    { date: [ { id, type: 'snack'|'exercise', name, time, calories, source } ] }
library;

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

  /// { date: `List<TempTask>` }
  Map<String, List<TempTask>> tempTasks;

  RecordStore({
    Map<String, Map<String, CheckEntry>>? checkRecords,
    Map<String, List<dynamic>>? extraFoods,
    Map<String, Map<String, AdjustEntry>>? mealAdjust,
    Map<String, List<TempTask>>? tempTasks,
  })  : checkRecords = checkRecords ?? {},
        extraFoods = extraFoods ?? {},
        mealAdjust = mealAdjust ?? {},
        tempTasks = tempTasks ?? {};

  factory RecordStore.empty() => RecordStore();

  /// 从存储 JSON 反序列化（4 个顶层键）
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
    return RecordStore(
      checkRecords: checks,
      extraFoods: foods,
      mealAdjust: adjusts,
      tempTasks: temps,
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
