/// 体重记录模型（F10，存储键：weightRecords）
/// 设计依据：spec/weight-design.md v1.0
/// {
///   "baseline": { "base": 1814, "date": "2026-09-03" },
///   "records": { "2026-09-03": { "weight": 68.55, "bmr": 1512, "updatedAt": 1756857600000 } }
/// }
/// 语义：历史日期的基础消耗一旦成为事实就不再变化；只有从生效日起才应用新值。
///  - baseline：第一次「基础消耗口径即将变化」且已有历史记录时固化的基准（幂等）
///  - records：一天一条，录入时快照当时算出的 BMR（基础信息不全存 0，仅展示体重）
library;

import '../utils/date_utils.dart';

/// 单日体重记录
class WeightEntry {
  double weight; // kg，允许两位小数（如 68.55）
  int bmr; // 录入时按当时基础信息快照的 BMR；0 = 录入时基础信息不完整（不参与基础消耗）
  int updatedAt; // 毫秒时间戳
  double? bodyFat; // 体脂率（%），如 20.5，选填（体脂秤参考）

  WeightEntry({
    required this.weight,
    required this.bmr,
    required this.updatedAt,
    this.bodyFat,
  });

  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
        weight: json['weight'] is num ? (json['weight'] as num).toDouble() : 0,
        bmr: json['bmr'] is num ? (json['bmr'] as num).round() : 0,
        updatedAt: json['updatedAt'] is num ? (json['updatedAt'] as num).round() : 0,
        bodyFat: json['bodyFat'] is num ? (json['bodyFat'] as num).toDouble() : null,
      );

  Map<String, dynamic> toJson() => {
        'weight': weight,
        'bmr': bmr,
        'updatedAt': updatedAt,
        if (bodyFat != null) 'bodyFat': bodyFat,
      };
}

/// 基准固化（历史稳定锚点）
class WeightBaseline {
  int base; // 固化的基准基础消耗（kcal，口径 = 固化时的 baseBurn）
  String date; // 固化日 YYYY-MM-DD；严格早于该日的日期才使用 baseline
  WeightBaseline({required this.base, required this.date});

  factory WeightBaseline.fromJson(Map<String, dynamic> json) => WeightBaseline(
        base: json['base'] is num ? (json['base'] as num).round() : 0,
        date: json['date'] is String ? json['date'] as String : '',
      );

  Map<String, dynamic> toJson() => {'base': base, 'date': date};
}

/// 体重记录仓库
class WeightData {
  WeightBaseline? baseline;
  Map<String, WeightEntry> records; // { date: WeightEntry }

  WeightData({this.baseline, Map<String, WeightEntry>? records})
      : records = records ?? {};

  factory WeightData.empty() => WeightData();

  factory WeightData.fromJson(Map<String, dynamic> json) {
    final b = json['baseline'];
    Map<String, WeightEntry>? recs;
    if (json['records'] is Map) {
      recs = <String, WeightEntry>{};
      (json['records'] as Map).forEach((date, v) {
        if (v is Map) {
          recs![date.toString()] = WeightEntry.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    return WeightData(
      baseline: (b is Map)
          ? WeightBaseline.fromJson(Map<String, dynamic>.from(b))
          : null,
      records: recs,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseline': baseline?.toJson(),
        'records': records.map((d, e) => MapEntry(d, e.toJson())),
      };

  /// date ≤ [dateStr] 的最近一条记录（key 按字典序即时间序）
  WeightEntry? entryFor(String dateStr) {
    WeightEntry? hit;
    String? hitDate;
    for (final e in records.entries) {
      if (e.key.compareTo(dateStr) <= 0) {
        if (hitDate == null || e.key.compareTo(hitDate) > 0) {
          hitDate = e.key;
          hit = e.value;
        }
      }
    }
    return hit;
  }

  /// 查找 ≤ [dateStr] 的最近一条记录中的体脂率（沿用链：体脂秤并非每天测，优先取最近一次测量的有效值）
  double? bodyFatFor(String dateStr) {
    final sortedDates = records.keys.where((d) => d.compareTo(dateStr) <= 0).toList()
      ..sort((a, b) => b.compareTo(a));
    for (final d in sortedDates) {
      final bf = records[d]?.bodyFat;
      if (bf != null && bf > 0) return bf;
    }
    return null;
  }

  /// 今天（同日重复录入覆盖）
  WeightEntry? todayEntry() => records[todayStr()];
}
