/// 打卡、加餐、当日调整与临时任务状态层（对应旧版 record.js）
/// 当日数据与整体计划分离：mealAdjust/tempTasks 只影响对应日期，不改动 plan
library;

import 'package:flutter/foundation.dart';

import '../models/records.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';
import '../utils/plan_utils.dart';

class RecordProvider extends ChangeNotifier {
  final StorageService _storage;

  RecordStore store;

  RecordProvider(this._storage) : store = RecordStore.empty() {
    _load();
  }

  void _load() {
    store = RecordStore.fromJson({
      'checkRecords': _storage.readMap(StorageService.kCheckRecords),
      'extraFoods': _storage.readMap(StorageService.kExtraFoods),
      'mealAdjust': _storage.readMap(StorageService.kMealAdjust),
      'tempTasks': _storage.readMap(StorageService.kTempTasks),
    });
    _prune();
    _migrateExtraFoods();
  }

  Future<void> _persistAll() async {
    await _storage.writeMap(StorageService.kCheckRecords, store.checkRecords.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))));
    await _storage.writeMap(StorageService.kExtraFoods, store.extraFoods);
    await _storage.writeMap(StorageService.kMealAdjust, store.mealAdjust.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))));
    await _storage.writeMap(StorageService.kTempTasks, store.tempTasks.map((d, l) => MapEntry(d, l.map((e) => e.toJson()).toList())));
  }

  Future<void> _persistCheck() async {
    await _storage.writeMap(StorageService.kCheckRecords, store.checkRecords.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))));
  }

  Future<void> _persistFoods() async {
    await _storage.writeMap(StorageService.kExtraFoods, store.extraFoods);
  }

  Future<void> _persistAdjust() async {
    await _storage.writeMap(StorageService.kMealAdjust, store.mealAdjust.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))));
  }

  Future<void> _persistTemps() async {
    await _storage.writeMap(StorageService.kTempTasks, store.tempTasks.map((d, l) => MapEntry(d, l.map((e) => e.toJson()).toList())));
  }

  /// 只保留近 400 天数据，防止无限膨胀
  void _prune() {
    final limit = addDays(todayStr(), -400);
    var dirty = false;
    store.checkRecords.removeWhere((k, _) => k.compareTo(limit) < 0);
    store.extraFoods.removeWhere((k, _) => k.compareTo(limit) < 0);
    store.mealAdjust.removeWhere((k, _) => k.compareTo(limit) < 0);
    store.tempTasks.removeWhere((k, _) => k.compareTo(limit) < 0);
    // 保守处理：仅在确有删除时标记（简化：加载后总是持久化一次裁剪结果）
    dirty = true;
    if (dirty) _persistAll();
  }

  /// 一次性迁移：旧「加餐记录」并入「今日临时加餐」（两者语义合并后 extraFoods 不再使用）
  void _migrateExtraFoods() {
    if (store.extraFoods.isEmpty) return;
    final migrated = <String, List<TempTask>>{};
    store.extraFoods.forEach((date, list) {
      final tasks = <TempTask>[];
      for (final f in list) {
        if (f is! Map) continue;
        tasks.add(TempTask(
          id: f['id'] is String ? f['id'] as String : genId('t'),
          type: 'snack',
          name: f['name'] is String ? f['name'] as String : '加餐',
          time: f['at'] is String ? f['at'] as String : '12:00',
          calories: f['calories'] is num ? (f['calories'] as num).round() : 0,
          source: f['source'] is String ? f['source'] as String : 'manual',
        ));
      }
      if (tasks.isNotEmpty) {
        migrated[date] = [...(store.tempTasks[date] ?? []), ...tasks];
      }
    });
    if (migrated.isNotEmpty) {
      store.tempTasks.addAll(migrated);
      store.extraFoods.clear();
      _persistTemps();
      _persistFoods();
    }
  }

  // ---------- 打卡 ----------

  bool isChecked(String date, String type, String id) => store.isChecked(date, type, id);

  /// 打卡/取消打卡；返回打卡后的状态
  Future<bool> toggleCheck(String date, String type, String id) async {
    if (!store.checkRecords.containsKey(date)) {
      store.checkRecords[date] = {};
    }
    final key = '$type:$id';
    if (store.checkRecords[date]!.containsKey(key)) {
      store.checkRecords[date]!.remove(key);
    } else {
      store.checkRecords[date]![key] = CheckEntry(checkedAt: DateTime.now().millisecondsSinceEpoch);
    }
    notifyListeners();
    await _persistCheck();
    return store.isChecked(date, type, id);
  }

  // ---------- 加餐食物记录（旧版兼容，新入口走 tempTasks）----------

  List<dynamic> getExtraFoods(String date) => store.extraFoods[date] ?? [];

  int extraTotal(String date) {
    var total = 0;
    for (final f in (store.extraFoods[date] ?? [])) {
      if (f is Map && f['calories'] is num) total += (f['calories'] as num).round();
    }
    return total;
  }

  // ---------- 当日每餐实际热量覆盖（仅当天生效）----------

  AdjustEntry? getAdjust(String date, String type, String id) => store.getAdjust(date, type, id);

  /// val = { calories, note } 或 null（清除，恢复计划值）
  Future<void> setAdjust(String date, String type, String id, Map<String, dynamic>? val) async {
    if (!store.mealAdjust.containsKey(date)) {
      store.mealAdjust[date] = {};
    }
    final k = '$type:$id';
    if (val != null && val['calories'] is num) {
      store.mealAdjust[date]![k] = AdjustEntry(
        calories: (val['calories'] as num).round(),
        note: val['note'] is String ? val['note'] as String : '',
      );
    } else {
      store.mealAdjust[date]!.remove(k);
    }
    notifyListeners();
    await _persistAdjust();
  }

  // ---------- 临时任务（计划外记录，不改整体计划；支持今日与近 3 天补录）----------

  List<TempTask> getTempTasks(String date) => store.getTempTasks(date);

  Future<void> addTempTask(String date,
      {required String type, required String name, String? time, required int calories, String? source}) async {
    final isEx = type == 'exercise';
    if (!store.tempTasks.containsKey(date)) {
      store.tempTasks[date] = [];
    }
    store.tempTasks[date]!.add(TempTask(
      id: genId('t'),
      type: isEx ? 'exercise' : 'snack',
      name: name.isNotEmpty ? name : (isEx ? '临时运动' : '临时加餐'),
      time: (time != null && time.isNotEmpty) ? time : nowTimeStr(),
      calories: calories,
      source: source ?? 'manual',
    ));
    notifyListeners();
    await _persistTemps();
  }

  /// 删除临时任务（连同其打卡状态）
  Future<void> removeTempTask(String date, String id) async {
    final list = store.tempTasks[date];
    if (list != null) {
      list.removeWhere((t) => t.id == id);
    }
    store.checkRecords[date]?.remove('temp:$id');
    notifyListeners();
    await _persistTemps();
    await _persistCheck();
  }

  // ---------- 清空 ----------

  /// 仅清空打卡/加餐/调整/临时任务（保留计划与设置）
  Future<void> clearRecords() async {
    store.checkRecords.clear();
    store.extraFoods.clear();
    store.mealAdjust.clear();
    store.tempTasks.clear();
    notifyListeners();
    await _persistAll();
  }

  // ---------- 历史备份：增量合并 ----------

  /// bundle = BackupData（或含 checkRecords/mealAdjust/tempTasks/extraFoods 的 Map）
  /// 规则：打卡按 checkedAt 取较新（不把已打卡倒回未打卡）；调整/临时任务/旧加餐按 id 合并，导入文件优先
  Future<void> mergeRecords(BackupLike bundle) async {
    // 打卡：同 date 同 key 保留时间戳较大者
    if (bundle.checkRecords != null && bundle.checkRecords!.isNotEmpty) {
      bundle.checkRecords!.forEach((date, dayMap) {
        if (dayMap is! Map) return;
        final target = store.checkRecords.putIfAbsent(date, () => {});
        dayMap.forEach((key, v) {
          if (v is! Map) return;
          final sv = v['checkedAt'];
          if (sv is! num) return;
          final cv = target[key]?.checkedAt;
          if (cv == null || sv.toInt() > cv) {
            target[key] = CheckEntry(checkedAt: sv.toInt());
          }
        });
      });
      await _persistCheck();
    }

    // 当日实际热量覆盖：同 key 以备份覆盖，新 key 追加
    if (bundle.mealAdjust != null && bundle.mealAdjust!.isNotEmpty) {
      bundle.mealAdjust!.forEach((date, dayMap) {
        if (dayMap is! Map) return;
        final target = store.mealAdjust.putIfAbsent(date, () => {});
        dayMap.forEach((k, v) {
          if (v is Map) target[k] = AdjustEntry.fromJson(Map<String, dynamic>.from(v));
        });
      });
      await _persistAdjust();
    }

    // 临时任务 / 旧加餐：按 id 合并（同 id 取备份，新 id 追加；无 id 的旧条目直接追加）
    if (bundle.tempTasks != null && bundle.tempTasks!.isNotEmpty) {
      bundle.tempTasks!.forEach((date, list) {
        if (list is! List) return;
        final merged = _mergeByIdList<TempTask>(store.tempTasks[date] ?? const <TempTask>[], list);
        store.tempTasks[date] = merged;
      });
      await _persistTemps();
    }
    if (bundle.extraFoods != null && bundle.extraFoods!.isNotEmpty) {
      bundle.extraFoods!.forEach((date, list) {
        if (list is! List) return;
        final merged = _mergeByIdList<dynamic>(store.extraFoods[date] ?? const [], list);
        store.extraFoods[date] = merged;
      });
      await _persistFoods();
    }
    notifyListeners();
  }

  List<T> _mergeByIdList<T>(List<T> target, List<dynamic> list) {
    final out = List<T>.from(target);
    final idx = <String, int>{};
    for (var i = 0; i < out.length; i++) {
      final id = (out[i] as dynamic).id;
      if (id is String) idx[id] = i;
    }
    for (final it in list) {
      if (it is! Map) continue;
      final id = it['id'];
      final casted = _castById<T>(Map<String, dynamic>.from(it));
      if (id is String && idx.containsKey(id)) {
        out[idx[id]!] = casted;
      } else if (id is String) {
        idx[id] = out.length;
        out.add(casted);
      } else {
        out.add(casted);
      }
    }
    return out;
  }

  T _castById<T>(Map<String, dynamic> m) {
    // 由调用方保证类型一致（tempTasks → TempTask；extraFoods → 原始 Map）
    if (T == TempTask) return TempTask.fromJson(m) as T;
    return m as T;
  }

  // ---------- 历史备份：覆盖替换 ----------

  /// 清空现有记录后整体写入备份数据（覆盖导入使用）
  Future<void> replaceRecords(BackupLike bundle) async {
    final b = bundle;
    store.checkRecords = _parseChecks(b.checkRecords ?? {});
    store.mealAdjust = _parseAdjusts(b.mealAdjust ?? {});
    store.tempTasks = _parseTemps(b.tempTasks ?? {});
    store.extraFoods = Map<String, List<dynamic>>.from(b.extraFoods ?? {});
    notifyListeners();
    await _persistAll();
  }

  Map<String, Map<String, CheckEntry>> _parseChecks(Map<String, dynamic> src) {
    final out = <String, Map<String, CheckEntry>>{};
    src.forEach((date, dayMap) {
      if (dayMap is! Map) return;
      out[date] = dayMap.map((k, v) {
        if (v is Map && v['checkedAt'] is num) {
          return MapEntry(k.toString(), CheckEntry(checkedAt: (v['checkedAt'] as num).round()));
        }
        return MapEntry(k.toString(), CheckEntry(checkedAt: 0));
      });
    });
    return out;
  }

  Map<String, Map<String, AdjustEntry>> _parseAdjusts(Map<String, dynamic> src) {
    final out = <String, Map<String, AdjustEntry>>{};
    src.forEach((date, dayMap) {
      if (dayMap is! Map) return;
      out[date] = dayMap.map(
          (k, v) => MapEntry(k.toString(), AdjustEntry.fromJson(Map<String, dynamic>.from(v as Map))));
    });
    return out;
  }

  Map<String, List<TempTask>> _parseTemps(Map<String, dynamic> src) {
    final out = <String, List<TempTask>>{};
    src.forEach((date, list) {
      if (list is! List) return;
      out[date] = list
          .whereType<Map>()
          .map((e) => TempTask.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
    return out;
  }
}

/// 备份数据兼容视图（供 mergeRecords/replaceRecords 使用）
class BackupLike {
  final Map<String, dynamic>? checkRecords;
  final Map<String, dynamic>? mealAdjust;
  final Map<String, dynamic>? tempTasks;
  final Map<String, dynamic>? extraFoods;
  const BackupLike({this.checkRecords, this.mealAdjust, this.tempTasks, this.extraFoods});
}
