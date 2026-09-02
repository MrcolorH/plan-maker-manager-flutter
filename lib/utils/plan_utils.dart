/// 计划解析/校验/当日任务计算（与旧版 uni-app plan.js 1:1 对齐）
/// 校验与归一化对 AI 生成的输出做了容错：数字字符串、带秒时间、中文 type 均自动纠正
library;

import '../models/plan_data.dart';
import 'date_utils.dart';

const List<String> kMealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];
const Map<String, String> kTypeCn = {
  'breakfast': '早餐',
  'lunch': '午餐',
  'dinner': '晚餐',
  'snack': '加餐',
};

const Map<String, String> _typeAlias = {
  'breakfast': 'breakfast', '早餐': 'breakfast',
  'lunch': 'lunch', '午餐': 'lunch',
  'dinner': 'dinner', '晚餐': 'dinner',
  'snack': 'snack', '加餐': 'snack',
};

/// 生成唯一 id（与 JS 版 genId 同构：前缀 + 时间戳36进制 + 随机数36进制5位）
String genId(String prefix) {
  final ts = DateTime.now().millisecondsSinceEpoch.toString();
  final rand = (DateTime.now().microsecondsSinceEpoch % 100000).toString();
  final base36 = (int.parse(ts) * 100 + DateTime.now().second).toRadixString(36);
  final rand36 = rand.padLeft(5, '0');
  return '$prefix-$base36-$rand36';
}

// ---------- 容错工具 ----------

/// 数字或数字字符串 → 数字；否则 null
num? _toNum(dynamic v) {
  if (v is num && v.isFinite) return v;
  if (v is String && v.trim().isNotEmpty && num.tryParse(v.trim()) != null) {
    return num.parse(v.trim());
  }
  return null;
}

/// "12:00" / "12:00:00" → "12:00"；非法返回 ''
String _normalizeTime(dynamic v) {
  if (v is! String) return '';
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?$').firstMatch(v.trim());
  return m != null ? '${m.group(1)}:${m.group(2)}' : '';
}

/// days 容错（"3" / 3 / [1,2] 混排，单个数字视为仅那一天）→ [1-7] 去重数字
List<int> _daysArr(dynamic v) {
  if (v is num || v is String) {
    final n = _toNum(v);
    return (n != null && n == n.roundToDouble() && n >= 1 && n <= 7) ? [n.round()] : [];
  }
  if (v is! List) return [];
  final out = <int>[];
  for (final d in v) {
    final n = _toNum(d);
    if (n != null && n == n.roundToDouble() && n >= 1 && n <= 7) out.add(n.round());
  }
  return out.toSet().toList();
}

/// dates 容错（"2026-09-05" / 数组混排）→ 去重升序的合法日期数组
List<String> _datesArr(dynamic v) {
  final list = v is List ? v : (v is String ? [v] : <dynamic>[]);
  final out = list.whereType<String>().where(isValidDateStr).toSet().toList();
  out.sort();
  return out;
}

// ---------- 校验（导入前调用）----------

