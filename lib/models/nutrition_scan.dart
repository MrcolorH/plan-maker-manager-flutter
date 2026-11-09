/// 预包装食品营养成分表与配料表数据模型及精确换算逻辑
library;

/// 换算后的实际摄入营养成分清单
class CalculatedNutrition {
  /// 用户实际输入的摄入量（g 或 ml）
  final double intakeAmount;

  /// 单位（如 g 或 ml）
  final String unit;

  /// 换算系数 = intakeAmount / servingSize
  final double ratio;

  /// 实际摄入总热量 (kcal，四舍五入)
  final int calories;

  /// 实际摄入蛋白质 (g，保留1位小数)
  final double protein;

  /// 实际摄入脂肪 (g，保留1位小数)
  final double fat;

  /// 实际摄入碳水化合物 (g，保留1位小数)
  final double carbs;

  /// 实际摄入钠 (mg，四舍五入)
  final int sodium;

  /// 实际摄入膳食纤维 (g，可选)
  final double? fiber;

  /// 实际摄入糖 (g，可选)
  final double? sugar;

  /// 蛋白质供能比 (0.0 - 1.0)
  final double proteinRatio;

  /// 脂肪供能比 (0.0 - 1.0)
  final double fatRatio;

  /// 碳水供能比 (0.0 - 1.0)
  final double carbsRatio;

  const CalculatedNutrition({
    required this.intakeAmount,
    required this.unit,
    required this.ratio,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.sodium,
    this.fiber,
    this.sugar,
    required this.proteinRatio,
    required this.fatRatio,
    required this.carbsRatio,
  });
}

/// 包装食品营养成分与配料表识别结果
class FoodPackageScanResult {
  /// 食品名称（如：全麦吐司、脱脂纯牛奶、黑巧克力）
  final String foodName;

  /// 品牌或厂商（可选）
  final String brand;

  /// 标称基准份量数值（通常为 100，或如每份 30）
  final double servingSize;

  /// 标称基准单位（如 "g" 或 "ml"）
  final String servingUnit;

  /// 标称基准热量 (kcal)
  final double calories;

  /// 包装若标示千焦 (kJ)，记录原始数值供核对
  final double? energyKj;

  /// 标称基准蛋白质 (g)
  final double protein;

  /// 标称基准脂肪 (g)
  final double fat;

  /// 标称基准碳水化合物 (g)
  final double carbs;

  /// 标称基准钠 (mg)
  final double sodium;

  /// 标称基准膳食纤维 (g，可选)
  final double? fiber;

  /// 标称基准糖 (g，可选)
  final double? sugar;

  /// 配料表原文（如：全麦粉、生活饮用水、食用酵母...）
  final String ingredients;

  /// 减脂与健康分析提示标签（如：高蛋白、低脂、高钠需控量、含添加糖等）
  final List<String> healthTips;

  const FoodPackageScanResult({
    required this.foodName,
    this.brand = '',
    this.servingSize = 100.0,
    this.servingUnit = 'g',
    required this.calories,
    this.energyKj,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.sodium,
    this.fiber,
    this.sugar,
    this.ingredients = '',
    this.healthTips = const [],
  });

  /// 复制并更新部分字段（供用户在识别后手动微调基准值）
  FoodPackageScanResult copyWith({
    String? foodName,
    String? brand,
    double? servingSize,
    String? servingUnit,
    double? calories,
    double? energyKj,
    double? protein,
    double? fat,
    double? carbs,
    double? sodium,
    double? fiber,
    double? sugar,
    String? ingredients,
    List<String>? healthTips,
  }) {
    return FoodPackageScanResult(
      foodName: foodName ?? this.foodName,
      brand: brand ?? this.brand,
      servingSize: servingSize ?? this.servingSize,
      servingUnit: servingUnit ?? this.servingUnit,
      calories: calories ?? this.calories,
      energyKj: energyKj ?? this.energyKj,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
      sodium: sodium ?? this.sodium,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      ingredients: ingredients ?? this.ingredients,
      healthTips: healthTips ?? this.healthTips,
    );
  }

