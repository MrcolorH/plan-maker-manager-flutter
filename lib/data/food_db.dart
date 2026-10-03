/// 内置食物热量库（离线兜底；数值为公开资料估算值，展示时带 ≈）
/// 结构与旧版 food-db.js 完全一致
library;

import '../models/records.dart';

class FoodItem {
  final String id;
  final String name;
  final List<String> alias;
  final int calories;
  final String unit;
  final List<String> tags;
  final int? protein;
  final int? carbs;
  final int? fat;
  final bool isUserCustom;

  const FoodItem({
    required this.id,
    required this.name,
    this.alias = const [],
    required this.calories,
    required this.unit,
    this.tags = const [],
    this.protein,
    this.carbs,
    this.fat,
    this.isUserCustom = false,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      id: json['id'] is String ? json['id'] as String : '',
      name: json['name'] is String ? json['name'] as String : '',
      alias: (json['alias'] as List?)?.map((e) => '$e').toList() ?? const [],
      calories: json['calories'] is num ? (json['calories'] as num).round() : 0,
      unit: json['unit'] is String && (json['unit'] as String).isNotEmpty ? json['unit'] as String : '1份',
      tags: (json['tags'] as List?)?.map((e) => '$e').toList() ?? const [],
      protein: json['protein'] is num ? (json['protein'] as num).round() : null,
      carbs: json['carbs'] is num ? (json['carbs'] as num).round() : null,
      fat: json['fat'] is num ? (json['fat'] as num).round() : null,
      isUserCustom: json['isUserCustom'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'alias': alias,
        'calories': calories,
        'unit': unit,
        'tags': tags,
        if (protein != null) 'protein': protein,
        if (carbs != null) 'carbs': carbs,
        if (fat != null) 'fat': fat,
        'isUserCustom': isUserCustom,
      };
}

/// 食物库匹配与份量换算结果
class FoodMatchResult {
  final FoodItem food;
  final double quantity; // 份量倍数，如 0.5, 2.0
  final String quantityText; // 份量描述，如 "0.5个", "2个", "200g"
  final int totalCalories;
  final int? totalProtein;
  final int? totalCarbs;
  final int? totalFat;
  final String calculationDetail; // 如 "590 kcal/1个 × 0.5个 = 295 kcal"
  final bool isUserCustom;
  final List<FoodBreakdownItem> breakdownItems;

  FoodMatchResult({
    required this.food,
    required this.quantity,
    required this.quantityText,
    required this.totalCalories,
    this.totalProtein,
    this.totalCarbs,
    this.totalFat,
    required this.calculationDetail,
    required this.isUserCustom,
    List<FoodBreakdownItem>? breakdownItems,
  }) : breakdownItems = breakdownItems ??
            [
              FoodBreakdownItem(
                name: food.name,
                portion: quantityText,
                calories: totalCalories,
              ),
            ];
}

const List<FoodItem> kFoodDb = [
  // ---- KFC 单品 ----
  FoodItem(id: 'kfc-01', name: '香辣鸡腿堡', alias: ['kfc', '肯德基', '汉堡'], calories: 590, unit: '1个', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-02', name: '新奥尔良烤鸡腿堡', alias: ['kfc', '肯德基', '烤堡'], calories: 500, unit: '1个', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-03', name: '劲脆鸡腿堡', alias: ['kfc', '肯德基'], calories: 590, unit: '1个', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-04', name: '吮指原味鸡', alias: ['kfc', '肯德基', '炸鸡'], calories: 240, unit: '1块', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-05', name: '黄金鸡块', alias: ['kfc', '肯德基', '鸡块'], calories: 270, unit: '5块', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-06', name: '香辣鸡翅', alias: ['kfc', '肯德基', '鸡翅'], calories: 180, unit: '2块', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-07', name: '薯条', alias: ['kfc', '肯德基', '薯条'], calories: 330, unit: '中份', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-08', name: '葡式蛋挞', alias: ['kfc', '肯德基', '蛋挞'], calories: 290, unit: '1个', tags: ['kfc', '甜品']),
  FoodItem(id: 'kfc-09', name: '老北京鸡肉卷', alias: ['kfc', '肯德基', '鸡肉卷'], calories: 490, unit: '1个', tags: ['kfc', '快餐']),
  FoodItem(id: 'kfc-10', name: '可乐', alias: ['kfc', '肯德基', '可口可乐'], calories: 180, unit: '中杯', tags: ['kfc', '饮品']),
  FoodItem(id: 'kfc-11', name: '九珍果汁饮料', alias: ['kfc', '肯德基', '果汁'], calories: 160, unit: '中杯', tags: ['kfc', '饮品']),
  FoodItem(id: 'kfc-12', name: 'K咖啡拿铁', alias: ['kfc', '肯德基', '拿铁'], calories: 230, unit: '大杯', tags: ['kfc', '饮品']),
  // ---- KFC 套餐 ----
  FoodItem(id: 'kfcset-01', name: '香辣鸡腿堡套餐（堡+中薯+中可乐）', alias: ['kfc', '肯德基', '套餐', '汉堡套餐'], calories: 1100, unit: '1份', tags: ['kfc', '套餐']),
  FoodItem(id: 'kfcset-02', name: '新奥尔良烤鸡腿堡套餐（堡+中薯+中可乐）', alias: ['kfc', '肯德基', '套餐', '烤堡套餐'], calories: 1010, unit: '1份', tags: ['kfc', '套餐']),
  FoodItem(id: 'kfcset-03', name: '劲脆鸡腿堡套餐（堡+中薯+中可乐）', alias: ['kfc', '肯德基', '套餐', '劲脆套餐'], calories: 1100, unit: '1份', tags: ['kfc', '套餐']),
  FoodItem(id: 'kfcset-04', name: '疯狂星期四（2个香辣鸡腿堡）', alias: ['kfc', '肯德基', '疯狂星期四', 'v50'], calories: 1180, unit: '2个', tags: ['kfc', '套餐']),
  // ---- 麦当劳 ----
  FoodItem(id: 'mcd-01', name: '巨无霸', alias: ['麦当劳', 'm', '汉堡'], calories: 550, unit: '1个', tags: ['麦当劳', '快餐']),
  FoodItem(id: 'mcd-02', name: '麦辣鸡腿堡', alias: ['麦当劳', 'm', '汉堡'], calories: 570, unit: '1个', tags: ['麦当劳', '快餐']),
  FoodItem(id: 'mcd-03', name: '双层吉士堡', alias: ['麦当劳', 'm'], calories: 460, unit: '1个', tags: ['麦当劳', '快餐']),
  FoodItem(id: 'mcd-04', name: '麦乐鸡', alias: ['麦当劳', 'm', '鸡块'], calories: 250, unit: '6块', tags: ['麦当劳', '快餐']),
  FoodItem(id: 'mcd-05', name: '麦辣鸡翅', alias: ['麦当劳', 'm', '鸡翅'], calories: 240, unit: '2块', tags: ['麦当劳', '快餐']),
  FoodItem(id: 'mcd-06', name: '薯条', alias: ['麦当劳', 'm', '薯条'], calories: 330, unit: '中份', tags: ['麦当劳', '快餐']),
  FoodItem(id: 'mcd-07', name: '圆筒冰淇淋', alias: ['麦当劳', 'm', '甜筒'], calories: 200, unit: '1个', tags: ['麦当劳', '甜品']),
  FoodItem(id: 'mcd-08', name: '麦辣鸡腿堡套餐（堡+中薯+中可乐）', alias: ['麦当劳', 'm', '套餐'], calories: 1100, unit: '1份', tags: ['麦当劳', '套餐']),
  // ---- 汉堡王 / 华莱士 等 ----
  FoodItem(id: 'bk-01', name: '汉堡王皇堡', alias: ['汉堡王', 'bk', '皇堡'], calories: 660, unit: '1个', tags: ['汉堡王', '快餐']),
  FoodItem(id: 'bk-02', name: '汉堡王狠霸王牛堡', alias: ['汉堡王', 'bk'], calories: 750, unit: '1个', tags: ['汉堡王', '快餐']),
  FoodItem(id: 'hls-01', name: '华莱士香辣鸡腿堡', alias: ['华莱士', '汉堡'], calories: 480, unit: '1个', tags: ['华莱士', '快餐']),
  // ---- 常见外卖主食 ----
  FoodItem(id: 'takeout-01', name: '黄焖鸡米饭', alias: ['外卖', '黄焖鸡'], calories: 750, unit: '大份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-02', name: '黄焖鸡米饭（小份）', alias: ['外卖', '黄焖鸡'], calories: 600, unit: '小份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-03', name: '麻辣烫（一碗）', alias: ['外卖', '麻辣烫'], calories: 700, unit: '1碗', tags: ['外卖']),
  FoodItem(id: 'takeout-04', name: '蛋炒饭', alias: ['外卖', '炒饭'], calories: 700, unit: '1份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-05', name: '扬州炒饭', alias: ['外卖', '炒饭'], calories: 720, unit: '1份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-06', name: '炒河粉', alias: ['外卖', '河粉', '干炒牛河'], calories: 750, unit: '1份', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-07', name: '炒面', alias: ['外卖', '面条'], calories: 700, unit: '1份', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-08', name: '螺蛳粉', alias: ['外卖', '螺蛳粉'], calories: 750, unit: '1份', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-09', name: '桂林米粉', alias: ['外卖', '米粉'], calories: 620, unit: '1份', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-10', name: '兰州牛肉面', alias: ['外卖', '拉面', '牛肉面'], calories: 650, unit: '1碗', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-11', name: '重庆小面', alias: ['外卖', '小面'], calories: 600, unit: '1碗', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-12', name: '沙县拌面+炖罐', alias: ['外卖', '沙县'], calories: 600, unit: '1套', tags: ['外卖']),
  FoodItem(id: 'takeout-13', name: '隆江猪脚饭', alias: ['外卖', '猪脚饭'], calories: 850, unit: '1份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-14', name: '烧腊双拼饭', alias: ['外卖', '烧腊', '叉烧饭'], calories: 800, unit: '1份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-15', name: '麻辣香锅（1人份）', alias: ['外卖', '香锅'], calories: 900, unit: '1份', tags: ['外卖']),
  FoodItem(id: 'takeout-16', name: '炸酱面', alias: ['外卖', '面条'], calories: 650, unit: '1碗', tags: ['外卖', '粉面']),
  FoodItem(id: 'takeout-17', name: '水饺（猪肉白菜）', alias: ['外卖', '饺子'], calories: 550, unit: '15个', tags: ['外卖']),
  FoodItem(id: 'takeout-18', name: '披萨', alias: ['外卖', 'pizza', '披萨'], calories: 280, unit: '1块(9寸/8块)', tags: ['外卖', '西餐']),
  FoodItem(id: 'takeout-19', name: '台式卤肉饭', alias: ['外卖', '卤肉饭'], calories: 700, unit: '1份', tags: ['外卖', '米食']),
  FoodItem(id: 'takeout-20', name: '梅菜扣肉饭', alias: ['外卖', '扣肉'], calories: 780, unit: '1份', tags: ['外卖', '米食']),
  // ---- 轻食 ----
  FoodItem(id: 'light-01', name: '鸡胸肉沙拉', alias: ['轻食', '沙拉'], calories: 350, unit: '1份', tags: ['轻食']),
  FoodItem(id: 'light-02', name: '金枪鱼三明治', alias: ['轻食', '三明治'], calories: 350, unit: '1个', tags: ['轻食']),
  FoodItem(id: 'light-03', name: '牛肉谷物碗', alias: ['轻食', '谷物碗'], calories: 500, unit: '1份', tags: ['轻食']),
  FoodItem(id: 'light-04', name: '关东煮', alias: ['关东煮', '便利店'], calories: 300, unit: '6串', tags: ['轻食']),
  FoodItem(id: 'light-05', name: '饭团', alias: ['便利店', '饭团'], calories: 350, unit: '1个', tags: ['轻食']),
  FoodItem(id: 'light-06', name: '三明治（便利店）', alias: ['便利店', '三明治'], calories: 300, unit: '1个', tags: ['轻食']),
  // ---- 饮品 ----
  FoodItem(id: 'drink-01', name: '珍珠奶茶（全糖大杯）', alias: ['奶茶', '珍珠奶茶', 'boba'], calories: 450, unit: '大杯', tags: ['饮品']),
  FoodItem(id: 'drink-02', name: '珍珠奶茶（三分糖大杯）', alias: ['奶茶', '珍珠奶茶'], calories: 320, unit: '大杯', tags: ['饮品']),
  FoodItem(id: 'drink-03', name: '美式咖啡', alias: ['咖啡', '美式', '美式咖啡'], calories: 10, unit: '大杯', tags: ['饮品']),
  FoodItem(id: 'drink-04', name: '拿铁', alias: ['咖啡', '拿铁'], calories: 230, unit: '大杯', tags: ['饮品']),
  FoodItem(id: 'drink-05', name: '生椰拿铁', alias: ['咖啡', '生椰拿铁'], calories: 280, unit: '大杯', tags: ['饮品']),
  FoodItem(id: 'drink-06', name: '可乐', alias: ['可乐', '可口可乐', '百事'], calories: 140, unit: '330ml', tags: ['饮品']),
  FoodItem(id: 'drink-07', name: '橙汁', alias: ['果汁', '橙汁'], calories: 200, unit: '500ml', tags: ['饮品']),
  FoodItem(id: 'drink-08', name: '啤酒', alias: ['啤酒', '酒'], calories: 150, unit: '1瓶500ml', tags: ['饮品']),
  FoodItem(id: 'drink-09', name: '果茶', alias: ['果茶', '水果茶'], calories: 250, unit: '大杯', tags: ['饮品']),
  // ---- 零食甜点 ----
  FoodItem(id: 'snack-01', name: '薯片', alias: ['零食', '薯片', '乐事'], calories: 550, unit: '1包104g', tags: ['零食']),
  FoodItem(id: 'snack-02', name: '巧克力', alias: ['零食', '巧克力', '德芙'], calories: 550, unit: '1板43g', tags: ['零食']),
  FoodItem(id: 'snack-03', name: '蛋糕（奶油切片）', alias: ['甜品', '蛋糕'], calories: 350, unit: '1块', tags: ['零食', '甜品']),
  FoodItem(id: 'snack-04', name: '冰淇淋', alias: ['甜品', '冰淇淋', '雪糕'], calories: 250, unit: '1个', tags: ['零食', '甜品']),
  FoodItem(id: 'snack-05', name: '饼干', alias: ['零食', '饼干'], calories: 120, unit: '3块', tags: ['零食']),
  FoodItem(id: 'snack-06', name: '辣条', alias: ['零食', '辣条'], calories: 300, unit: '1包', tags: ['零食']),
  FoodItem(id: 'snack-07', name: '坚果', alias: ['零食', '坚果', '每日坚果'], calories: 160, unit: '1小袋25g', tags: ['零食']),
  // ---- 通用参照 ----
  FoodItem(id: 'common-01', name: '白米饭', alias: ['米饭', '白饭'], calories: 230, unit: '1碗200g', tags: ['通用']),
  FoodItem(id: 'common-02', name: '水煮蛋', alias: ['鸡蛋', '水煮蛋', '煮鸡蛋'], calories: 70, unit: '1个', tags: ['通用']),
  FoodItem(id: 'common-03', name: '茶叶蛋', alias: ['鸡蛋', '茶叶蛋'], calories: 80, unit: '1个', tags: ['通用']),
  FoodItem(id: 'common-04', name: '纯牛奶', alias: ['牛奶', '纯牛奶'], calories: 160, unit: '250ml', tags: ['通用']),
  FoodItem(id: 'common-05', name: '无糖酸奶', alias: ['酸奶'], calories: 120, unit: '1杯135g', tags: ['通用']),
  FoodItem(id: 'common-06', name: '全麦面包', alias: ['面包', '全麦'], calories: 240, unit: '2片', tags: ['通用']),
  FoodItem(id: 'common-07', name: '包子（猪肉）', alias: ['包子', '馒头'], calories: 250, unit: '1个', tags: ['通用']),
  FoodItem(id: 'common-08', name: '玉米', alias: ['玉米', '苞谷'], calories: 110, unit: '1根', tags: ['通用']),
  FoodItem(id: 'common-09', name: '红薯', alias: ['红薯', '地瓜'], calories: 200, unit: '1个中等', tags: ['通用']),
  FoodItem(id: 'common-10', name: '香蕉', alias: ['水果', '香蕉'], calories: 90, unit: '1根', tags: ['通用']),
  FoodItem(id: 'common-11', name: '苹果', alias: ['水果', '苹果'], calories: 85, unit: '1个', tags: ['通用']),
  FoodItem(id: 'common-12', name: '黑咖啡', alias: ['咖啡', '黑咖啡'], calories: 5, unit: '1杯', tags: ['通用']),
];

/// 搜索：名称/别名/标签 不区分大小写包含匹配，返回前 20 条
List<FoodItem> searchFoods(String kw, {List<FoodItem>? userFoods}) {
  final k = kw.trim().toLowerCase();
  if (k.isEmpty) return const [];
  final candidates = <FoodItem>[...(userFoods ?? const <FoodItem>[]), ...kFoodDb];
  final result = candidates.where((f) {
    final hay = '${f.name} ${f.alias.join(' ')} ${f.tags.join(' ')}'.toLowerCase();
    return hay.contains(k);
  }).toList();
  return result.length > 20 ? result.sublist(0, 20) : result;
}

final _stopAndUnitPattern = RegExp(
  r'('
  r'\d+(?:\.\d+)?\s*/\s*\d+|\d+(?:\.\d+)?|'
  r'[个块份碗杯串片包根瓶盒袋条只盘两勺克gml毫升kg千克斤]|'
  r'小碗|大碗|中碗|小份|大份|中份|小杯|大杯|中杯|'
  r'[一二两俩三四五六七八九十半整满多份几]|分之|'
  r'大约|大概|约|左右|来|点|有些|有一点|吃了|吃|喝了|喝|尝了|尝|要了|点了|一份|一个|一小|一大|的|了|在|'
  r'[\s,，、+~—·.。/()（）\[\]【】\-_:：]'
  r')',
  caseSensitive: false,
);

/// 智能解析输入文本并在食物库中匹配与折算热量
///
/// 规则：
/// 1. 若输入包含多种食物（如通过逗号、顿号、加号、换行或空格分隔）：
///    - 若拆分出的每一项均能在食物库中精确命中，则合并求和返回完整组合结果，不遗漏任何食物；
///    - 若有任何一项未在食物库收录，绝不截断输出部分食物，直接返回 null 交由 AI 大模型全量估算！
/// 2. 若输入为单项描述，严格校验文本纯粹性，避免把包含多个食物或复杂烹饪的长句误当单品截断。
FoodMatchResult? matchAndCalculateFood(String input, {List<FoodItem>? userFoods}) {
  final raw = input.trim();
  if (raw.isEmpty) return null;

  // 1. 合并用户库与内置库，用户自建库在前
  final customList = userFoods ?? const [];
  final candidates = <FoodItem>[...customList, ...kFoodDb];
  // 长词优先，避免如“新奥尔良烤鸡腿堡”先被“鸡腿堡”截断
  candidates.sort((a, b) => b.name.length.compareTo(a.name.length));

  // 2. 检查多食物强分隔符：逗号、顿号、加号、分号、换行、或独立的连接词（和/还有/加上/以及）
  final delimiterPattern = RegExp(r'[\n\r，,、+；;]|(?:\s+(?:还有|加上|以及|和)\s+)|(?:\s*还有\s*)|(?:\s*加上\s*)');
  if (delimiterPattern.hasMatch(raw)) {
    final parts = raw.split(delimiterPattern).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      final results = <FoodMatchResult>[];
      for (final p in parts) {
        final m = _matchSingleFood(p, candidates);
        if (m == null) {
          // 只要有任何一项未能单品精准命中（如包含未收录食物、复杂家常菜等），
          // 绝不能截断输出部分食物！必须返回 null 交给 AI 大模型全量综合估算！
          return null;
        }
        results.add(m);
      }
      return _combineMatchResults(results);
    }
  }

  // 3. 检查是否有空格分隔的多项（如 "200g白米饭 2个水煮蛋"）
  if (raw.contains(' ')) {
    final spaceParts = raw.split(RegExp(r'\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (spaceParts.length >= 2) {
      final results = <FoodMatchResult>[];
      bool allMatched = true;
      for (final p in spaceParts) {
        final m = _matchSingleFood(p, candidates);
        if (m == null) {
          allMatched = false;
          break;
        }
        results.add(m);
      }
      if (allMatched && results.length >= 2) {
        return _combineMatchResults(results);
      }
    }
  }

  // 4. 单项匹配（严格校验，避免把包含多食物的长句误当单品）
  return _matchSingleFood(raw, candidates);
}

/// 匹配单项食物
FoodMatchResult? _matchSingleFood(String input, List<FoodItem> candidates) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  final lower = raw.toLowerCase();

  FoodItem? matchedFood;
  String matchedKey = '';

  // 第一轮：直接按食物名称包含匹配（长词优先）
  for (final item in candidates) {
    final itemName = item.name.toLowerCase();
    if (lower.contains(itemName)) {
      matchedFood = item;
      matchedKey = item.name;
      break;
    }
  }

  // 第二轮：按别名包含匹配
  if (matchedFood == null) {
    for (final item in candidates) {
      for (final al in item.alias) {
        final alLower = al.toLowerCase();
        if (alLower.length >= 2 && lower.contains(alLower)) {
          matchedFood = item;
          matchedKey = al;
          break;
        }
      }
      if (matchedFood != null) break;
    }
  }

  if (matchedFood == null) return null;

  // 提取剩余修饰文本（仅替换首次命中的关键词，避免重复替换）
  final keyIndex = raw.toLowerCase().indexOf(matchedKey.toLowerCase());
  if (keyIndex < 0) return null;
  final remainder = ('${raw.substring(0, keyIndex)} ${raw.substring(keyIndex + matchedKey.length)}').trim();

  // 关键校验：检查 remainder 中是否还残留未被解释的实质性字词
  // 若残留文字包含其他食物或复杂描述，说明该片段不是单纯的单食物描述，不可盲目截断
  final leftover = remainder.replaceAll(_stopAndUnitPattern, '').trim();
  if (leftover.isNotEmpty) {
    return null;
  }

  final parsed = _parseQuantity(remainder.toLowerCase(), matchedFood.unit);
  final quantity = parsed.$1;
  final quantityText = parsed.$2;

  final totalCal = (matchedFood.calories * quantity).round();
  final totalP = matchedFood.protein != null ? (matchedFood.protein! * quantity).round() : null;
  final totalC = matchedFood.carbs != null ? (matchedFood.carbs! * quantity).round() : null;
  final totalF = matchedFood.fat != null ? (matchedFood.fat! * quantity).round() : null;

  final String detail;
  if ((quantity - 1.0).abs() < 0.001) {
    detail = '${matchedFood.calories} kcal / ${matchedFood.unit}';
  } else {
    detail = '${matchedFood.calories} kcal/${matchedFood.unit} × $quantityText = $totalCal kcal';
  }

  return FoodMatchResult(
    food: matchedFood,
    quantity: quantity,
    quantityText: quantityText,
    totalCalories: totalCal,
    totalProtein: totalP,
    totalCarbs: totalC,
    totalFat: totalF,
    calculationDetail: detail,
    isUserCustom: matchedFood.isUserCustom,
  );
}

/// 合并多个食物的匹配结果
FoodMatchResult _combineMatchResults(List<FoodMatchResult> results) {
  if (results.length == 1) return results.first;

  int totalCal = 0;
  int totalP = 0;
  bool hasP = false;
  int totalC = 0;
  bool hasC = false;
  int totalF = 0;
  bool hasF = false;
  bool isUserCustom = false;

  final names = <String>[];
  final units = <String>[];
  final details = <String>[];

  for (final r in results) {
    totalCal += r.totalCalories;
    if (r.totalProtein != null) {
      totalP += r.totalProtein!;
      hasP = true;
    }
    if (r.totalCarbs != null) {
      totalC += r.totalCarbs!;
      hasC = true;
    }
    if (r.totalFat != null) {
      totalF += r.totalFat!;
      hasF = true;
    }
    if (r.isUserCustom) isUserCustom = true;

    names.add(r.food.name);
    units.add('${r.food.name}×${r.quantityText}');
    details.add('${r.food.name}(${r.quantityText}, ${r.totalCalories}kcal)');
  }

  final combinedName = names.join(' + ');
  final combinedUnit = units.join('，');
  final detail = '${details.join(' + ')} = $totalCal kcal';

  final combinedFood = FoodItem(
    id: 'combo_${DateTime.now().millisecondsSinceEpoch}',
    name: combinedName,
    calories: totalCal,
    unit: combinedUnit,
    protein: hasP ? totalP : null,
    carbs: hasC ? totalC : null,
    fat: hasF ? totalF : null,
    isUserCustom: isUserCustom,
  );

  return FoodMatchResult(
    food: combinedFood,
    quantity: 1.0,
    quantityText: combinedUnit,
    totalCalories: totalCal,
    totalProtein: hasP ? totalP : null,
    totalCarbs: hasC ? totalC : null,
    totalFat: hasF ? totalF : null,
    calculationDetail: detail,
    isUserCustom: isUserCustom,
    breakdownItems: results
        .map((r) => FoodBreakdownItem(
              name: r.food.name,
              portion: r.quantityText,
              calories: r.totalCalories,
            ))
        .toList(),
  );
}

/// 解析份量修饰词，返回 (倍数, 份量展示文本)
(double, String) _parseQuantity(String text, String baseUnit) {
  final cleanBaseUnit = baseUnit.replaceFirst(RegExp(r'^\d+'), '');
  final defaultUnitText = cleanBaseUnit.isNotEmpty ? cleanBaseUnit : '份';

  if (text.isEmpty) {
    return (1.0, '1$defaultUnitText');
  }

  // 常见分数：如 1/4, 1/3, 1/2, 3/4 等
  final fracMatch = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(text);
  if (fracMatch != null) {
    final num1 = double.tryParse(fracMatch.group(1) ?? '');
    final num2 = double.tryParse(fracMatch.group(2) ?? '');
    if (num1 != null && num2 != null && num2 > 0) {
      final ratio = num1 / num2;
      final rawFrac = fracMatch.group(0)!.replaceAll(' ', '');
      return (ratio, '$rawFrac$defaultUnitText');
    }
  }
  if (text.contains('四分之一')) return (0.25, '1/4$defaultUnitText');
  if (text.contains('三分之一')) return (0.33, '1/3$defaultUnitText');
  if (text.contains('二分之一')) return (0.5, '0.5$defaultUnitText');
  if (text.contains('四分之三')) return (0.75, '3/4$defaultUnitText');
  if (text.contains('三分之二')) return (0.67, '2/3$defaultUnitText');

  // 常见中文半份
  if (text.contains('半个') ||
      text.contains('半份') ||
      text.contains('半碗') ||
      text.contains('半块') ||
      text.contains('半杯') ||
      text.contains('半包') ||
      text.contains('半根') ||
      text.contains('半条') ||
      text.contains('半瓶') ||
      text.contains('半盘') ||
      text.contains('一半') ||
      text == '半') {
    return (0.5, '0.5$defaultUnitText');
  }

  // 中文两/俩
  if (text.contains('两个') ||
      text.contains('两块') ||
      text.contains('两碗') ||
      text.contains('两份') ||
      text.contains('两杯') ||
      text.contains('两瓶') ||
      text.contains('两根') ||
      text.contains('两包') ||
      text.contains('两盘') ||
      text.contains('两只')) {
    return (2.0, '2$defaultUnitText');
  }

  // 大份 / 小份
  if (text.contains('大份') || text.contains('大碗') || text.contains('加大') || text.contains('大杯')) {
    if (baseUnit.contains('大')) return (1.0, '1$defaultUnitText');
    return (1.3, '大份');
  }
  if (text.contains('小份') || text.contains('小碗') || text.contains('小杯')) {
    if (baseUnit.contains('小')) return (1.0, '1$defaultUnitText');
    return (0.7, '小份');
  }

  // 克重：如 200g, 150克
  final gMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:g|克)').firstMatch(text);
  if (gMatch != null) {
    final g = double.tryParse(gMatch.group(1) ?? '') ?? 100.0;
    final baseGMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:g|克)').firstMatch(baseUnit);
    final baseG = baseGMatch != null ? (double.tryParse(baseGMatch.group(1) ?? '') ?? 100.0) : 100.0;
    final ratio = g / (baseG > 0 ? baseG : 100.0);
    return (ratio, '${g.round()}g');
  }