/// 返回中文错误信息数组；空数组 = 通过
List<String> validateRaw(dynamic raw) {
  final errs = <String>[];
  if (raw is! Map) {
    return ['JSON 根节点必须是对象 { }'];
  }
  if (raw['version'] != '1.0') errs.add('版本不支持：version 必须为 "1.0"');
  if (raw['meals'] != null && raw['meals'] is! List) errs.add('meals 必须是数组');
  if (raw['exercises'] != null && raw['exercises'] is! List) errs.add('exercises 必须是数组');
  final hasMeals = raw['meals'] is List && (raw['meals'] as List).isNotEmpty;
  final hasExercises = raw['exercises'] is List && (raw['exercises'] as List).isNotEmpty;
  if (!hasMeals && !hasExercises) errs.add('导入内容为空：meals 或 exercises 至少需要一项');

  final meta = raw['meta'];
  if (meta is Map) {
    if (meta['startDate'] is String && !isValidDateStr(meta['startDate'] as String)) {
      errs.add('meta.startDate 日期格式错误，应为 YYYY-MM-DD');
    }
    if (meta['endDate'] is String && !isValidDateStr(meta['endDate'] as String)) {
      errs.add('meta.endDate 日期格式错误，应为 YYYY-MM-DD');
    }
    const nums = [['baseWeight', 500], ['targetWeight', 500], ['dailyCalorieTarget', 10000], ['tdee', 10000]];
    for (final entry in nums) {
      final k = entry[0] as String;
      final max = entry[1] as int;
      final v = meta[k];
      if (v != null && v != '') {
        final n = _toNum(v);
        if (n == null || n < 0 || n > max) {
          errs.add('meta.$k 必须是不超过 $max 的数字');
        }
      }
    }
  }

  if (raw['meals'] is List) {
    final list = raw['meals'] as List;
    for (var i = 0; i < list.length; i++) {
      errs.addAll(_validateMeal(list[i], '第 ${i + 1} 条餐食'));
    }
  }
  if (raw['exercises'] is List) {
    final list = raw['exercises'] as List;
    for (var i = 0; i < list.length; i++) {
      errs.addAll(_validateExercise(list[i], '第 ${i + 1} 条运动'));
    }
  }
  return errs;
}

List<String> _validateDays(dynamic days, String no) {
  if (days == null) return [];
  if (days is num || days is String) {
    final n = _toNum(days);
    if (n != null && n == n.roundToDouble() && n >= 1 && n <= 7) return [];
    return ['$no 的 days 含非法值 $days（1=周一…7=周日）'];
  }
  if (days is! List) return ['$no 的 days 必须是数字数组（1=周一…7=周日）'];
  final bad = days.where((d) {
    final n = _toNum(d);
    return n == null || n != n.roundToDouble() || n < 1 || n > 7;
  }).toList();
  if (bad.isNotEmpty) return ['$no 的 days 含非法值 ${bad.join('、')}（1=周一…7=周日）'];
  return [];
}

List<String> _validateRange(dynamic sd, dynamic ed, String no) {
  final e = <String>[];
  final sdOk = sd == null || sd == '' || (sd is String && isValidDateStr(sd));
  final edOk = ed == null || ed == '' || (ed is String && isValidDateStr(ed));
  if (!sdOk) e.add('$no 的 startDate 格式错误，应为 YYYY-MM-DD');
  if (!edOk) e.add('$no 的 endDate 格式错误，应为 YYYY-MM-DD');
  if (sdOk && edOk && sd is String && ed is String && sd.isNotEmpty && ed.isNotEmpty && sd.compareTo(ed) > 0) {
    e.add('$no 日期范围无效：开始日期晚于结束日期');
  }
  return e;
}

List<String> _validateDates(dynamic dates, String no) {
  if (dates == null) return [];
  if (dates is String) {
    return isValidDateStr(dates) ? [] : ['$no 的 dates 日期格式错误，应为 YYYY-MM-DD'];
  }
  if (dates is! List) return ['$no 的 dates 必须是日期字符串数组（YYYY-MM-DD）'];
  final bad = dates.whereType<String>().where((d) => !isValidDateStr(d)).toList();
  if (bad.isNotEmpty) return ['$no 的 dates 含非法日期 ${bad.join('、')}，应为 YYYY-MM-DD'];
  return [];
}

