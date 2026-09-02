/// 内置食物热量库（离线兜底；数值为公开资料估算值，展示时带 ≈）
/// 结构与旧版 food-db.js 完全一致
library;

class FoodItem {
  final String id;
  final String name;
  final List<String> alias;
  final int calories;
  final String unit;
  final List<String> tags;

  const FoodItem({
    required this.id,
    required this.name,
    this.alias = const [],
    required this.calories,
    required this.unit,
    this.tags = const [],
  });
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
  FoodItem(id: 'kfcset-01', name: '香辣鸡腿堡套餐（堡+中薯+中可乐）', alias: ['kfc', '肯德基', '套餐', '香辣鸡腿堡'], calories: 1100, unit: '1份', tags: ['kfc', '套餐']),
  FoodItem(id: 'kfcset-02', name: '新奥尔良烤鸡腿堡套餐（堡+中薯+中可乐）', alias: ['kfc', '肯德基', '套餐', '烤鸡腿堡'], calories: 1010, unit: '1份', tags: ['kfc', '套餐']),
  FoodItem(id: 'kfcset-03', name: '劲脆鸡腿堡套餐（堡+中薯+中可乐）', alias: ['kfc', '肯德基', '套餐', '劲脆'], calories: 1100, unit: '1份', tags: ['kfc', '套餐']),
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
List<FoodItem> searchFoods(String kw) {
  final k = kw.trim().toLowerCase();
  if (k.isEmpty) return [];
  final result = kFoodDb.where((f) {
    final hay = '${f.name} ${f.alias.join(' ')} ${f.tags.join(' ')}'.toLowerCase();
    return hay.contains(k);
  }).toList();
  return result.length > 20 ? result.sublist(0, 20) : result;
}
