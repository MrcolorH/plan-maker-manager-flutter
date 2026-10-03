/// 打卡、加餐、当日调整与临时任务状态层（对应旧版 record.js）
/// 当日数据与整体计划分离：mealAdjust/tempTasks 只影响对应日期，不改动 plan
library;

import 'package:flutter/foundation.dart';

import '../models/plan_data.dart';
import '../models/records.dart';
import '../models/weight.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';
import '../utils/legacy_convert.dart';
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
      'dayEntries': _storage.readMap(StorageService.kDayEntries),
      'weightRecords': _storage.readMap(StorageService.kWeightRecords),
    });
    _prune();
    _migrateExtraFoods();
  }

  Future<void> _persistAll() async {
    await _storage.writeMap(StorageService.kCheckRecords, store.checkRecords.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))));
    await _storage.writeMap(StorageService.kExtraFoods, store.extraFoods);
    await _storage.writeMap(StorageService.kMealAdjust, store.mealAdjust.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))));
    await _storage.writeMap(StorageService.kTempTasks, store.tempTasks.map((d, l) => MapEntry(d, l.map((e) => e.toJson()).toList())));
    await _persistEntries();
    await _persistWeights();
  }

  Future<void> _persistWeights() async {
    await _storage.writeMap(StorageService.kWeightRecords, store.weightRecords.toJson());
  }

  Future<void> _persistEntries() async {
    await _storage.writeMap(StorageService.kDayEntries, store.dayEntries.map((d, l) => MapEntry(d, l.map((e) => e.toJson()).toList())));
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
  /// dayEntries（当日条目快照）**不参与裁剪**：历史固化是硬需求（F11 FR11.7）
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

  // ---------- 当日条目快照（F11：计划 = 模板，快照 = 事实）----------

  List<DayEntry> getDayEntries(String date) => store.dayEntries[date] ?? const [];

  /// 当天计划项 → 新建快照列表（不含归档，供 sync 使用）
  List<DayEntry> _instantiatePlan(String date, PlanData plan) {
    final tasks = getTasksForDate(plan, date);
    final out = <DayEntry>[];
    for (final m in tasks.meals) {
      out.add(DayEntry(
        id: m.id,
        kind: 'meal',
        slot: m.type,
        time: m.time,
        content: m.name,
        calories: m.calories,
        protein: m.protein,
        carbs: m.carbs,
        fat: m.fat,
        note: '',
        source: 'plan',
        planItemId: m.id,
      ));
    }
    for (final e in tasks.exercises) {
      out.add(DayEntry(
        id: e.id,
        kind: 'exercise',
        slot: '',
        time: e.time,
        content: e.name,
        calories: e.caloriesBurned,
        note: '',
        source: 'plan',
        planItemId: e.id,
      ));
    }
    return out;
  }

  bool _entriesEqual(List<DayEntry>? a, List<DayEntry>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_entryEq(a[i], b[i])) return false;
    }
    return true;
  }

  bool _entryEq(DayEntry a, DayEntry b) =>
      a.id == b.id &&
      a.kind == b.kind &&
      a.slot == b.slot &&
      a.time == b.time &&
      a.content == b.content &&
      a.calories == b.calories &&
      a.protein == b.protein &&
      a.carbs == b.carbs &&
      a.fat == b.fat &&
      a.note == b.note &&
      a.source == b.source &&
      a.planItemId == b.planItemId &&
      a.detached == b.detached &&
      a.caloriesDirty == b.caloriesDirty;

  /// 同步某天快照与当前计划（幂等；只对 ≤ 今天操作，未来日期不生成）。
  /// 规则（spec day-snapshot-design §4.1）：
  ///   - 计划外条目（加餐/加练，source != plan）原样保留，永不触碰
  ///   - 未脱钩条目跟随计划（content/time/slot；calories 未被手改则跟随）
  ///   - 未脱钩但计划里已删除（该日无此计划项）→ 移除；脱钩条目永不动
  ///   - 计划里新增 → 追加新快照
  /// 有变化才 notify + 落盘。
  Future<void> syncDayEntries(String date, PlanData plan) async {
    if (date.compareTo(todayStr()) > 0) return; // 未来日期不生成快照
    final planItems = _instantiatePlan(date, plan);
    final old = store.dayEntries[date];
    if (old == null && planItems.isEmpty) {
      // 无快照无计划（新用户/未制定计划）：生成默认早中晚三餐骨架
      await ensureDefaultMealEntries(date);
      return;
    }

    final kept = <DayEntry>[];
    for (final e in (old ?? const <DayEntry>[])) {
      if (!e.isPlan) {
        kept.add(e);
        continue;
      }
      final p = planItems.where((x) => x.kind == e.kind && x.id == e.planItemId).toList();
      if (p.isEmpty) {
        if (e.detached) kept.add(e); // 脱钩：计划里删了也永久保留
      } else if (!e.detached) {
        final s = p.first;
        kept.add(DayEntry(
          id: e.id,
          kind: e.kind,
          slot: s.slot,
          time: s.time,
          content: s.content,
          calories: e.caloriesDirty ? e.calories : s.calories,
          protein: e.caloriesDirty ? e.protein : s.protein,
          carbs: e.caloriesDirty ? e.carbs : s.carbs,
          fat: e.caloriesDirty ? e.fat : s.fat,
          note: e.note,
          source: 'plan',
          planItemId: e.planItemId,
          detached: false,
          caloriesDirty: e.caloriesDirty,
        ));
      } else {
        kept.add(e);
      }
    }
    for (final p in planItems) {
      if (!kept.any((e) => e.isPlan && e.kind == p.kind && e.planItemId == p.id)) {
        kept.add(p);
      }
    }

    // 若当前完全无计划（如清空或尚未制定），且没有任何正餐条目，补全早中晚骨架
    if (!plan.hasPlan && !kept.any((e) => e.kind == 'meal' && e.slot != 'snack')) {
      const defaultSlots = [
        (slot: 'breakfast', time: '08:00'),
        (slot: 'lunch', time: '12:00'),
        (slot: 'dinner', time: '18:30'),
      ];
      for (final s in defaultSlots) {
        kept.add(DayEntry(
          id: genId('m'),
          kind: 'meal',
          slot: s.slot,
          time: s.time,
          content: '',
          calories: null,
          source: 'manual',
          planItemId: '',
          detached: true,
          caloriesDirty: true,
        ));
      }
    }

    sortDayEntries(kept);
    if (_entriesEqual(old, kept)) return;
    store.dayEntries[date] = kept;
    notifyListeners();
    await _persistEntries();
  }

  /// 计划外录入（加餐 / 加练 / 补录）：source 保留；添加即计缺口/消耗，不参与完成度
  Future<void> addDayEntry(
    String date, {
    required String kind, // 'meal' | 'exercise'
    required String content,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    String slot = '',
    String? time,
    String note = '',
    String source = 'manual',
    String? detail,
    List<FoodBreakdownItem>? items,
  }) async {
    final list = store.dayEntries.putIfAbsent(date, () => []);
    list.add(DayEntry(
      id: genId(kind == 'exercise' ? 'e' : 'm'),
      kind: kind,
      slot: kind == 'meal' ? (slot.isNotEmpty ? slot : 'snack') : '',
      time: (time != null && time.isNotEmpty) ? time : nowTimeStr(),
      content: content.isNotEmpty ? content : (kind == 'meal' ? '加餐' : '临时运动'),
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      note: note,
      source: source,
      planItemId: '',
      detached: true,
      caloriesDirty: true,
      detail: detail,
      items: items,
    ));
    sortDayEntries(list);
    notifyListeners();
    await _persistEntries();
  }

  /// 更新某天某条快照的内容（编辑弹窗保存）；不触碰打卡状态（由调用方决定是否 toggleCheck）
  Future<void> updateDayEntry(String date, DayEntry updated) async {
    final list = store.dayEntries[date];
    if (list == null) return;
    final i = list.indexWhere((e) => e.id == updated.id);
    if (i < 0) return;
    list[i] = updated;
    sortDayEntries(list);
    notifyListeners();
    await _persistEntries();
  }

  /// 删除计划外条目（加餐/加练，可删；正餐/计划运动快照不提供删除入口）
  /// 同时清理其打卡状态（temp:&lt;id&gt;，兼容旧键空间）
  Future<void> removeDayEntry(String date, String id) async {
    final list = store.dayEntries[date];
    if (list == null) return;
    final e = list.where((x) => x.id == id).firstOrNull;
    list.removeWhere((x) => x.id == id);
    if (e != null && !e.isPlan) {
      store.checkRecords[date]?.remove('temp:${e.id}');
      await _persistCheck();
    }
    notifyListeners();
    await _persistEntries();
  }

  /// 打卡键（快照渲染用）：计划条目沿用 meal:/exercise:；计划外条目用 temp:
  /// 例：'meal:abc'（计划餐）、'exercise:abc'（计划运动）、'temp:xyz'（计划外加餐/加练）
  String checkKeyOf(DayEntry e) {
    if (e.isPlan) return '${e.kind == 'meal' ? 'meal' : 'exercise'}:${e.planItemId}';
    return 'temp:${e.id}';
  }

  bool isEntryChecked(String date, DayEntry e) =>
      store.checkRecords[date]?.containsKey(checkKeyOf(e)) ?? false;

  /// 对任意快照条目进行打卡/取消打卡（支持计划条目与计划外正餐/加餐）
  Future<bool> toggleEntryCheck(String date, DayEntry e) async {
    final key = checkKeyOf(e);
    final colonIdx = key.indexOf(':');
    final type = colonIdx > 0 ? key.substring(0, colonIdx) : 'temp';
    final id = colonIdx > 0 ? key.substring(colonIdx + 1) : e.id;
    return toggleCheck(date, type, id);
  }

  /// 迁移打卡状态（例如条目从计划外 temp: 升级为日常计划 meal: 时，平滑保留打卡标记）
  Future<void> migrateEntryCheck({
    required String date,
    required String oldCheckKey,
    required String newCheckKey,
  }) async {
    if (oldCheckKey == newCheckKey) return;
    final dayCheck = store.checkRecords[date];
    if (dayCheck != null && dayCheck.containsKey(oldCheckKey)) {
      final val = dayCheck.remove(oldCheckKey);
      if (val != null) {
        dayCheck[newCheckKey] = val;
        notifyListeners();
        await _persistCheck();
      }
    }
  }

  /// 确保某天有默认的早中晚三餐骨架（无计划/冷启动或某餐缺位时补齐空白待录入项）
  Future<void> ensureDefaultMealEntries(String date) async {
    if (date.compareTo(todayStr()) > 0) return; // 未来日期不自动补
    final list = store.dayEntries.putIfAbsent(date, () => []);
    const slots = [
      (slot: 'breakfast', time: '08:00'),
      (slot: 'lunch', time: '12:00'),
      (slot: 'dinner', time: '18:30'),
    ];
    var changed = false;
    for (final s in slots) {
      final exists = list.any((e) => e.kind == 'meal' && e.slot == s.slot);
      if (!exists) {
        list.add(DayEntry(
          id: genId('m'),
          kind: 'meal',
          slot: s.slot,
          time: s.time,
          content: '',
          calories: null,
          source: 'manual',
          planItemId: '',
          detached: true,
          caloriesDirty: true,
        ));
        changed = true;
      }
    }
    if (changed) {
      sortDayEntries(list);
      notifyListeners();
      await _persistEntries();
    }
  }

  /// 升级首启迁移：把本机旧格式存量一次性转换为快照（幂等，kDayEntries 已存在则跳过）
  Future<void> migrateIfNeeded(PlanData plan) async {
    if (_storage.readString(StorageService.kDayEntries) != null) return; // 已迁移（含空）
    final converted = convertLegacyToEntries(
      plan: plan,
      checkRecords: _storage.readMap(StorageService.kCheckRecords),
      mealAdjust: _storage.readMap(StorageService.kMealAdjust),
      tempTasks: _storage.readMap(StorageService.kTempTasks),
      extraFoods: _storage.readMap(StorageService.kExtraFoods),
    );
    if (converted.isNotEmpty) {
      store.dayEntries = converted;
      notifyListeners();
      await _persistEntries();
    } else {
      // 无记录也要落一个空标记，防止每次启动重扫
      await _storage.writeMap(StorageService.kDayEntries, {});
    }
  }

  /// v1 老备份 → 快照（导入管线内直接转换；用备份自带 planData 投影）
  /// 返回转换结果供导入概要展示；调用方负责把结果并入 store（merge/replace）
  Map<String, List<DayEntry>> convertBackupEntries({
    required PlanData plan,
    Map<String, dynamic>? checkRecords,
    Map<String, dynamic>? mealAdjust,
    Map<String, dynamic>? tempTasks,
    Map<String, dynamic>? extraFoods,
  }) {
    return convertLegacyToEntries(
      plan: plan,
      checkRecords: checkRecords,
      mealAdjust: mealAdjust,
      tempTasks: tempTasks,
      extraFoods: extraFoods,
    );
  }

  // ---------- 体重记录（F10：历史基础消耗固化）----------

  /// 本机是否有历史记录（供 ensureBaseline 判断是否需要固化）
  bool get hasHistory =>
      store.checkRecords.isNotEmpty ||
      store.tempTasks.isNotEmpty ||
      store.extraFoods.isNotEmpty ||
      store.mealAdjust.isNotEmpty ||
      store.dayEntries.isNotEmpty;

  /// 固化历史基准（幂等）：baseline 已存在则跳过；
  /// [base] = 固化时的基础消耗（baseBurn(settings) 现值）
  Future<void> ensureBaseline(int base) async {
    final w = store.weightRecords;
    if (w.baseline != null || !hasHistory) return;
    if (base <= 0) return;
    w.baseline = WeightBaseline(base: base, date: todayStr());
    notifyListeners();
    await _persistWeights();
  }

  /// 写入/覆盖某天体重与体脂率（同日重复录入刷新 updatedAt）；[bmr] = 录入时快照的 BMR（基础信息不全传 0）
  Future<void> setWeightRecord(
    double weight,
    int bmr, {
    String? date,
    int? updatedAt,
    double? bodyFat,
  }) async {
    final d = (date != null && date.isNotEmpty) ? date : todayStr();
    store.weightRecords.records[d] = WeightEntry(
      weight: weight,
      bmr: bmr,
      bodyFat: bodyFat,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
    notifyListeners();
    await _persistWeights();
  }

  /// 删除某天体重记录（删除仅影响展示与后续沿用，不回改 baseline）
  Future<void> removeWeightRecord(String date) async {
    if (store.weightRecords.records.remove(date) != null) {
      notifyListeners();
      await _persistWeights();
    }
  }

  // ---------- 清空 ----------

  /// 仅清空打卡/加餐/调整/临时任务/当日快照/体重记录（保留计划与设置）
  Future<void> clearRecords() async {
    store.checkRecords.clear();
    store.extraFoods.clear();
    store.mealAdjust.clear();
    store.tempTasks.clear();
    store.dayEntries.clear();
    store.weightRecords = WeightData.empty();
    notifyListeners();
    await _persistAll();
  }

  // ---------- 历史备份：增量合并 ----------

  /// bundle = BackupData（或含 checkRecords/mealAdjust/tempTasks/extraFoods/dayEntries 的 Map）
  /// 规则：打卡按 checkedAt 取较新（不把已打卡倒回未打卡）；调整/临时任务/旧加餐按 id 合并，导入文件优先；
  ///       当日快照 dayEntries 按「同 date 内同 id 合并、新 id 追加、导入优先」（v2 备份直入；v1 备份由调用方先转换）
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

    // 当日条目快照：同 date 内按 id 合并（导入优先、新 id 追加），合并后按 time 排序
    if (bundle.dayEntries != null && bundle.dayEntries!.isNotEmpty) {
      bundle.dayEntries!.forEach((date, list) {
        if (list is! List) return;
        final d = date.toString();
        final target = store.dayEntries.putIfAbsent(d, () => []);
        final idx = <String, int>{};
        for (var i = 0; i < target.length; i++) {
          idx[target[i].id] = i;
        }
        for (final it in list) {
          if (it is! Map) continue;
          final id = it['id'];
          if (id is! String || id.isEmpty) continue;
          final entry = DayEntry.fromJson(Map<String, dynamic>.from(it));
          if (idx.containsKey(id)) {
            target[idx[id]!] = entry;
          } else {
            idx[id] = target.length;
            target.add(entry);
          }
        }
        sortDayEntries(target);
      });
      await _persistEntries();
    }

    // 体重记录：records 按 updatedAt 取较新；baseline 双方都有取日期较早者（保留更长历史基准）
    if (bundle.weightRecords != null && bundle.weightRecords!.isNotEmpty) {
      final src = WeightData.fromJson(Map<String, dynamic>.from(bundle.weightRecords!));
      final tgt = store.weightRecords;
      if (src.baseline != null) {
        final b = tgt.baseline;
        if (b == null ||
            (src.baseline!.date.isNotEmpty && src.baseline!.date.compareTo(b.date) < 0)) {
          tgt.baseline = src.baseline;
        }
      }
      src.records.forEach((date, e) {
        final cur = tgt.records[date];
        if (cur == null || e.updatedAt >= cur.updatedAt) tgt.records[date] = e;
      });
      await _persistWeights();
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
    store.dayEntries = _parseDayEntries(b.dayEntries ?? {});
    store.weightRecords = (b.weightRecords != null && b.weightRecords!.isNotEmpty)
        ? WeightData.fromJson(Map<String, dynamic>.from(b.weightRecords!))
        : WeightData.empty();
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

  Map<String, List<DayEntry>> _parseDayEntries(Map<String, dynamic> src) {
    final out = <String, List<DayEntry>>{};
    src.forEach((date, list) {
      if (list is! List) return;
      final entries = list
          .whereType<Map>()
          .map((e) => DayEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      sortDayEntries(entries);
      if (entries.isNotEmpty) out[date.toString()] = entries;
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
  final Map<String, dynamic>? dayEntries;
  final Map<String, dynamic>? weightRecords;
  const BackupLike({
    this.checkRecords,
    this.mealAdjust,
    this.tempTasks,
    this.extraFoods,
    this.dayEntries,
    this.weightRecords,
  });
}