List<String> _validateMeal(dynamic it, String no) {
  if (it is! Map) return ['$no 不是对象'];
  final e = <String>[];
  final name = it['name'];
  if (name is! String || name.isEmpty) e.add('$no 缺少 name（名称）');
  if (_normalizeTime(it['time']).isEmpty) {
    e.add('$no 时间格式错误（${it['time']}），应为 HH:mm 如 12:00');
  }
  if (_typeAlias[it['type']] == null) {
    e.add('$no 的 type 无效（${it['type']}）：只能是 breakfast/lunch/dinner/snack');
  }
  final cal = it['calories'];
  if (cal != null && cal != '') {
    final n = _toNum(cal);
    if (n == null || n < 0 || n > 5000) {
      e.add('$no 热量超出合理范围（0-5000 kcal），自由餐请填 null');
    }
  }
  e.addAll(_validateDays(it['days'], no));
  e.addAll(_validateDates(it['dates'], no));
  e.addAll(_validateRange(it['startDate'], it['endDate'], no));
  return e;
}

List<String> _validateExercise(dynamic it, String no) {
  if (it is! Map) return ['$no 不是对象'];
  final e = <String>[];
  final name = it['name'];
  if (name is! String || name.isEmpty) e.add('$no 缺少 name（名称）');
  if (_normalizeTime(it['time']).isEmpty) {
    e.add('$no 时间格式错误（${it['time']}），应为 HH:mm 如 18:30');
  }
  final dur = _toNum(it['duration']);
  final durMissing = it['duration'] == null || it['duration'] == '';
  if (durMissing || dur == null || dur <= 0 || dur > 600) {
    e.add('$no 的 duration（时长分钟）必须为 1-600 的数字');
  }
  final burn = it['caloriesBurned'];
  if (burn != null && burn != '') {
    final b = _toNum(burn);
    if (b == null || b < 0 || b > 5000) e.add('$no 的 caloriesBurned 超出合理范围（0-5000）');
  }
  e.addAll(_validateDays(it['days'], no));
  e.addAll(_validateDates(it['dates'], no));
  e.addAll(_validateRange(it['startDate'], it['endDate'], no));
  return e;
}

// ---------- 规范化（校验通过后调用）----------

String _str(dynamic v) => v is String ? v : '';
String _dateStr(dynamic v) => v is String && isValidDateStr(v) ? v : '';
double? _posNum(dynamic v) {
  final n = _toNum(v);
  return (n != null && n > 0) ? n.toDouble() : null;
}
double? _numOr(dynamic v, double? def) {
  final n = _toNum(v);
  return (n != null && n >= 0) ? n.toDouble() : def;
}

