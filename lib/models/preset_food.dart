/// 常用预设方案与 AI 知识缓存模型
library;

class PresetFood {
  final String id;
  final String name;
  final int calories;
  final int? protein; // 蛋白质 (g)
  final int? carbs;   // 碳水 (g)
  final int? fat;     // 脂肪 (g)
  final String note;
  final int useCount; // 使用频次，用于推荐排序
  final int updatedAt;

  const PresetFood({
    required this.id,
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.note = '',
    this.useCount = 1,
    required this.updatedAt,
  });

  factory PresetFood.fromJson(Map<String, dynamic> json) {
    return PresetFood(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      calories: json['calories'] is num ? (json['calories'] as num).round() : 0,
      protein: json['protein'] is num ? (json['protein'] as num).round() : null,
      carbs: json['carbs'] is num ? (json['carbs'] as num).round() : null,
      fat: json['fat'] is num ? (json['fat'] as num).round() : null,
      note: json['note'] is String ? json['note'] as String : '',
      useCount: json['useCount'] is num ? (json['useCount'] as num).round() : 1,
      updatedAt: json['updatedAt'] is num ? (json['updatedAt'] as num).round() : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        if (protein != null) 'protein': protein,
        if (carbs != null) 'carbs': carbs,
        if (fat != null) 'fat': fat,
        'note': note,
        'useCount': useCount,
        'updatedAt': updatedAt,
      };

  PresetFood copyWith({
    String? name,
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    String? note,
    int? useCount,
    int? updatedAt,
  }) {
    return PresetFood(
      id: id,
      name: name ?? this.name,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      note: note ?? this.note,
      useCount: useCount ?? this.useCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