  // 毫升：如 500ml, 330毫升
  final mlMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|毫升)').firstMatch(text);
  if (mlMatch != null) {
    final ml = double.tryParse(mlMatch.group(1) ?? '') ?? 250.0;
    final baseMlMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|毫升)').firstMatch(baseUnit);
    final baseMl = baseMlMatch != null ? (double.tryParse(baseMlMatch.group(1) ?? '') ?? 250.0) : 250.0;
    final ratio = ml / (baseMl > 0 ? baseMl : 250.0);
    return (ratio, '${ml.round()}ml');
  }

  // 数字 + 单位 或纯数字：如 "2个", "1.5份", "3", "0.5"
  final numMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(?:个|块|份|碗|杯|串|片|包|根|瓶|盒|袋|条|只)?').firstMatch(text);
  if (numMatch != null) {
    final n = double.tryParse(numMatch.group(1) ?? '');
    if (n != null && n > 0 && n <= 50) {
      final disp = (n % 1 == 0) ? '${n.toInt()}' : '$n';
      return (n, '$disp$defaultUnitText');
    }
  }

  // 中文数字
  const cnNums = {'一': 1.0, '二': 2.0, '三': 3.0, '四': 4.0, '五': 5.0, '六': 6.0};
  for (final entry in cnNums.entries) {
    if (text.contains(entry.key)) {
      return (entry.value, '${entry.value.toInt()}$defaultUnitText');
    }
  }

  return (1.0, '1$defaultUnitText');
}