  /// 核心计算逻辑：输入用户摄入克数，等比例精确计算实际摄入营养清单
  CalculatedNutrition calculate(double intakeAmount) {
    final validBase = servingSize > 0 ? servingSize : 100.0;
    final ratio = intakeAmount / validBase;

    final actualCal = (calories * ratio).round();
    final actualP = _round1(protein * ratio);
    final actualF = _round1(fat * ratio);
    final actualC = _round1(carbs * ratio);
    final actualNa = (sodium * ratio).round();

    final actualFiber = fiber != null ? _round1(fiber! * ratio) : null;
    final actualSugar = sugar != null ? _round1(sugar! * ratio) : null;

    // 计算三大宏量供能比：P*4, C*4, F*9
    final calP = actualP * 4.0;
    final calC = actualC * 4.0;
    final calF = actualF * 9.0;
    final macroCalTotal = calP + calC + calF;

    double pRatio = 0.0;
    double cRatio = 0.0;
    double fRatio = 0.0;
    if (macroCalTotal > 0) {
      pRatio = calP / macroCalTotal;
      cRatio = calC / macroCalTotal;
      fRatio = calF / macroCalTotal;
    }

    return CalculatedNutrition(
      intakeAmount: intakeAmount,
      unit: servingUnit,
      ratio: ratio,
      calories: actualCal,
      protein: actualP,
      fat: actualF,
      carbs: actualC,
      sodium: actualNa,
      fiber: actualFiber,
      sugar: actualSugar,
      proteinRatio: pRatio,
      fatRatio: fRatio,
      carbsRatio: cRatio,
    );
  }

  static double _round1(double v) {
    return (v * 10).round() / 10.0;
  }

  /// 从 AI 返回的 JSON 解析
  factory FoodPackageScanResult.fromJson(Map<String, dynamic> json) {
    // 基础信息
    final name = (json['foodName'] ?? json['name'] ?? '袋装食品').toString().trim();
    final brand = (json['brand'] ?? '').toString().trim();
    final unit = (json['servingUnit'] ?? 'g').toString().trim();

    double sSize = 100.0;
    if (json['servingSize'] is num) {
      sSize = (json['servingSize'] as num).toDouble();
    } else if (json['servingSize'] != null) {
      sSize = double.tryParse(json['servingSize'].toString()) ?? 100.0;
    }

    // 热量与千焦转换：优先取 calories，若只有千焦 energyKj 则折算
    double cal = 0.0;
    double? kj;
    if (json['energyKj'] is num) {
      kj = (json['energyKj'] as num).toDouble();
    } else if (json['energyKj'] != null) {
      kj = double.tryParse(json['energyKj'].toString());
    }

    if (json['calories'] is num) {
      cal = (json['calories'] as num).toDouble();
    } else if (json['calories'] != null) {
      cal = double.tryParse(json['calories'].toString()) ?? 0.0;
    }

    // 若无 calories 但有千焦，中国标签换算 1 kcal = 4.184 kJ
    if (cal <= 0 && kj != null && kj > 0) {
      cal = _round1(kj / 4.184);
    } else if (cal > 0 && kj == null) {
      kj = _round1(cal * 4.184);
    }

    final p = _numToDouble(json['protein']);
    final f = _numToDouble(json['fat']);
    final c = _numToDouble(json['carbs'] ?? json['carbohydrate']);
    final na = _numToDouble(json['sodium']);
    final fiber = json['fiber'] != null ? _numToDouble(json['fiber']) : null;
    final sugar = json['sugar'] != null ? _numToDouble(json['sugar']) : null;

    final ing = (json['ingredients'] ?? '').toString().trim();

    final tips = <String>[];
    if (json['healthTips'] is List) {
      for (final t in json['healthTips'] as List) {
        if (t != null && t.toString().trim().isNotEmpty) {
          tips.add(t.toString().trim());
        }
      }
    }

    return FoodPackageScanResult(
      foodName: name.isNotEmpty ? name : '袋装食品',
      brand: brand,
      servingSize: sSize > 0 ? sSize : 100.0,
      servingUnit: unit.isNotEmpty ? unit : 'g',
      calories: cal,
      energyKj: kj,
      protein: p,
      fat: f,
      carbs: c,
      sodium: na,
      fiber: fiber,
      sugar: sugar,
      ingredients: ing,
      healthTips: tips,
    );
  }