/// 规范化原始 JSON → PlanData（与 JS normalizePlan 语义一致）
PlanData normalizePlan(Map<String, dynamic> raw) {
  final meals = <MealItem>[];
  if (raw['meals'] is List) {
    for (final it in (raw['meals'] as List).whereType<Map>()) {
      final cal = it['calories'];
      final calValue = (cal == null || cal == '')
          ? null
          : (_numOr(cal, null)?.round());
      meals.add(MealItem(
        id: _str(it['id']).isNotEmpty ? _str(it['id']) : genId('m'),
        type: _typeAlias[it['type']] ?? 'lunch',
        name: _str(it['name']).isNotEmpty ? _str(it['name']) : '未命名',
        time: _normalizeTime(it['time']).isNotEmpty ? _normalizeTime(it['time']) : '12:00',
        calories: calValue,
        days: _daysArr(it['days']),
        reminder: it['reminder'] != false,
        note: _str(it['note']),
        details: (it['details'] is List)
            ? (it['details'] as List)
                .whereType<Map>()
                .map((d) => DetailItem(item: _str(d['item']), amount: _str(d['amount'])))
                .where((d) => d.item.isNotEmpty)
                .toList()
            : [],
        steps: (it['steps'] is List)
            ? (it['steps'] as List).map((s) => s.toString()).where((s) => s.isNotEmpty).toList()
            : [],
        dates: _datesArr(it['dates']),
        startDate: _dateStr(it['startDate']),
        endDate: _dateStr(it['endDate']),
      ));
    }
  }

  final exercises = <ExerciseItem>[];
  if (raw['exercises'] is List) {
    for (final it in (raw['exercises'] as List).whereType<Map>()) {
      final dur = _posNum(it['duration']);
      exercises.add(ExerciseItem(
        id: _str(it['id']).isNotEmpty ? _str(it['id']) : genId('e'),
        name: _str(it['name']).isNotEmpty ? _str(it['name']) : '未命名',
        time: _normalizeTime(it['time']).isNotEmpty ? _normalizeTime(it['time']) : '18:00',
        duration: (dur?.round() ?? 30),
        caloriesBurned: (_numOr(it['caloriesBurned'], 0)?.round() ?? 0),
        days: _daysArr(it['days']),
        dates: _datesArr(it['dates']),
        startDate: _dateStr(it['startDate']),
        endDate: _dateStr(it['endDate']),
        reminder: it['reminder'] != false,
        note: _str(it['note']),
        content: (it['content'] is List)
            ? (it['content'] as List)
                .whereType<Map>()
                .map((c) => ContentItem(
                      item: _str(c['item']),
                      detail: _str(c['detail']),
                      minutes: (_numOr(c['minutes'], 0)?.round() ?? 0),
                    ))
                .where((c) => c.item.isNotEmpty)
                .toList()
            : [],
      ));
    }
  }

  // 按 id 去重（保留首个）
  List<T> dedup<T, K>(List<T> list, K Function(T) key) {
    final seen = <K>{};
    final out = <T>[];
    for (final it in list) {
      if (seen.add(key(it))) out.add(it);
    }
    return out;
  }

  final meta = raw['meta'] is Map ? raw['meta'] as Map : <String, dynamic>{};
  return PlanData(
    version: '1.0',
    meta: PlanMeta(
      planName: _str(meta['planName']),
      startDate: _dateStr(meta['startDate']),
      endDate: _dateStr(meta['endDate']),
      baseWeight: _posNum(meta['baseWeight']),
      targetWeight: _posNum(meta['targetWeight']),
      dailyCalorieTarget: _posNum(meta['dailyCalorieTarget']),
      tdee: _posNum(meta['tdee']),
    ),
    meals: dedup(meals, (m) => m.id),
    exercises: dedup(exercises, (e) => e.id),
    deletedIds: [],
  );
}

// ---------- 当日任务 ----------

/// 当日任务集合
class TaskSet {
  final List<MealItem> meals;
  final List<ExerciseItem> exercises;
  const TaskSet({this.meals = const [], this.exercises = const []});
  int get total => meals.length + exercises.length;
}

/// 计划开始日（首次导入日）之前的日子视为「无计划」：不产生任务、不计完成度、不参与统计
TaskSet getTasksForDate(PlanData planData, String dateStr) {
  final startedAt = planData.meta.startedAt;
  if (startedAt.isNotEmpty && dateStr.compareTo(startedAt) < 0) {
    return const TaskSet();
  }
  final weekday = parseDate(dateStr).weekday;
  // 命中规则：填了 dates 仅按具体日期生效（days/范围忽略）；否则按 days 周几 + 日期范围
  bool hit(dynamic it) {
    final dates = it is MealItem ? it.dates : (it as ExerciseItem).dates;
    final startDate = it is MealItem ? it.startDate : (it as ExerciseItem).startDate;
    final endDate = it is MealItem ? it.endDate : (it as ExerciseItem).endDate;
    final days = it is MealItem ? it.days : (it as ExerciseItem).days;
    if (dates.isNotEmpty) return dates.contains(dateStr);
    final inRange = (startDate.isEmpty || dateStr.compareTo(startDate) >= 0) &&
        (endDate.isEmpty || dateStr.compareTo(endDate) <= 0);
    return inRange && (days.isEmpty || days.contains(weekday));
  }

  int byTime(String a, String b) => timeToMin(a) - timeToMin(b);

  final meals = planData.meals.where(hit).toList()
    ..sort((a, b) => byTime(a.time, b.time));
  final exercises = planData.exercises.where(hit).toList()
    ..sort((a, b) => byTime(a.time, b.time));
  return TaskSet(meals: meals, exercises: exercises);
}