/// 从用户记录或常用方案中反推归一化单位食物，沉淀到自定义食物库
FoodItem extractUnitFood({
  required String name,
  required int calories,
  int? protein,
  int? carbs,
  int? fat,
  String? unit,
}) {
  final trimmed = name.trim();
  var cleanName = trimmed;
  var ratio = 1.0;
  var resolvedUnit = (unit != null && unit.isNotEmpty) ? unit : '1份';

  if (trimmed.startsWith('半个') || trimmed.endsWith('半个')) {
    ratio = 0.5;
    resolvedUnit = '1个';
    cleanName = trimmed.replaceAll('半个', '').trim();
  } else if (trimmed.startsWith('半份') || trimmed.endsWith('半份') || trimmed.startsWith('一半')) {
    ratio = 0.5;
    resolvedUnit = '1份';
    cleanName = trimmed.replaceAll(RegExp(r'半份|一半'), '').trim();
  } else {
    // 检查是否有前置或后置数字
    final headMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*(个|块|份|碗|杯|串|片|包|根|瓶|盒|袋|条|只)?').firstMatch(trimmed);
    if (headMatch != null) {
      final n = double.tryParse(headMatch.group(1) ?? '');
      final u = headMatch.group(2);
      if (n != null && n > 0 && n <= 50) {
        ratio = n;
        if (u != null && u.isNotEmpty) resolvedUnit = '1$u';
        cleanName = trimmed.substring(headMatch.end).trim();
      }
    } else {
      final tailMatch = RegExp(r'(\d+(?:\.\d+)?)\s*(个|块|份|碗|杯|串|片|包|根|瓶|盒|袋|条|只)?$').firstMatch(trimmed);
      if (tailMatch != null) {
        final n = double.tryParse(tailMatch.group(1) ?? '');
        final u = tailMatch.group(2);
        if (n != null && n > 0 && n <= 50) {
          ratio = n;
          if (u != null && u.isNotEmpty) resolvedUnit = '1$u';
          cleanName = trimmed.substring(0, tailMatch.start).trim();
        }
      }
    }
  }

  if (cleanName.isEmpty) cleanName = trimmed;

  // 基础单位热量与营养素 = 总量 / ratio
  final baseCal = ratio > 0 ? (calories / ratio).round() : calories;
  final baseP = (protein != null && ratio > 0) ? (protein / ratio).round() : protein;
  final baseC = (carbs != null && ratio > 0) ? (carbs / ratio).round() : carbs;
  final baseF = (fat != null && ratio > 0) ? (fat / ratio).round() : fat;

  final id = 'user_${cleanName.hashCode.abs()}';

  return FoodItem(
    id: id,
    name: cleanName,
    alias: [cleanName],
    calories: baseCal,
    unit: resolvedUnit,
    tags: ['自定义'],
    protein: baseP,
    carbs: baseC,
    fat: baseF,
    isUserCustom: true,
  );
}