  static double _numToDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v == null) return 0.0;
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Map<String, dynamic> toJson() => {
        'foodName': foodName,
        'brand': brand,
        'servingSize': servingSize,
        'servingUnit': servingUnit,
        'calories': calories,
        if (energyKj != null) 'energyKj': energyKj,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        'sodium': sodium,
        if (fiber != null) 'fiber': fiber,
        if (sugar != null) 'sugar': sugar,
        'ingredients': ingredients,
        'healthTips': healthTips,
      };

  /// 本地正则与文本智能兜底提取器：
  /// 用户手动输入/粘贴营养成分表文本（如从照片 OCR 复制或手敲文字），离线即时结构化提取
  static FoodPackageScanResult extractFromText(String text) {
    final clean = text.replaceAll('，', ',').replaceAll('：', ':');

    // 1. 基准份量提取（如：每100克、每100g、每份30g、每30ml）
    double serving = 100.0;
    String unit = 'g';
    final servingMatch = RegExp(r'每\s*(\d+(?:\.\d+)?)\s*(克|g|毫升|ml)', caseSensitive: false).firstMatch(clean);
    if (servingMatch != null) {
      serving = double.tryParse(servingMatch.group(1) ?? '') ?? 100.0;
      final u = (servingMatch.group(2) ?? '').toLowerCase();
      unit = (u == '毫升' || u == 'ml') ? 'ml' : 'g';
    }

    // 2. 能量/千焦/千卡提取
    double cal = 0.0;
    double? kj;
    final kjMatch = RegExp(r'(?:能量|热量)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:千焦|kj)', caseSensitive: false).firstMatch(clean);
    if (kjMatch != null) {
      kj = double.tryParse(kjMatch.group(1) ?? '');
      if (kj != null) {
        cal = _round1(kj / 4.184);
      }
    }

    final kcalMatch = RegExp(r'(?:能量|热量)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:千卡|kcal|大卡)', caseSensitive: false).firstMatch(clean);
    if (kcalMatch != null) {
      final parsedCal = double.tryParse(kcalMatch.group(1) ?? '');
      if (parsedCal != null && parsedCal > 0) {
        cal = parsedCal;
        kj ??= _round1(cal * 4.184);
      }
    }

    // 3. 蛋白质
    double protein = 0.0;
    final pMatch = RegExp(r'蛋白质\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:g|克)', caseSensitive: false).firstMatch(clean);
    if (pMatch != null) protein = double.tryParse(pMatch.group(1) ?? '') ?? 0.0;

    // 4. 脂肪
    double fat = 0.0;
    final fMatch = RegExp(r'脂肪\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:g|克)', caseSensitive: false).firstMatch(clean);
    if (fMatch != null) fat = double.tryParse(fMatch.group(1) ?? '') ?? 0.0;

    // 5. 碳水化合物
    double carbs = 0.0;
    final cMatch = RegExp(r'碳水(?:化合物)?\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:g|克)', caseSensitive: false).firstMatch(clean);
    if (cMatch != null) carbs = double.tryParse(cMatch.group(1) ?? '') ?? 0.0;

    // 6. 钠
    double sodium = 0.0;
    final naMatch = RegExp(r'钠\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:mg|毫克)', caseSensitive: false).firstMatch(clean);
    if (naMatch != null) sodium = double.tryParse(naMatch.group(1) ?? '') ?? 0.0;

    // 7. 膳食纤维 & 糖
    double? fiber;
    final fiberMatch = RegExp(r'膳食纤维\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:g|克)', caseSensitive: false).firstMatch(clean);
    if (fiberMatch != null) fiber = double.tryParse(fiberMatch.group(1) ?? '');

    double? sugar;
    final sugarMatch = RegExp(r'糖\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:g|克)', caseSensitive: false).firstMatch(clean);
    if (sugarMatch != null) sugar = double.tryParse(sugarMatch.group(1) ?? '');

    // 8. 配料表识别（如：配料：... 或 配料表：...）
    String ing = '';
    final ingMatch = RegExp(r'配料(?:表)?\s*[:：]\s*([^\n\r]+)').firstMatch(text);
    if (ingMatch != null) {
      ing = (ingMatch.group(1) ?? '').trim();
    }

    // 9. 本地智能健康洞察生成
    final tips = <String>[];
    if (fat <= 3.0 && serving == 100.0) tips.add('🟢 低脂健康');
    if (fat >= 20.0 && serving == 100.0) tips.add('🔴 脂肪含量较高，建议控量');
    if (protein >= 10.0 && serving == 100.0) tips.add('🟢 高蛋白补充');
    if (sodium >= 600.0 && serving == 100.0) tips.add('🟡 高钠注意防浮肿');
    if (ing.contains('白砂糖') || ing.contains('果葡糖浆') || (sugar != null && sugar > 10.0)) {
      tips.add('🟡 含有添加糖');
    }
    if (ing.contains('氢化植物油') || ing.contains('植脂末') || ing.contains('代可可脂') || ing.contains('起酥油')) {
      tips.add('🔴 含有氢化油脂/人造脂肪');
    }

    return FoodPackageScanResult(
      foodName: '袋装食品',
      servingSize: serving,
      servingUnit: unit,
      calories: cal,
      energyKj: kj,
      protein: protein,
      fat: fat,
      carbs: carbs,
      sodium: sodium,
      fiber: fiber,
      sugar: sugar,
      ingredients: ing,
      healthTips: tips,
    );
  }
}
