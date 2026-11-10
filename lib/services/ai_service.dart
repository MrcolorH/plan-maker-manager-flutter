/// AI 服务（OpenAI 兼容）：计划文档转 JSON / 食物热量查询 / 运动消耗估算 / 余额查询
/// 与旧版 ai.js 逻辑对齐，HTTP 层改用 dio
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../data/templates.dart';
import '../models/nutrition_scan.dart';
import '../models/onboarding.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../utils/date_utils.dart';

const String kNutritionScanSys = '''你是中国营养学会注册营养师与预包装食品标签（GB 28050）分析专家。
用户提供了一张食品包装袋照片（营养成分表/配料表）或相关文字。
请严格按国家标准与食品营养学进行精准识别与分析：

【核心解析规则】
1. 食品与品牌识别：
   - foodName: 食品准确名称（如“全麦黑麦吐司”、“原味苏打饼干”、“无糖纯酸奶”）；
   - brand: 品牌（若可见，如“达利园”、“三只松鼠”等，若不确定可留空）。
2. 营养成分表基准份量识别（关键）：
   - servingSize: 标称的基准分量数字（如标签写“每100克”则填 100；“每份30g”则填 30）；
   - servingUnit: 单位（"g" 或 "ml"，默认为 "g"）。
3. 营养素含量提取与千焦/千卡转换（铁律）：
   - 中国食品包装上能量大多标示为「千焦 (kJ)」。必须同时提取 energyKj，并将其精确换算为「千卡 (kcal)」：kcal = kJ / 4.184（四舍五入或保留一位小数）！若标签直接标示了 kcal，则以标示的 kcal 为准；
   - 蛋白质 protein: 克数 (g)；
   - 脂肪 fat: 克数 (g)；
   - 碳水化合物 carbs: 克数 (g)；
   - 钠 sodium: 毫克数 (mg)；
   - 膳食纤维 fiber: 克数 (g，若标示，否则 null)；
   - 糖 sugar: 克数 (g，若标示，否则 null)。
4. 配料表识别 (ingredients)：
   - 完整提取配料表文字（按包装排布顺序，如“全麦粉、生活饮用水、食用盐、酵母”）。
5. 减脂与健康深度洞察 (healthTips，提供 2-4 条精炼标签)：
   - 油脂品质：是否含反式脂肪酸、是否使用氢化植物油/人造奶油/植脂末/起酥油；
   - 糖分评估：配料表前三位是否有添加糖（白砂糖、果葡糖浆、麦芽糖等），是否有代糖；
   - 减脂友好度：是否低脂（脂肪<=3g/100g）、高蛋白（蛋白质>=12g/100g）、高纤；
   - 钠含量预警：是否高钠（钠>=600mg/100g，提醒控盐防浮肿）。

严格只返回一个 JSON 对象，不要输出任何其他文字或 markdown 代码块：
{
  "foodName": "食品名称",
  "brand": "品牌名",
  "servingSize": 100,
  "servingUnit": "g",
  "calories": 标称热量数字kcal,
  "energyKj": 标称千焦数字kJ,
  "protein": 蛋白质数字g,
  "fat": 脂肪数字g,
  "carbs": 碳水数字g,
  "sodium": 钠数字mg,
  "fiber": 纤维数字g或null,
  "sugar": 糖数字g或null,
  "ingredients": "完整配料表文本",
  "healthTips": ["🟢 低脂健康", "🟢 高蛋白质", "🟡 含有添加糖", "🔴 脂肪偏高注意控量"]
}
''';

const String kCalorieSys = '''你是中国营养学会专业营养师。用户描述一份食物或饮品（可能是单品、多食物组合，或复制自其他 AI 助手/聊天记录/外卖订单的长文本），请科学精确估算总热量及三大营养素。

【核心估算规则】
1. 【语义理解、抗噪与剔除明显非清单数据项（核心铁律）】：
   - 用户输入的文本可能包含大量非食物干扰信息，例如：复制自其他 AI 助手（如“萌萌”等）的问候寒暄（“收到，这就把菜品总重重新缩放...”）、交互式结语（“如无误请回复确认”、“👉 请核对以上识别是否有误”）、中间缩放计算与说明（“原先菜品总重是285g...缩放系数约为0.737”）、汇总统计（“菜品总重：210g”、“整餐总重：410g”、“蛋白质总量”等）以及宏量评价等；
   - 必须基于语义理解，精准识别并仅提取真正的食物/菜品/食材及其份量与热量数据；
   - 坚决剔除任何客套寒暄、对话问答、中间计算折算说明、总计小结及宏量汇总等非食物描述；
   - items 数组中的每一项必须是具体合法的食物食材名，严禁输出空白名称、纯数字名称、标点符号、或计算过程项；
   - detail 字段只保留纯净的食物分项拆解与最终合计（格式如：“白米饭200g≈232，清炒西兰花48g≈26，...，合计506”），严禁在 detail 中输出纯数字算式累加过程（如“26+33+55+31+59+70=506”）、问候语或任何非食物文字！
2. 多食物完整合并：若输入包含多种食物（如「米饭+鸡蛋+鸡腿+炒茄子」或「一碗米饭，半盘炒菜」），必须全面识别所有食材并累加合并总热量与三大营养素，绝不能只计算某一项而遗漏其他！
3. 真实家常烹饪用油常识（严禁机械盲目加油）：
   - 普通家常炒菜（整盘生重约250-350g）：中国家庭常态整盘放油约8-12g（约一平汤匙；清淡小炒仅5-8g底油滑锅；吸油蔬菜如家常炒茄子、干煸豆角整盘放油约12-15g）。装盘出锅后，盘底与菜汤会残留20%-35%余油不被摄入；
   - 餐厅外卖/重油滑炒：整份油量约12-18g；只有明确油炸时才考虑18g以上；
   - 水煮/清蒸/凉拌/白灼：用油按0-3g计算。
4. 【烹饪与复热油脂损耗 / 扣减规则（必查）】：
   - 当用户描述「空气炸锅逼出油/油脂」「沥油」「吸油纸吸油」「去皮」「滤出油」「倒掉余油」「吃肉不吃皮」或明确指出「损耗/减去/扣除X克油」等明确未食用的油脂损耗时，必须精准计算损耗并从总热量与总脂肪中扣除！
   - 扣除常识：纯油脂每 1g 约含 9 kcal 热量与 1g 纯脂肪（如逼出 3g 油 ≈ 扣减 27 kcal 热量与 3g 脂肪；逼出 5g 油 ≈ 扣减 45 kcal 与 5g 脂肪）；
   - 计算规则：实际总热量 = 食物基准总热量 - 逼出/损耗油脂热量（总脂肪也等量扣减，严禁只加不减）；
   - 拆解要求：在 items 拆解明细中单独列出一项负热量损耗扣减项（如 {"name":"空气炸锅逼出油(损耗扣减)","portion":"3g","calories":-27}），在 detail 文本中明确写出扣减过程；
   - 若用户单独录入损耗（如仅输入「空气炸锅逼出3克油」或「扣除3克油」），请直接输出负值热量（calories: -27, fat: -3），作为热量扣减项！
5. 多人共食与分摊比例折算（关键铁律）：
   - 当用户描述与家人共吃、按比例食用（如「1/4盘炒菜」「半盘」「吃了几口」「尝了一点」）时，所有成分（主料、配料、实际摄入油量、总脂肪及各营养素）必须严格等比例折算！
   - 典型示例：整盘家常炒茄子整盘摄入油约10-12g，若用户吃 1/4 盘，则实际摄入油量仅约 2.5-3g（脂肪约2.5-3g，折合22-27kcal），茄子本身约15kcal，1/4盘总热量仅约40-45kcal！
   - 严禁违背常识：绝对不可直接给「1/4盘炒菜」算8-15g油（否则倒推整盘高达32-60g纯油，相当于油炸或浸油，严重脱离家常事实）！
6. 严格遵循能量守恒：总热量 ≈ 蛋白质*4 + 碳水*4 + 脂肪*9。肉类按熟重计算。
7. 【总计数值绝对一致（严禁前后矛盾）】：
   calories 字段数值必须与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！detail 内部各项数值相加之和也必须严格等于该合计，绝对不允许 detail 里的合计与 calories 字段出现任何偏差！

严格只返回一个 JSON 对象，不要输出任何其他文字或 markdown 代码块：
{"name":"规范食物名或损耗扣减名（多食物时概括如：米饭配炒菜）","calories":总热量整数kcal(损耗扣减可为负数),"protein":蛋白质克数整数g,"carbs":碳水克数整数g,"fat":脂肪克数整数g,"unit":"份量描述（如：1人份、1碗+1盘等）","items":[{"name":"食物名","portion":"估算重量或份量","calories":该项热量整数}],"detail":"过程详解与分项拆解，如：米饭100g≈116，炒茄子1/4盘(含油约2.5g)≈45，合计161；或：汉堡2个≈900，空气炸锅逼出油3g≈-27，合计873","confidence":0到1}
描述模糊时 confidence 给低值。''';

const String kMealEstSys = '''你是减脂临床营养与食物成分分析专家。用户会描述这一餐实际吃了什么（可能是完整菜名、食材用量，或是复制自其他 AI 助手/聊天记录/外卖订单的长文描述，带备注）。
请按中国常见食物热量与烹饪常识精确估算。
规则：
1. 【语义理解、抗噪与剔除明显非清单数据项（核心铁律）】：
   - 用户输入的文本可能包含大量非食物干扰信息，例如：复制自其他 AI 助手（如“萌萌”等）的问候寒暄（“收到，萌萌这就把菜品总重重新缩放...”）、交互式结语（“如无误请回复确认”、“👉 请核对以上识别是否有误”）、中间缩放计算与折算过程说明（“原先菜品总重是285g...缩放系数约为0.737”）、汇总统计小结（“菜品总重：210g”、“整餐总重：410g”、“蛋白质总量”、“脂肪总量”等）以及营养素分析评价等；
   - 必须基于语义理解，精准识别并仅提取真正的食物/菜品/食材清单（如“白米饭”、“清炒西兰花”、“炒蒜苔”等）及其重量与热量；
   - 坚决剔除任何客套寒暄、对话问答、中间计算折算说明、总计小结及宏量汇总等非食物描述；
   - items 数组中的每一个条目的 name 必须是具体有效的食物食材名称，严禁为空白、纯数字、标点符号、或计算过程项；
   - detail 字段只保留纯净的食物分项拆解与最终合计（格式如：“白米饭200g≈232，清炒西兰花48g≈26，...，合计506”），严禁在 detail 中输出纯数字算式累加过程（如“26+33+55+31+59+70=506”）、问候语或任何非食物文字！
2. 真实烹饪用油与分食折算：
   - 普通家常炒菜一整盘（250-350g）整盘用油约8-12g（清淡小炒5-8g，吸油菜如炒茄子整盘约12-15g），盘底残留余油不吃；外卖重油菜整份约12-18g；凉拌水煮清蒸少油或无油（0-3g）；
   - 若多人共食或按比例分吃（如吃 1/4 盘、半盘、吃了几口），食材用量与摄入油量必须严格等比例缩减！例如 1/4 盘家常炒茄子摄入油量仅约 2.5-3g，严禁将单人整份底油直接套给 1/4 盘（否则倒推整盘高达32g油，脱离常识）；
3. 【烹饪与复热油脂损耗 / 扣减规则（必查）】：
   - 当用户描述「空气炸锅逼出油/油脂」「沥油」「吸油纸吸油」「去皮」「滤出油」「倒掉余油」「吃肉不吃皮」或明确指出「损耗/减去/扣除X克油」等明确未食用的油脂损耗时，必须精准计算损耗并从总热量与总脂肪中扣除！
   - 扣除常识：纯油脂每 1g 约含 9 kcal 热量与 1g 纯脂肪（如逼出 3g 油 ≈ 扣减 27 kcal 热量与 3g 脂肪；逼出 5g 油 ≈ 扣减 45 kcal 与 5g 脂肪）；
   - 计算规则：实际总热量 = 食物原本总热量 - 逼出/损耗油脂热量（总脂肪也等量扣减，严禁只加不减）；
   - 拆解要求：在 items 拆解明细数组中单独列出一项损耗扣减项（热量为负整数），例如：{"name": "空气炸锅逼出油脂(损耗扣减)", "portion": "3g", "calories": -27}；在 detail 文本中明确写出扣减过程，如：汉堡2个≈900，空气炸锅逼出油3g≈-27，合计873；
   - 若用户单独录入损耗（如仅输入「空气炸锅逼出3克油」或「扣除3克油」），请直接输出负值热量（calories: -27, fat: -3），作为热量扣减项！
4. 多食物与复合描述必须全面合并计算，不漏掉任何一项食材；
5. 严格核验能量守恒：总热量必须约等于 (蛋白质*4 + 碳水*4 + 脂肪*9)；
6. 【总计数值绝对一致（严禁前后矛盾）】：
   calories 字段数值必须与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！detail 内部各项数值相加之和也必须严格等于该合计，绝对不允许 detail 里的合计与 calories 字段出现任何偏差！
7. 【拆分成分明细列表】：
   识别出该餐实际包含的所有主要食物/食材（如米饭、去皮鸡肉、青椒、烹调用油、空气炸锅逼出油脂等），输出在 items 数组中，每项包含：
   - name: 食物/食材名称（如"米饭"、"鸡胸肉"、"空气炸锅逼出油脂(损耗扣减)"）
   - portion: 估算重量或份量描述（如"150g"、"半盘"、"3g"）
   - calories: 该项预估热量整数（kcal，损耗扣减项为负数）
8. 严格只返回一个 JSON 对象，不要输出任何其他文字或代码块：
{"calories":实际总热量整数kcal(损耗扣减可为负数),"protein":蛋白质整数g,"carbs":碳水整数g,"fat":脂肪整数g,"items":[{"name":"食物名","portion":"估算重量或份量","calories":该项热量整数}],"detail":"一句话分项拆解，如：米饭100g≈116，炒茄子1/4盘(含油约2.5g)≈45，合计161；或：汉堡2个≈900，空气炸锅逼出油3g≈-27，合计873"}
描述模糊时按常规份量估算。''';

/// FR6.9：计划条目编辑器专用——输入是结构化食材清单（含用量）+ 做法步骤，非口语描述
const String kItemCalSys = '''你是减脂计划餐食的热量与宏量营养素估算助手。用户给出一份计划餐食的结构化描述：餐名、食材清单（含用量）、做法步骤、备注。
请按中国常见食物热量成分，对食材清单逐项按给出的用量估算；做法步骤中提到的烹饪用油/糖/酱料等隐藏热量必须计入；未标注用量的食材按常见份量估算。
【烹饪用油常识】普通家常炒菜整盘用油约8-12g（清淡小炒5-8g，吸油菜12-15g）；若为分食（如吃几分之几盘）油量必须按比例等比缩减。
【油脂损耗扣减】若做法或备注中提到空气炸锅逼油、滤油、倒掉浮油等，按 1g 油 = 9 kcal 与 1g 脂肪从总热量和总脂肪中等量扣除。
严格遵循营养守恒：总热量 ≈ 蛋白质*4 + 碳水*4 + 脂肪*9。
【总计数值绝对一致】：calories 字段数值必须与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"calories":整餐总热量整数kcal,"protein":蛋白质整数g,"carbs":碳水整数g,"fat":脂肪整数g,"detail":"一句话拆解，如：鸡胸肉150g≈200(P45g)，橄榄油5g≈45，米饭150g≈175，合计420"}
备注中提到的替代/增减（如"不放糖"）以备注为准。''';

const String kBurnEstSys = '''你是运动消耗估算与运动生理学专家。用户会描述一次实际做的运动（可能是一个或多个运动项目 + 时长/距离/组数/强度，可能带备注或复制自聊天记录）。
请结合用户的基础资料（性别/年龄/身高/体重，若提供）按运动强度（MET 参照）科学估算各项及总消耗；未提供体重时按 65kg 成人估算。
规则：
1. 【语义理解与抗噪】：若输入包含寒暄客套或非运动描述，基于语义精准识别并剔除无关项，仅保留真实发生的运动项目。
2. 【拆分子项目清单】：
   将用户本次做的所有具体运动项目拆解列出在 items 数组中，每项包含：
   - name: 运动项目名称（如"室外慢跑"、"哑铃弯举"、"跳绳"、"静态拉伸"）
   - portion: 时长、距离、组数或次数（如"30分钟"、"4组共40次"、"500个"、"3公里"）
   - calories: 该子项预估消耗热量整数（kcal）
   若用户只做了一项运动，items 数组也包含该单项。
3. 【总计数值绝对一致（严禁前后矛盾）】：
   calories 字段数值必须与 items 中所有子项 calories 之和严格相等，且与 detail 拆解文本结尾的「合计 XXX」数值 100% 完全相同！
4. 严格只返回一个 JSON 对象，不要输出任何其他文字或代码块：
{"name":"运动概述名称（如：慢跑与拉伸）","calories":总消耗整数kcal,"items":[{"name":"运动项目名","portion":"时长/运动量","calories":该项消耗整数}],"detail":"一句话分项拆解，如：慢跑30分钟≈220，静态拉伸10分钟≈30，合计250"}
描述模糊时按常规强度估算。''';

const String kGuidePlanSys = '''你是减脂计划生成助手。用户会描述想吃的餐食和想做的运动（可能是一整段大白话，也可能是逐条列表），请把它生成为结构化计划 JSON。

只输出一个 JSON 对象，不要输出任何解释文字，不要 markdown 代码块围栏。

JSON 结构：
{
  "version": "1.0",
  "meta": { "planName": "我的减脂计划", "dailyCalorieTarget": 每日目标摄入kcal数字 },
  "meals": [
    { "type": "breakfast/lunch/dinner/snack四选一", "name": "餐名", "time": "HH:mm", "calories": 热量kcal数字或null, "days": [1,2,3], "note": "" }
  ],
  "exercises": [
    { "name": "训练名", "time": "HH:mm", "duration": 总分钟数字, "caloriesBurned": 消耗kcal数字, "days": [1,3,5], "note": "" }
  ]
}

生成规则：
1. 按用户描述拆分条目：早/午/晚/加餐分别一条；计划外运动放 exercises。不遗漏用户提到的任何内容，也不要凭空添加用户没提的条目
2. days 用数字表示星期几：1=周一 … 7=周日；「每天」或未提及 = [1,2,3,4,5,6,7]；「周一到周五」= [1,2,3,4,5]
3. 用户已给出的时间/热量/星期等信息必须原样保留；未给出的按常识补全：早餐07:30、午餐12:00、加餐16:00、晚餐18:00、运动18:30
4. 热量/消耗按中国常见食物与运动强度估算，给合理整数；用户明确说热量不固定（如自由餐/作弊餐）calories 填 null
5. 用户提供了体重时，运动消耗按该体重估算
6. name 用简洁中文（20字内）；meta.dailyCalorieTarget 填用户给定的目标摄入，未给定则省略''';

const String kWeeklyAdviceSys = '''你是资深注册营养师与专业运动减脂教练。
用户会提供他在减脂 App 中统计好的过去 7 天真实减脂数据（包含体重体脂变化、每日摄入/消耗/热量缺口、三大营养素实际克数与供能比、打卡与运动情况）。

【你的核心任务】
仅针对所提供的客观数据进行定性分析与指导。绝对不要做繁杂的数据重算，把重点放在减脂成效复盘、饮食结构优缺点、以及未来一周切实可执行的微习惯调整建议上。

严格只返回一个 JSON 对象，不要输出任何额外的问候、寒暄或 markdown 围栏标记：
{
  "headline": "一句话核心评价（15字内，如：执行稳健，减脂节奏良好 / 需重点提升蛋白质饱腹感）",
  "review": "本周点评（120~220字，客观复盘掉秤速度、热量缺口达成度、三大营养素合理性与生活运动配合，指明主要优点与具体短板）",
  "suggestions": [
    "第1条下周落地建议（具体到下一周的三餐或摄入微调，如：早餐增加1个水煮蛋，将日均蛋白质补足至75g）",
    "第2条下周落地建议（针对饮食控油、烹饪方式或某一餐的改进建议）",
    "第3条下周落地建议（针对运动频次、非运动消耗NEAT或热量预算的微调建议）"
  ],
  "encouragement": "教练寄语（40~80字，结合平台期与减脂心态给予真诚、科学的鼓励）"
}''';

const String kDailyVerifySys = '''你是资深临床营养学专家与减脂指导教练。
用户会提供他在减脂 App 中记录的今日饮食与运动记录（包含原始输入和系统估算/拆解结果）。

【核心原则与校验标准（极其重要，必须严格遵守）】
1. **加法总和与计算准确性（严禁心算臆造错误）**：
   - 清单中提供的「各餐条目估算总热量」、「拆解明细各分项」以及「全天汇总总热量」均由系统底层代码精确加总求和，在数学上 100% 绝对一致，绝无累加计算错误！
   - **绝对严禁**凭大模型自身心算臆造“拆解明细之和与估算总热量不符”、“全天总和算错”等虚假错误！
   - 宏量营养素与热量换算允许合理修约（中国食物成分表因膳食纤维、蛋白质热量换算折算系数等因素，与理论值存在正常工程浮动），**严禁**仅仅因为 4P+4C+9F 与总热量有微小出入就判定为计算错误！

2. **严谨审慎，拒绝微小扰动的无效纠偏（15% / 80 kcal 容差原则）**：
   - 家常与外卖餐食天然存在热量浮动。若原系统估算与你的理论值差异在 **±15% 以内（或绝对差值 ≤ 80 kcal）**，属于合理可信范围，**必须判定为 "准确"，严禁标记为 "偏差"！**
   - **严禁为了体现存在感而随意做 10~30 kcal 的无意义微调**（如 680 改为 670、320 改为 310），这属于不严谨的误报扰民。
   - **只有发生以下实质性重大错误时，才判定为 "偏差"**：
     ① 食材严重误判/漏判：如原始输入为“油炸鸡排”，系统识别成了“水煮鸡胸肉”；或严重漏算了重油红油、高糖饮品、芝麻酱沙拉酱等高热量关键配料；
     ② 份量数量级偏离：如输入“大份牛肉面”，系统按“100g 挂面”估算；
     ③ 运动强度或消耗估算严重脱离常识（如散步半小时估算消耗 500 kcal）。

3. **准确条目的数值保护原则**：
   - 凡判定为 "准确" 的条目，其 `corrected_calories`、`corrected_protein`、`corrected_carbs`、`corrected_fat` **必须 100% 保持原估算数值，绝对不要改动任何一个数字**，`issue` 填空字符串 `""`。
   - 只有判定为 "偏差" 的条目，才给出切实有据的修正值，并在 `issue` 中清晰指出偏差根源（如：“外卖水煮牛肉实为重油重盐烹饪，原估算低估了红油热量”）。

4. **整体结论（overall）的客观严谨**：
   - 若所有条目均判定为准确（无实质性偏差），`overall` 必须为 `"准确"`，`summary` 给出正面客观肯定（如：“今日饮食记录与热量估算合理严谨，宏量营养素配比均衡”）。
   - 仅在存在真正的食材误判或热量严重失真时，`overall` 才为 `"存在偏差"`。

【返回格式要求】
严格只返回一个标准的 JSON 对象，不要附加任何开场白、客套话或 markdown 说明文本：
{
  "overall": "准确" 或 "存在偏差",
  "summary": "一句话整体评价结论（先给结论，再讲主要偏差集中在哪；若准确请给予正面肯定）",
  "items": [
    {
      "content": "这里必须100%一字不差复制对应的【原始输入】文本，以便系统自动匹配对应",
      "status": "准确" 或 "偏差",
      "issue": "问题说明（准确留空；偏差才填写说明，如：外卖黄焖鸡用油较重，且实际肉量较多，热量低估约150kcal）",
      "corrected_calories": 修正后的热量整数kcal（准确条目必须完全保留原值）,
      "corrected_protein": 修正后的蛋白质整数g（准确条目必须完全保留原值，运动条目可为null或省略）,
      "corrected_carbs": 修正后的碳水整数g（准确条目必须完全保留原值，运动条目可为null或省略）,
      "corrected_fat": 修正后的脂肪整数g（准确条目必须完全保留原值，运动条目可为null或省略）
    }
  ]
}''';

const String kMealRecommendationSys = '''你是兼具中国居民膳食指南常识与临床减脂营养学的资深营养师与生活方式教练。
用户会提供当前的实际时间（小时:分钟）、今日已打卡/已摄入的餐饮和宏量营养素、已记录的运动消耗、基础日常消耗以及目标热量缺口要求。
你的职责是：结合当前时间点，合理预留至少 400 kcal 的每日总热量缺口，并为今天接下来的餐次（如午餐、下午茶、晚餐等）提供兼顾饱腹感与营养平衡的具体饮食建议与轻量运动调节建议。

【核心原则】
1. 【保底热量缺口红线】：
   - 全天必须严格保留至少 400 kcal 的健康减脂缺口（即：全天总消耗 - 全天总摄入 >= 400）。
   - 剩余可用总摄入上限 = 基础日常消耗 + 实际运动消耗 - 今日已摄入 - 保底缺口(400)。
   - 若剩余可用热量充裕（如 >600 kcal），合理分配到后续正餐与下午茶；若剩余可用热量吃紧（如 <300 kcal），推荐饱腹低卡轻食，并提出轻度运动建议以拓展可用额度。
2. 【结合当前时钟时间智能规划】：
   - 上午时段（06:00 - 11:30）：进行全天剩余规划，包含午餐、下午茶（可选）、晚餐；
   - 中午时段（11:30 - 14:00）：重点推荐午餐即食方案，并附带晚餐额度预留建议；
   - 下午茶时段（14:00 - 17:00）：重点推荐下午防暴食低卡加餐（约 80-150 kcal），并规划晚餐；
   - 晚餐时段（17:00 - 20:30）：重点推荐晚餐，以查漏补缺为主（如补充不足的蛋白质与膳食纤维）；
   - 晚间夜宵时段（20:30 以后）：若饥饿，提供 50-100 kcal 纯饱腹轻卡应急方案（如无糖酸奶/黄瓜/气泡水）。
3. 【具象实操，拒绝空洞说教】：
   - 每个时段给出 2-3 种切实可行的场景方案（如外卖便选、便利店快手、自烹家常），必须写清具体的食物组合（如「赛百味香烤鸡胸三明治(无酱)+冰美式」或「7-11即食鸡胸肉+小烤红薯」）。
   - 标明预估热量、蛋白质(g)、碳水(g)、脂肪(g)与一句话推荐理由。
4. 【用户餐饮倾向与现有食材定制优先级（最高原则）】：
   - 当用户指定就餐倾向为「自己做」，且提供了「手里现有的食材」时：
     * 必须优先围绕用户手里现有的食材设计减脂餐！在 name 或 reason 中明确指出如何搭配这几样食材，并给出极简少油少盐的做法要点（如："现有鸡蛋+西红柿：5g油微波温炒西红柿炒蛋，配主食"）；
     * scene 字段标注为「自烹家常 (优先已有食材)」；
     * 严禁无视用户输入而推荐用户没有的生僻材料；
   - 当用户指定「点外卖」时：方案全面偏向主流外卖品牌与品类，并附带避油避酱的备注小贴士；
   - 当用户指定「去店里吃」时：方案偏向常见连锁餐饮堂食选菜或便利店即食组合；
5. 【运动平衡建议（非强制，仅作为弹性调节）】：
   - 若用户剩余热量充足，可提示维持日常或做轻度拉伸；
   - 若用户剩余可用热量偏少或运动量为 0，可建议 15-30 分钟轻运动（如快走、跳绳、爬楼梯，预计多消耗 100-150 kcal），让晚餐更从容。
5. 【纯建议属性】：语气专业、温和、鼓励，强调“这只是弹性建议，请依个人饱腹感灵活调整”。

【严格格式要求】：
请只输出一个 JSON 对象，严禁包含任何多余文字或解释：
{
  "summary": "一句话核心点评与预算概况（如：今日还剩560kcal可用摄入，已锁定400kcal保底缺口，建议中午补充高蛋白优质碳水）",
  "remainingCalorieBudget": 剩余可用热量整数kcal,
  "macroFocus": "宏量营养素查漏侧重（如：需重点补足蛋白质30g，严格控油）",
  "plans": [
    {
      "timeSlot": "午餐",
      "slotKey": "lunch",
      "recommendedCalories": 推荐本餐热量整数kcal,
      "options": [
        {
          "scene": "外卖便选",
          "name": "老乡鸡去皮香菇鸡汤 + 香葱蒸蛋 + 半碗米饭",
          "calories": 360,
          "protein": 26,
          "carbs": 38,
          "fat": 10,
          "reason": "去皮减油，蛋禽搭配吸收率高，碳水适中"
        },
        {
          "scene": "便利店快手",
          "name": "即食黑椒鸡胸肉 + 烤紫薯小个 + 无糖冰乌龙",
          "calories": 320,
          "protein": 30,
          "carbs": 35,
          "fat": 4,
          "reason": "全家/7-11随手买，强饱腹感抗饿"
        }
      ]
    }
  ],
  "exerciseAdvice": {
    "needExercise": false或true,
    "suggestion": "运动建议文本（如：傍晚快走25分钟可额外消耗约120kcal，让晚餐更丰富）",
    "burnCalories": 预计消耗整数kcal
  }
}''';

/// 周报 AI 点评与建议模型
class WeeklyAdviceResult {
  final String headline;
  final String review;
  final List<String> suggestions;
  final String encouragement;

  const WeeklyAdviceResult({
    required this.headline,
    required this.review,
    required this.suggestions,
    required this.encouragement,
  });

  factory WeeklyAdviceResult.fromJson(Map<String, dynamic> json) {
    final hl = json['headline'] is String ? (json['headline'] as String).trim() : '';
    final rv = json['review'] is String ? (json['review'] as String).trim() : '';
    final sugs = <String>[];
    if (json['suggestions'] is List) {
      for (final s in json['suggestions'] as List) {
        if (s is String && s.trim().isNotEmpty) {
          sugs.add(s.trim());
        }
      }
    }
    final enc = json['encouragement'] is String ? (json['encouragement'] as String).trim() : '';
    return WeeklyAdviceResult(
      headline: hl.isNotEmpty ? hl : '执行稳健，减脂节奏良好',
      review: rv,
      suggestions: sugs,
      encouragement: enc,
    );
  }

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'review': review,
        'suggestions': suggestions,
        'encouragement': encouragement,
      };
}

/// 饮食与运动建议选项
class MealOption {
  final String scene;
  final String name;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final String reason;

  const MealOption({
    required this.scene,
    required this.name,
    required this.calories,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.reason = '',
  });

  factory MealOption.fromJson(Map<String, dynamic> json) => MealOption(
        scene: '${json['scene'] ?? '方案'}',
        name: '${json['name'] ?? ''}',
        calories: num.tryParse('${json['calories']}')?.round() ?? 0,
        protein: num.tryParse('${json['protein']}')?.round() ?? 0,
        carbs: num.tryParse('${json['carbs']}')?.round() ?? 0,
        fat: num.tryParse('${json['fat']}')?.round() ?? 0,
        reason: '${json['reason'] ?? ''}',
      );
}

/// 某一时段（如午餐/下午茶/晚餐）的推荐计划
class MealSlotPlan {
  final String timeSlot;
  final String slotKey; // lunch, snack, dinner
  final int recommendedCalories;
  final List<MealOption> options;

  const MealSlotPlan({
    required this.timeSlot,
    required this.slotKey,
    required this.recommendedCalories,
    required this.options,
  });

  factory MealSlotPlan.fromJson(Map<String, dynamic> json) {
    final opts = <MealOption>[];
    if (json['options'] is List) {
      for (final it in json['options'] as List) {
        if (it is Map<String, dynamic>) {
          opts.add(MealOption.fromJson(it));
        } else if (it is Map) {
          opts.add(MealOption.fromJson(Map<String, dynamic>.from(it)));
        }
      }
    }
    return MealSlotPlan(
      timeSlot: '${json['timeSlot'] ?? '餐食建议'}',
      slotKey: '${json['slotKey'] ?? 'snack'}',
      recommendedCalories: num.tryParse('${json['recommendedCalories']}')?.round() ?? 0,
      options: opts,
    );
  }
}

/// 运动建议（调节热量用）
class ExerciseAdvice {
  final bool needExercise;
  final String suggestion;
  final int burnCalories;

  const ExerciseAdvice({
    required this.needExercise,
    required this.suggestion,
    required this.burnCalories,
  });

  factory ExerciseAdvice.fromJson(Map<String, dynamic> json) => ExerciseAdvice(
        needExercise: json['needExercise'] == true,
        suggestion: '${json['suggestion'] ?? ''}',
        burnCalories: num.tryParse('${json['burnCalories']}')?.round() ?? 0,
      );
}

/// 整体推荐结果
class MealRecommendationResult {
  final String summary;
  final int remainingCalorieBudget;
  final String macroFocus;
  final List<MealSlotPlan> plans;
  final ExerciseAdvice? exerciseAdvice;
  final String rawResponse;

  const MealRecommendationResult({
    required this.summary,
    required this.remainingCalorieBudget,
    required this.macroFocus,
    required this.plans,
    this.exerciseAdvice,
    this.rawResponse = '',
  });

  factory MealRecommendationResult.fromJson(Map<String, dynamic> json, {String raw = ''}) {
    final plans = <MealSlotPlan>[];
    if (json['plans'] is List) {
      for (final it in json['plans'] as List) {
        if (it is Map<String, dynamic>) {
          plans.add(MealSlotPlan.fromJson(it));
        } else if (it is Map) {
          plans.add(MealSlotPlan.fromJson(Map<String, dynamic>.from(it)));
        }
      }
    }
    ExerciseAdvice? ex;
    if (json['exerciseAdvice'] is Map) {
      ex = ExerciseAdvice.fromJson(Map<String, dynamic>.from(json['exerciseAdvice'] as Map));
    }
    return MealRecommendationResult(
      summary: '${json['summary'] ?? ''}',
      remainingCalorieBudget: num.tryParse('${json['remainingCalorieBudget']}')?.round() ?? 0,
      macroFocus: '${json['macroFocus'] ?? ''}',
      plans: plans,
      exerciseAdvice: ex,
      rawResponse: raw,
    );
  }
}

/// 解析智能推荐饮食
MealRecommendationResult parseMealRecommendation(String text) {
  final json = extractJsonObj(text);
  if (json != null) {
    return MealRecommendationResult.fromJson(json, raw: text);
  }
  return MealRecommendationResult(
    summary: text.isNotEmpty ? text : '未能解析出推荐方案',
    remainingCalorieBudget: 0,
    macroFocus: '',
    plans: const [],
    rawResponse: text,
  );
}

/// 解析 AI 周报建议（支持 JSON 解析与纯文本降级提取）
WeeklyAdviceResult parseWeeklyAdvice(String text) {
  final json = extractJsonObj(text);
  if (json != null && (json['review'] != null || json['suggestions'] != null)) {
    return WeeklyAdviceResult.fromJson(json);
  }

  var headline = '减脂周度复盘与建议';
  final suggestions = <String>[];
  final reviewBuffer = StringBuffer();
  final encBuffer = StringBuffer();
  var currentSection = '';

  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  for (final line in lines) {
    if (line.contains('本周点评') || line.contains('整体点评')) {
      currentSection = 'review';
      continue;
    } else if (line.contains('建议') || line.contains('下周建议')) {
      currentSection = 'suggestions';
      continue;
    } else if (line.contains('寄语') || line.contains('心态') || line.contains('教练寄语')) {
      currentSection = 'encouragement';
      continue;
    }

    if (currentSection == 'review') {
      reviewBuffer.writeln(line);
    } else if (currentSection == 'suggestions') {
      if (RegExp(r'^[-*•\d+.]').hasMatch(line)) {
        final clean = line.replaceFirst(RegExp(r'^[-*•\d+.\s]+'), '').trim();
        if (clean.isNotEmpty) suggestions.add(clean);
      } else {
        if (line.isNotEmpty) suggestions.add(line);
      }
    } else if (currentSection == 'encouragement') {
      encBuffer.writeln(line);
    } else if (headline == '减脂周度复盘与建议' && line.length < 30 && !line.startsWith('#')) {
      headline = line.replaceAll(RegExp(r'[*#]'), '').trim();
    }
  }

  final review = reviewBuffer.toString().trim();
  final encouragement = encBuffer.toString().trim();

  return WeeklyAdviceResult(
    headline: headline,
    review: review.isNotEmpty ? review : (text.length > 300 ? text.substring(0, 300) : text),
    suggestions: suggestions.isNotEmpty ? suggestions : ['继续保持合理热量缺口，规律作息与记录。'],
    encouragement: encouragement.isNotEmpty ? encouragement : '不求快但求稳，坚持就是胜利！',
  );
}

/// HTTP 状态码 → 中文提示
String httpErrorMsg(int code) {
  const map = {
    400: '请求被拒绝（400）：请检查模型名是否正确',
    401: 'API Key 无效或已过期（401）：请检查 Key 是否复制完整',
    402: '账户余额不足（402）：请到服务商官网充值',
    403: '无访问权限（403）：请检查 Key 的权限',
    404: '接口地址或模型名不存在（404）：请检查接口地址与模型名',
    429: '请求过于频繁（429）：请稍后再试',
    500: 'AI 服务内部错误（500）：请稍后再试',
    503: 'AI 服务繁忙（503）：请稍后再试',
  };
  return map[code] ?? 'AI 服务返回异常状态码 $code';
}

String netErrorMsg(Object? err) {
  final m = err?.toString() ?? '';
  if (m.contains('timeout') || m.contains('TimedOut')) return 'AI 请求超时：服务端生成较慢或网络波动，请稍后重试';
  if (m.contains('cancel')) return '请求已取消，请重试';
  // 域名解析失败：设备断网 / 无网络权限（旧安装包缺 INTERNET 权限时也会这样）
  if (m.contains('Failed host lookup') ||
      m.contains('Connection failed') ||
      m.contains('errno = 13')) {
    return '无法连接 AI 服务：请检查网络是否可用，若网络正常仍报此错，请重新安装最新打包';
  }
  return '网络异常：请检查网络后重试';
}

/// 规范化接口地址：去首尾空白与斜杠，剥离误粘贴的 /chat/completions 后缀
String normalizeEndpoint(String raw) {
  var e = raw.trim();
  e = e.replaceAll(RegExp(r'/chat/completions/?$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r'/+$'), '');
  return e;
}

/// 从 AI 回复文本中容错提取 JSON 对象（剥离围栏/杂文字）
Map<String, dynamic>? extractJsonObj(String? text) {
  if (text is! String) return null;
  var t = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false).firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  final s = t.indexOf('{');
  final e = t.lastIndexOf('}');
  if (s < 0 || e <= s) return null;
  try {
    final v = jsonDecode(t.substring(s, e + 1));
    return (v is Map) ? Map<String, dynamic>.from(v) : null;
  } catch (_) {
    return null;
  }
}

/// 判断是否为 Google Gemini 原生 REST 协议
bool isGeminiProvider(AiConfig config) {
  final ep = config.endpoint.toLowerCase().trim();
  final p = config.provider.trim().toLowerCase();

  // 1. 若端点明确含有 Gemini 专属特征（googleapis 或 generatecontent）
  if (ep.contains('generativelanguage.googleapis.com') ||
      ep.contains('generatecontent')) {
    return true;
  }

  // 2. 若端点明确是 OpenAI 协议（含有 /chat/completions 或 /openai）
  if (ep.contains('/chat/completions') || ep.contains('/openai')) {
    return false;
  }

  // 3. 若提供商显式为 gemini 或 google
  if (p == 'gemini' || p == 'google') {
    // 只有当 endpoint 被明确设置为非 deepseek 默认值的第三方 /v1 路径时才视为 OpenAI 代理
    if (ep.contains('/v1') && !ep.contains('/v1beta') && !ep.contains('deepseek.com') && !ep.contains('googleapis.com')) {
      return false;
    }
    return true;
  }

  // 4. 自定义端点：如果包含 v1beta 则为 Gemini 原生
  return ep.contains('v1beta');
}

/// 规范化 Gemini 端点并组装 generateContent 完整 URL
String buildGeminiUrl(String rawEndpoint, String model) {
  var e = rawEndpoint.trim();
  e = e.replaceAll(RegExp(r'/models/[^/:]+:generateContent.*$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r':generateContent.*$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r'/chat/completions/?$', caseSensitive: false), '');
  e = e.replaceAll(RegExp(r'/+$'), '');
  if (e.isEmpty) {
    e = 'https://generativelanguage.googleapis.com/v1beta';
  } else if (!e.contains('/v1') && !e.contains('/v1beta')) {
    e = '$e/v1beta';
  }
  final m = model.trim().isEmpty ? 'gemini-2.5-flash' : model.trim();
  return '$e/models/$m:generateContent';
}

/// 提取 Gemini 请求体（适配 systemInstruction 与 contents）
Map<String, dynamic> buildGeminiRequestBody(List<Map<String, String>> messages) {
  final systemParts = <Map<String, String>>[];
  final contents = <Map<String, dynamic>>[];

  for (final m in messages) {
    final role = m['role'] ?? 'user';
    final text = m['content'] ?? '';
    if (text.isEmpty) continue;

    if (role == 'system') {
      systemParts.add({'text': text});
    } else {
      final gRole = (role == 'assistant' || role == 'model') ? 'model' : 'user';
      contents.add({
        'role': gRole,
        'parts': [{'text': text}],
      });
    }
  }

  if (contents.isEmpty && systemParts.isNotEmpty) {
    contents.add({
      'role': 'user',
      'parts': [{'text': systemParts.map((p) => p['text']).join('\n\n')}],
    });
    systemParts.clear();
  }

  final body = <String, dynamic>{
    'contents': contents,
    'generationConfig': {
      'temperature': 0.2,
    },
  };

  if (systemParts.isNotEmpty) {
    body['systemInstruction'] = {
      'parts': systemParts,
    };
  }

  return body;
}

/// 解析 Gemini 响应并累计 usage
String parseGeminiResponse(
  Map<String, dynamic> data, {
  void Function(Map<String, dynamic> usage)? onUsage,
}) {
  if (data['usageMetadata'] is Map) {
    final u = data['usageMetadata'] as Map;
    onUsage?.call({
      'prompt_tokens': u['promptTokenCount'] ?? 0,
      'completion_tokens': u['candidatesTokenCount'] ?? 0,
      'total_tokens': u['totalTokenCount'] ?? 0,
    });
  }

  final candidates = data['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    final feedback = data['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw Exception('Gemini 拒绝响应：${feedback['blockReason']}');
    }
    throw Exception('AI 未返回内容，请重试');
  }

  final cand = candidates[0];
  if (cand is Map) {
    final contentMap = cand['content'];
    if (contentMap is Map && contentMap['parts'] is List) {
      final parts = contentMap['parts'] as List;
      // 优先拼接非思维链的正文文本（忽略 thought: true 部分）
      final text = parts
          .whereType<Map>()
          .where((p) => p['thought'] != true)
          .map((p) => p['text'])
          .whereType<String>()
          .join('');
      if (text.isNotEmpty) return text;

      // 兜底：若全是 thought，取全部 text
      final allText = parts
          .whereType<Map>()
          .map((p) => p['text'])
          .whereType<String>()
          .join('');
      if (allText.isNotEmpty) return allText;
    }
    final finishReason = cand['finishReason'];
    if (finishReason != null && finishReason != 'STOP') {
      throw Exception('Gemini 响应未完成：$finishReason');
    }
  }
  throw Exception('AI 未返回内容，请重试');
}

String _extractGeminiError(dynamic data, int? statusCode) {
  if (data is Map && data['error'] is Map) {
    final err = data['error'] as Map;
    final msg = err['message']?.toString() ?? '';
    final status = err['status']?.toString() ?? '';
    if (msg.contains('API key not valid')) {
      return 'Google API Key 无效或格式不正确，请核对后再试';
    }
    if (msg.contains('location') || msg.contains('not supported')) {
      return '当前网络地区暂不支持 Google API，请切换网络环境或使用代理接口';
    }
    if (status == 'RESOURCE_EXHAUSTED' || statusCode == 429) {
      return '已超出 Gemini 速率限制（429）：请稍后再试或在设置中换用其他模型';
    }
    if (msg.isNotEmpty) return 'Gemini 错误（$status）：$msg';
  }
  return httpErrorMsg(statusCode ?? 0);
}

String? _extractOpenAiError(dynamic data, int? statusCode) {
  if (data is Map) {
    if (data['error'] is Map) {
      final err = data['error'] as Map;
      final msg = err['message']?.toString();
      if (msg != null && msg.isNotEmpty) {
        if (msg.contains('Insufficient Balance')) {
          return '账户余额不足（402）：请到服务商官网充值';
        }
        return 'AI 接口报错（$statusCode）：$msg';
      }
    } else if (data['message'] is String && (data['message'] as String).isNotEmpty) {
      return 'AI 接口报错（$statusCode）：${data['message']}';
    }
  }
  return null;
}

/// 检查食物/食材名称是否合法有效，剔除空白、纯数字、纯符号、算式、元数据字段与统计小结
bool isValidFoodBreakdownName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;

  // 排除纯数字、纯符号、算式
  if (RegExp(r'^[\d\s\.\+\-\*\/=＝≈~:：,，;；()（）\[\]【】%％#№]+$').hasMatch(trimmed)) {
    return false;
  }
  // 排除单纯的数字序号，如 "1." 或 "1"
  if (RegExp(r'^\d+[\.、]?$').hasMatch(trimmed)) return false;

  // 排除非食物的元数据/总结字段
  const invalidKeywords = {
    '合计', '总计', '共计', '小计', '整餐', '整餐总重', '菜品总重', '米饭重量', '食物总重', '总重量',
    '预估克数', '预估重量', '预估份量', '预估热量', '预估总热量', '标称热量', '实际热量', '总热量',
    '蛋白质', '脂肪', '碳水', '碳水化合物', '钠', '膳食纤维', '热量', '卡路里',
    '蛋白质总量', '脂肪总量', '碳水总量', '缩放系数', '等比例缩放', '修正后总计', '营养小结',
    '如无误', '请核对', '确认', '打卡', '核算',
  };
  final cleanName = trimmed.replaceAll(RegExp(r'[:：\s]'), '');
  if (invalidKeywords.contains(cleanName)) return false;

  // 如果名称就是统计词加上数字（如 "菜品总重210g" 或 "蛋白质：5.2g"），也不是食物
  if (RegExp(
    r'^(?:菜品总重|整餐总重|米饭重量|总重|总热量|预估总热量|预估克数|预估热量|蛋白质|脂肪|碳水|碳水化合物|钠|膳食纤维|缩放系数)\s*[:：]?\s*[\d\.]+\s*(?:g|克|kcal|大卡|%|毫克|mg)?$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return false;
  }
  // 排除明显的交互问答与对话前缀
  if (trimmed.startsWith('👉') ||
      trimmed.startsWith('收到') ||
      trimmed.startsWith('请核对') ||
      trimmed.startsWith('如无误') ||
      trimmed.startsWith('重新校准后')) {
    return false;
  }
  return true;
}

/// 清理食物名称的前置序号与前后空白（如 "1. 白米饭" -> "白米饭"）
String cleanFoodBreakdownName(String name) {
  var s = name.trim();
  s = s.replaceAll(RegExp(r'^\s*(?:\d+[\.、\s]+|[-*•]\s*|[\u2460-\u2473]\s*)'), '').trim();
  return s;
}

/// 校准与对齐 AI 返回的总热量与拆解详情，确保 100% 绝对一致，消除前后打架
(int, String) reconcileCalorieAndDetail(int rawCal, String? rawDetail) {
  var detail = (rawDetail ?? '').trim();
  if (detail.isEmpty) {
    return (rawCal, '总热量约 $rawCal kcal');
  }

  // 清理 detail 中夹杂的累加算式（如 "26+33+55+31+59+70=506" 或 "(26+33+55=506)"）
  detail = detail.replaceAll(
    RegExp(r'(?:[，,；;\s]|\b)?[\(（]?\s*(?:\d+\s*[\+＋]\s*)+\d+\s*(?:[=＝]\s*\d+)?\s*[\)）]?', caseSensitive: false),
    '',
  ).trim();
  detail = detail.replaceAll(RegExp(r'^[，,；;\s]+|[，,；;\s]+$'), '').trim();

  // 匹配 detail 末尾或其中的合计表达，如：
  // "总热量预估：约 605 kcal", "预估总热量：约 498 kcal", "合计161", "合计 161", "总计 161", "共计161"
  final sumRegex = RegExp(
    r'(?:总热量预估|预估总热量|整餐总热量|总热量合计|总热量|合计|总计|共计|共约|合计约|总计约|小计|＝|=)\s*[:：]?\s*≈?\s*约?\s*(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?',
    caseSensitive: false,
  );


  final matches = sumRegex.allMatches(detail).toList();
  if (matches.isNotEmpty) {
    final lastMatch = matches.last;
    final parsedCal = int.tryParse(lastMatch.group(1) ?? '');
    if (parsedCal != null && (parsedCal != 0 || rawCal != 0)) {
      if (parsedCal != rawCal) {
        // 当 detail 的合计值与顶层 calories 字段不一致时：
        // 若差异在合理范围（<=150 kcal 或 25% 比例内），说明 detail 的分项累加推导更细致，以 detail 的加总值为准
        final diff = (parsedCal - rawCal).abs();
        if (diff <= 150 || (rawCal != 0 && diff / rawCal.abs() <= 0.25)) {
          rawCal = parsedCal;
        } else {
          // 若差异过大，强制将 detail 末尾的合计修正为 rawCal，确保两者绝对一致
          detail = '${detail.substring(0, lastMatch.start)}合计 $rawCal kcal${detail.substring(lastMatch.end)}';
        }
      }
    }
  } else {
    // 若 detail 没写合计后缀，且含有多项拆解，自动在末尾追加规范合计
    if (detail.contains('+') || detail.contains('，') || detail.contains(',') || detail.contains('≈')) {
      detail = '$detail，合计约 $rawCal kcal';
    }
  }

  return (rawCal, detail);
}

/// 判断在 OpenAI 兼容协议下是否应向服务端发送 'thinking': {'type': 'disabled'}
/// DeepSeek V4 / V4.1 系列默认开启思考模式 (effort=high)，
/// 估算热量/运动消耗这类结构化小任务使用非思考模式可极大提速（从 30~40s 缩减到 1~2s 秒级返回）。
bool shouldPassThinkingDisabled(
  String model, {
  String provider = 'deepseek',
  String endpoint = 'https://api.deepseek.com',
  bool enableThinking = false,
}) {
  if (enableThinking) return false;
  final isDeepSeek = provider.trim().toLowerCase() == 'deepseek' ||
      endpoint.toLowerCase().contains('deepseek.com');
  if (!isDeepSeek) return false;
  final m = model.toLowerCase();
  return m.contains('flash') || m.contains('v4') || m.contains('pro');
}

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  /// 测试专用的 Mock 回调
  Future<String> Function(
    AiConfig config,
    List<Map<String, String>> messages, {
    bool enableThinking,
    int timeoutMs,
    void Function(Map<String, dynamic>)? onUsage,
  })? mockChatHandler;

  /// 测试专用的 Vision Mock 回调
  Future<String> Function(
    AiConfig config, {
    required String systemPrompt,
    required String userPrompt,
    String? imageBase64,
    String? mimeType,
    int timeoutMs,
    void Function(Map<String, dynamic>)? onUsage,
  })? mockVisionHandler;

  /// 全局单例 Dio：底层 HttpClient 复用连接池（keep-alive），
  /// 避免每次调用重新 DNS + TCP + TLS 握手（移动网络下可省几百毫秒）
  Dio? _dio;
  Dio _client() {
    if (_dio != null) return _dio!;
    _dio = Dio(BaseOptions(
      contentType: 'application/json',
      // 连接建立上限：与接收超时分离，避免黑洞连接（如 IPv6 不通）长时间挂住
      connectTimeout: const Duration(seconds: 15),
    ));
    return _dio!;
  }

  /// 通用 chat 调用：根据 provider 自动分流 OpenAI 兼容 或 Google Gemini 原生 REST
  Future<String> chat(AiConfig config, List<Map<String, String>> messages,
      {int timeoutMs = 60000, bool enableThinking = false, void Function(Map<String, dynamic> usage)? onUsage}) async {
    if (mockChatHandler != null) {
      return mockChatHandler!(
        config,
        messages,
        enableThinking: enableThinking,
        timeoutMs: timeoutMs,
        onUsage: onUsage,
      );
    }
    if (config.apiKey.isEmpty || config.endpoint.isEmpty) {
      throw Exception('未配置 AI：请到「设置 → AI 服务」填写 API Key');
    }

    if (isGeminiProvider(config)) {
      return _chatGemini(
        config,
        messages,
        timeoutMs: timeoutMs,
        onUsage: onUsage,
      );
    }

    final base = normalizeEndpoint(config.endpoint);
    final model = config.model.isEmpty ? 'deepseek-flash' : config.model;
    final sw = Stopwatch()..start();
    debugPrint('[AiService] >>> $base/chat/completions model=$model thinking=$enableThinking '
        'msg=${messages.map((m) => '${m['role']}:${(m['content'] ?? '').length}字').join(' | ')}');
    // 仅在明确是 deepseek-flash 或 v4 架构时，才在非深度思考时传 thinking: disabled 提速
    final shouldPassThinkingDisabledFlag = shouldPassThinkingDisabled(
      model,
      provider: config.provider,
      endpoint: base,
      enableThinking: enableThinking,
    );

    try {
      final res = await _client().post(
        '$base/chat/completions',
        data: {
          'model': model,
          'temperature': 0.2,
          'messages': messages,
          if (shouldPassThinkingDisabledFlag) 'thinking': {'type': 'disabled'},
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
          // 深度思考模式放宽到 90s 超时，普通模式 60s
          receiveTimeout: Duration(milliseconds: enableThinking ? 90000 : timeoutMs),
        ),
      );
      debugPrint('[AiService] <<< HTTP ${res.statusCode} 耗时 ${sw.elapsedMilliseconds}ms');
      if (res.statusCode != 200) {
        final serverErr = _extractOpenAiError(res.data, res.statusCode);
        throw Exception(serverErr ?? httpErrorMsg(res.statusCode ?? 0));
      }
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
      // 累计本 App 的 API 用量（tokens/次数）
      final usage = data['usage'];
      if (usage is Map) {
        onUsage?.call(Map<String, dynamic>.from(usage));
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) throw Exception('AI 未返回内容，请重试');
      final ch = choices[0];
      final content = (ch is Map) ? (ch['message'] is Map ? (ch['message'] as Map)['content'] : null) : null;
      if (content is! String || content.isEmpty) throw Exception('AI 未返回内容，请重试');
      return content;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final responseData = e.response?.data;
      debugPrint('[AiService] !!! DioException type=${e.type} '
          'status=$code 耗时 ${sw.elapsedMilliseconds}ms err=${e.error} msg=${e.message}');
      if (responseData != null) debugPrint('[AiService] !!! body=$responseData');

      // 若携带 thinking 参数被服务端 400 拒绝，自动剔除 thinking 参数重试一次
      if (code == 400 && shouldPassThinkingDisabledFlag) {
        try {
          debugPrint('[AiService] 400 尝试不带 thinking 重试...');
          return await _chatWithoutThinking(
            base,
            model,
            config.apiKey.trim(),
            messages,
            timeoutMs: timeoutMs,
            onUsage: onUsage,
          );
        } catch (_) {}
      }

      final serverErr = _extractOpenAiError(responseData, code);
      if (serverErr != null) throw Exception(serverErr);
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('连接 AI 服务超时：请检查网络后重试');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('AI 响应超时：服务端生成较慢，请稍后重试或手动填写');
      }
      if (e.type == DioExceptionType.cancel) throw Exception('请求已取消，请重试');
      throw Exception(netErrorMsg(e.error ?? e.message));
    } catch (e) {
      debugPrint('[AiService] ??? 未知异常 耗时 ${sw.elapsedMilliseconds}ms: $e');
      if (e is Exception && e.toString().contains('网络超时')) rethrow;
      if (e is Exception && e.toString().contains('请求已取消')) rethrow;
      rethrow;
    }
  }

  /// 兜底不带思考控制参数的标准 OpenAI chat 调用
  Future<String> _chatWithoutThinking(
    String base,
    String model,
    String apiKey,
    List<Map<String, String>> messages, {
    int timeoutMs = 60000,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    final res = await _client().post(
      '$base/chat/completions',
      data: {
        'model': model,
        'temperature': 0.2,
        'messages': messages,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
        receiveTimeout: Duration(milliseconds: timeoutMs),
      ),
    );
    if (res.statusCode != 200) {
      final serverErr = _extractOpenAiError(res.data, res.statusCode);
      throw Exception(serverErr ?? httpErrorMsg(res.statusCode ?? 0));
    }
    final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
    final usage = data['usage'];
    if (usage is Map) {
      onUsage?.call(Map<String, dynamic>.from(usage));
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) throw Exception('AI 未返回内容，请重试');
    final ch = choices[0];
    final content = (ch is Map) ? (ch['message'] is Map ? (ch['message'] as Map)['content'] : null) : null;
    if (content is! String || content.isEmpty) throw Exception('AI 未返回内容，请重试');
    return content;
  }

  /// Google Gemini 原生 REST 协议调用（generateContent）
  Future<String> _chatGemini(
    AiConfig config,
    List<Map<String, String>> messages, {
    int timeoutMs = 60000,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    final model = config.model.trim().isEmpty ? 'gemini-2.5-flash' : config.model.trim();
    final url = buildGeminiUrl(config.endpoint, model);
    final reqBody = buildGeminiRequestBody(messages);
    final sw = Stopwatch()..start();
    debugPrint('[AiService:Gemini] >>> POST $url model=$model '
        'msg=${messages.map((m) => '${m['role']}:${(m['content'] ?? '').length}字').join(' | ')}');

    try {
      final res = await _client().post(
        url,
        data: reqBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': config.apiKey.trim(),
          },
          receiveTimeout: Duration(milliseconds: timeoutMs),
        ),
      );
      debugPrint('[AiService:Gemini] <<< HTTP ${res.statusCode} 耗时 ${sw.elapsedMilliseconds}ms');
      if (res.statusCode != 200) {
        throw Exception(_extractGeminiError(res.data, res.statusCode));
      }
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      return parseGeminiResponse(data, onUsage: onUsage);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      debugPrint('[AiService:Gemini] !!! DioException type=${e.type} '
          'status=$code 耗时 ${sw.elapsedMilliseconds}ms err=${e.error} msg=${e.message}');
      if (e.response?.data != null) {
        debugPrint('[AiService:Gemini] !!! body=${e.response?.data}');
        throw Exception(_extractGeminiError(e.response?.data, code));
      }
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception('连接 Google AI 服务超时：请检查网络后重试');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Gemini 响应超时：服务端生成较慢，请稍后重试或手动填写');
      }
      if (e.type == DioExceptionType.cancel) throw Exception('请求已取消，请重试');
      throw Exception(netErrorMsg(e.error ?? e.message));
    } catch (e) {
      debugPrint('[AiService:Gemini] ??? 未知异常 耗时 ${sw.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  bool hasConfig(AiConfig config) => config.hasConfig;

  /// 食物热量及营养素查询（支持本地缓存与损耗扣减）
  Future<Map<String, dynamic>> queryCalorie(AiConfig config, String foodDesc,
      {bool enableThinking = false, void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kCalorieSys},
        {'role': 'user', 'content': '食物描述：$foodDesc'},
      ],
      enableThinking: enableThinking,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动录入热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < -2000 || cal > 20000) throw Exception('AI 返回的热量数值异常，请手动录入');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    final items = parseBreakdownItems(obj['items'], reconciled.$2);
    return {
      'name': (obj['name'] is String && (obj['name'] as String).isNotEmpty) ? obj['name'] : '食物',
      'calories': reconciled.$1,
      'protein': num.tryParse('${obj['protein']}')?.round(),
      'carbs': num.tryParse('${obj['carbs']}')?.round(),
      'fat': num.tryParse('${obj['fat']}')?.round(),
      'unit': obj['unit'] is String ? obj['unit'] : '',
      'detail': reconciled.$2,
      'items': items,
      'confidence': obj['confidence'] is num ? obj['confidence'] : 0.5,
    };
  }

  /// 计划文档 → 计划 JSON（AI 导入）
  Future<Map<String, dynamic>> generatePlan(AiConfig config, String docText,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kPlanConvertPrompt},
        {'role': 'user', 'content': '今天是 ${dateCn(todayStr())}（${todayStr()}）。计划文档：\n$docText'},
      ],
      timeoutMs: 90000,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 未返回有效的 JSON，请重试；多次失败可换更完整的计划文档');
    // AI 偶尔漏写或写错 version，直接修正
    obj['version'] = '1.0';
    return obj;
  }

  /// 测试连接：向 AI 发送测试并返回清晰反馈结果
  Future<String> testAI(AiConfig config, {void Function(Map<String, dynamic>)? onUsage}) async {
    try {
      final res = await queryCalorie(config, '一个水煮蛋', onUsage: onUsage);
      final cal = res['calories'];
      final p = res['protein'];
      final c = res['carbs'];
      final f = res['fat'];
      final macroStr = (p != null || c != null || f != null)
          ? '（P: ${p ?? 0}g / C: ${c ?? 0}g / F: ${f ?? 0}g）'
          : '';
      return '连接成功 ✓ AI 测算返回：水煮蛋 约 $cal kcal$macroStr';
    } catch (e) {
      // 若因 strict JSON 解析失败但实际网络通畅，降级验证简单纯文本问答
      final text = await chat(
        config,
        [
          {'role': 'user', 'content': '请回复六个字：AI服务已连接'}
        ],
        timeoutMs: 15000,
        onUsage: onUsage,
      );
      final clean = text.trim();
      return '连接成功 ✓ AI 回复：${clean.length > 50 ? '${clean.substring(0, 50)}...' : clean}';
    }
  }

  /// 从文本描述中容错解析食物拆解明细表格（兜底与历史兼容）
  static List<FoodBreakdownItem> parseBreakdownFromText(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final clean = text.trim();
    final content = clean.replaceAll(RegExp(r'^(?:AI\s*拆解|食物库(?:组合|命中)?|分项拆解)[：:]\s*'), '');

    // 1. 优先检查：是否包含带序号/项目符的多行结构化食物条目块
    // 例如复制自 AI 助手的问答或报表：
    // 1. 白米饭（单独核算）
    // 预估克数：200g
    // 预估热量：232 kcal
    final blockSplits = RegExp(r'(?:^|\n)\s*(?:\d+[\.、]|\([0-9]+\)|（[0-9]+）)\s*').allMatches(content).toList();
    if (blockSplits.isNotEmpty) {
      final blockResults = <FoodBreakdownItem>[];
      for (var i = 0; i < blockSplits.length; i++) {
        final start = blockSplits[i].end;
        final end = (i + 1 < blockSplits.length) ? blockSplits[i + 1].start : content.length;
        final block = content.substring(start, end).trim();
        final lines = block.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (lines.isEmpty) continue;
        final rawName = lines.first;

        // 优先检查管道符格式: "白米饭：预估 180g | 预估热量 210kcal | ..."
        if (rawName.contains('|') || rawName.contains('｜')) {
          final parts = rawName.split(RegExp(r'[|｜]'));
          final namePart = parts[0].trim();
          String n = '';
          String p = '';
          if (namePart.contains('：') || namePart.contains(':')) {
            final np = namePart.split(RegExp(r'[:：]'));
            n = cleanFoodBreakdownName(np[0]);
            p = np.sublist(1).join(':').replaceFirst(RegExp(r'^(?:预估|约)?\s*'), '').trim();
          } else {
            n = cleanFoodBreakdownName(namePart);
          }
          int c = 0;
          for (var pIdx = 1; pIdx < parts.length; pIdx++) {
            final part = parts[pIdx].trim();
            final mC = RegExp(r'(?:预估热量|热量|能量)\s*[:：约约为\s]*(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)?|(-?\d+)\s*(?:kcal|大卡|卡路里|千卡)', caseSensitive: false).firstMatch(part);
            if (mC != null) {
              final val = int.tryParse(mC.group(1) ?? mC.group(2) ?? '') ?? 0;
              if (val > 0) c = val;
            }
            if (p.isEmpty) {
              final mPort = RegExp(r'(?:预估克数|克数|重量|份量)\s*[:：约约为\s]*([\d\.\/]+[^\s\|｜]+)').firstMatch(part);
              if (mPort != null) p = mPort.group(1)?.trim() ?? '';
            }
          }
          if (c > 0 && isValidFoodBreakdownName(n)) {
            blockResults.add(FoodBreakdownItem(name: n, portion: p, calories: c));
            continue;
          }
        }

        final name = cleanFoodBreakdownName(rawName.replaceFirst(RegExp(r'[:：]$'), ''));
        if (!isValidFoodBreakdownName(name)) continue;

        // 在该块中提取热量与重量
        final calMatch = RegExp(r'(?:预估热量|热量|能量)[:：约约为\s]*(\d+)\s*(?:kcal|大卡)?', caseSensitive: false).firstMatch(block);
        final cal = calMatch != null ? int.tryParse(calMatch.group(1) ?? '') ?? 0 : 0;

        final portionMatch = RegExp(r'(?:预估克数|克数|重量|份量)[:：约约为\s]*([^\n\r|｜]+)').firstMatch(block);
        final portion = portionMatch?.group(1)?.trim() ?? '';

        if (cal > 0 || portion.isNotEmpty) {
          blockResults.add(FoodBreakdownItem(name: name, portion: portion, calories: cal));
        }

      }
      if (blockResults.isNotEmpty) {
        return blockResults;
      }
    }

    // 2. 清理单行中夹杂的累加算式（如 "26+33+55+31+59+70=506"）
    final inlineContent = content.replaceAll(
      RegExp(r'(?:[，,；;\s]|\b)?[\(（]?\s*(?:\d+\s*[\+＋]\s*)+\d+\s*(?:[=＝]\s*\d+)?\s*[\)）]?', caseSensitive: false),
      '',
    ).trim();

    // 括号感知的顶层切分（避免切碎括号内的逗号，如 "牛肉面(1碗, 550kcal)"）
    final segments = <String>[];
    var depth = 0;
    var current = StringBuffer();
    for (var i = 0; i < inlineContent.length; i++) {
      final char = inlineContent[i];
      if (char == '(' || char == '（') {
        depth++;
        current.write(char);
      } else if (char == ')' || char == '）') {
        if (depth > 0) depth--;
        current.write(char);
      } else if (depth == 0 && (char == '，' || char == ',' || char == ';' || char == '；' || char == '+' || char == '\n' || char == '\r')) {
        final s = current.toString().trim();
        if (s.isNotEmpty) segments.add(s);
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    final rem = current.toString().trim();
    if (rem.isNotEmpty) segments.add(rem);

    final results = <FoodBreakdownItem>[];

    for (final rawSeg in segments) {
      var seg = rawSeg.trim();
      if (seg.isEmpty) continue;

      // 剔除纯数字、纯符号或算式残片
      if (RegExp(r'^[\d\s\.\+\-\*\/=＝≈~:：,，;；()（）\[\]【】%％#№]+$').hasMatch(seg)) continue;

      // 剔除合计、小结行
      if (RegExp(r'^(?:合计|总计|共计|小计|总热量|整餐总重|菜品总重|米饭重量|修正后总计|营养小结|预估总热量|蛋白质总量|脂肪总量|碳水总量)\b', caseSensitive: false).hasMatch(seg)) continue;

      // 去除可能的前置序号
      seg = cleanFoodBreakdownName(seg);

      // 1. 本地食物库格式：如 "牛肉面(1碗, 550kcal)" 或 "葡式蛋挞(1个, 290kcal)"
      final mDb = RegExp(r'^([^\(（]+)[\(（]([^\,，]+)[\,，]\s*(-?\d+)\s*(?:kcal)?[\)）]?$', caseSensitive: false).firstMatch(seg);
      if (mDb != null) {
        final name = cleanFoodBreakdownName(mDb.group(1) ?? '');
        final portion = mDb.group(2)?.trim() ?? '';
        final cal = int.tryParse(mDb.group(3) ?? '') ?? 0;
        if (isValidFoodBreakdownName(name)) {
          results.add(FoodBreakdownItem(name: name, portion: portion, calories: cal));
          continue;
        }
      }

      // 2. 带 ≈、=、: 的拆解格式，如 "米饭100g≈116" 或 "炒茄子1/4盘(含油约2.5g)≈45" 或 "空气炸锅逼出油3g≈-27"
      // 从后往前找最后一个分隔符（避免食物括号内备注中的冒号等干扰）
      final allSeps = RegExp(r'[≈=：:]').allMatches(seg).toList();
      if (allSeps.isNotEmpty) {
        final lastSep = allSeps.last;
        final left = seg.substring(0, lastSep.start).trim();
        final right = seg.substring(lastSep.end).trim();
        final calMatch = RegExp(r'^\s*(-?\d+)').firstMatch(right);
        if (calMatch != null) {
          final cal = int.tryParse(calMatch.group(1) ?? '') ?? 0;
          final pMatch = RegExp(r'([\d\.\/]+[^\d\s\(\)（）]+(?:\([^\)]+\)|（[^）]+）)?)\s*$').firstMatch(left);
          if (pMatch != null) {
            final portion = pMatch.group(1)?.trim() ?? '';
            final rawName = left.substring(0, pMatch.start).trim();
            final name = cleanFoodBreakdownName(rawName.isNotEmpty ? rawName : left);
            if (isValidFoodBreakdownName(name)) {
              results.add(FoodBreakdownItem(
                name: name,
                portion: portion,
                calories: cal,
              ));
              continue;
            }
          } else {
            final name = cleanFoodBreakdownName(left);
            if (isValidFoodBreakdownName(name)) {
              results.add(FoodBreakdownItem(name: name, portion: '', calories: cal));
              continue;
            }
          }
        }
      }

      // 3. 通用兜底：提取末尾数字为热量（支持负数损耗）
      final endCal = RegExp(r'(-?\d+)\s*(?:kcal)?\s*$', caseSensitive: false).firstMatch(seg);
      if (endCal != null) {
        final cal = int.tryParse(endCal.group(1) ?? '') ?? 0;
        final left = seg.substring(0, endCal.start).trim();
        final name = cleanFoodBreakdownName(left);
        if (isValidFoodBreakdownName(name)) {
          results.add(FoodBreakdownItem(name: name, portion: '', calories: cal));
        }
      }
    }
    return results;
  }

  /// 提取/转换 AI 返回的 items 结构，若缺失则降级从 detail 文本解析
  static List<FoodBreakdownItem> parseBreakdownItems(dynamic rawItems, String? fallbackDetail) {
    if (rawItems is List && rawItems.isNotEmpty) {
      final list = <FoodBreakdownItem>[];
      for (final it in rawItems) {
        if (it is Map) {
          final rawName = '${it['name'] ?? ''}'.trim();
          final name = cleanFoodBreakdownName(rawName);
          final portion = '${it['portion'] ?? it['weight'] ?? ''}'.trim();
          final cal = num.tryParse('${it['calories']}')?.round() ?? 0;
          if (isValidFoodBreakdownName(name)) {
            list.add(FoodBreakdownItem(name: name, portion: portion, calories: cal));
          }
        }
      }
      if (list.isNotEmpty) return list;
    }
    return parseBreakdownFromText(fallbackDetail);
  }

  /// 一餐实际热量与三大营养素估算（支持"计划+少了什么"的口语描述及深度思考），resolve { calories, protein, carbs, fat, detail, items }
  Future<Map<String, dynamic>> estimateMeal(AiConfig config, String desc,
      {bool enableThinking = false, void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kMealEstSys},
        {'role': 'user', 'content': '这一餐的描述：$desc'},
      ],
      enableThinking: enableThinking,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < -2000 || cal > 5000) throw Exception('AI 估算的热量超出合理范围，请手动填写');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    final items = parseBreakdownItems(obj['items'], reconciled.$2);
    return {
      'calories': reconciled.$1,
      'protein': num.tryParse('${obj['protein']}')?.round(),
      'carbs': num.tryParse('${obj['carbs']}')?.round(),
      'fat': num.tryParse('${obj['fat']}')?.round(),
      'detail': reconciled.$2,
      'items': items,
    };
  }

  /// FR6.9：计划条目编辑器整餐热量估算——输入为结构化食材清单（含用量）+ 做法步骤 + 备注，
  /// 专用提示词强调按用量逐项估算并计入烹饪隐藏热量与三大营养素；resolve { calories, protein, carbs, fat, detail }
  Future<Map<String, dynamic>> estimateItemMeal(AiConfig config, String desc,
      {bool enableThinking = false, void Function(Map<String, dynamic>)? onUsage}) async {
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kItemCalSys},
        {'role': 'user', 'content': '计划餐食的描述：\n$desc'},
      ],
      enableThinking: enableThinking,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写热量');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < -2000 || cal > 5000) throw Exception('AI 估算的热量超出合理范围，请手动填写');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    return {
      'calories': reconciled.$1,
      'protein': num.tryParse('${obj['protein']}')?.round(),
      'carbs': num.tryParse('${obj['carbs']}')?.round(),
      'fat': num.tryParse('${obj['fat']}')?.round(),
      'detail': reconciled.$2,
    };
  }

  /// 一次运动的消耗估算（支持"项目+时长"的口语描述），resolve { name, calories, detail }
  /// F10：携带个人基础资料（性别/年龄/身高/体重）按强度（MET 参照）估算
  Future<Map<String, dynamic>> estimateBurn(
    AiConfig config,
    String desc, {
    num? weight,
    String? gender, // 'male' | 'female'
    int? age,
    int? height,
    void Function(Map<String, dynamic>)? onUsage,
  }) async {
    final parts = <String>[];
    final g = gender == 'male' ? '男性' : (gender == 'female' ? '女性' : '');
    if (g.isNotEmpty) parts.add(g);
    if (age != null && age > 0) parts.add('$age岁');
    if (height != null && height > 0) parts.add('身高${height}cm');
    if (weight != null && weight > 0 && weight < 300) parts.add('体重约${fmtWeight(weight.toDouble())}kg');
    final user = parts.isEmpty
        ? '运动的描述：$desc'
        : '运动的描述：$desc；用户资料：${parts.join('，')}';
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kBurnEstSys},
        {'role': 'user', 'content': user},
      ],
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 返回格式异常，请手动填写消耗');
    final cal = num.tryParse('${obj['calories']}');
    if (cal == null || cal < 0 || cal > 5000) throw Exception('AI 估算的消耗超出合理范围，请手动填写');
    final reconciled = reconcileCalorieAndDetail(cal.round(), obj['detail'] as String?);
    final items = parseBreakdownItems(obj['items'], reconciled.$2);
    return {
      'name': (obj['name'] is String && (obj['name'] as String).isNotEmpty) ? obj['name'] : '运动',
      'calories': reconciled.$1,
      'detail': reconciled.$2,
      'items': items,
    };
  }

  /// 余额查询（DeepSeek /user/balance 接口）
  Future<Map<String, dynamic>> queryBalance(AiConfig config) async {
    if (config.apiKey.isEmpty) throw Exception('未配置 API Key，请先到「设置 → AI 服务」填写');
    final isDeepSeek = config.provider == 'deepseek' || RegExp(r'deepseek', caseSensitive: false).hasMatch(config.endpoint);
    if (!isDeepSeek) throw Exception('当前服务商暂不支持余额查询（仅 DeepSeek 支持）');
    final base = normalizeEndpoint(config.endpoint);
    try {
      final res = await _client().get(
        '$base/user/balance',
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey}'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (res.statusCode != 200) throw Exception(httpErrorMsg(res.statusCode ?? 0));
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      final infos = data['balance_infos'];
      if (infos is! List || infos.isEmpty) throw Exception('服务未返回余额信息');
      return data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      throw Exception(netErrorMsg(e.error ?? e.message));
    }
  }

  /// 引导页「AI 创造计划」：把用户的描述/条目列表生成为计划 JSON
  Future<Map<String, dynamic>> generatePlanFromInput(AiConfig config, String inputText, UserProfile profile,
      {void Function(Map<String, dynamic>)? onUsage}) async {
    final p = profile;
    final meta = <String>[];
    if (p.gender.isNotEmpty) meta.add(p.gender == 'male' ? '男性' : '女性');
    if (p.age != null) meta.add('${p.age}岁');
    if (p.height != null) meta.add('身高${p.height}cm');
    if (p.weight != null) meta.add('体重约${fmtWeight(p.weight!)}kg');
    final user = '今天是 ${dateCn(todayStr())}（${todayStr()}）。'
        '${meta.isNotEmpty ? '用户资料：${meta.join('，')}。' : ''}'
        '用户的需求描述：\n$inputText';
    final content = await chat(
      config,
      [
        {'role': 'system', 'content': kGuidePlanSys},
        {'role': 'user', 'content': user},
      ],
      timeoutMs: 90000,
      onUsage: onUsage,
    );
    final obj = extractJsonObj(content);
    if (obj == null) throw Exception('AI 未返回有效的 JSON，请重试或改用手动模式');
    obj['version'] = '1.0';
    return obj;
  }

  /// 周报「AI 营养师点评与建议」：根据本地统计数据生成定性分析与下周建议
  Future<WeeklyAdviceResult> generateWeeklyAdvice(
    AiConfig config,
    String statsSummary, {
    void Function(Map<String, dynamic>)? onUsage,
  }) async {
    final messages = [
      {'role': 'system', 'content': kWeeklyAdviceSys},
      {
        'role': 'user',
        'content': '请根据以下我过去 7 天的真实减脂数据，给出专业客观的周度复盘与下周指导：\n\n$statsSummary',
      },
    ];
    final content = await chat(
      config,
      messages,
      timeoutMs: 60000,
      onUsage: onUsage,
    );
    return parseWeeklyAdvice(content);
  }

  /// 今日记录专家级二次校验（一键智能校验）
  Future<String> verifyDaily(
    AiConfig config,
    String summaryText, {
    void Function(Map<String, dynamic>)? onUsage,
  }) async {
    final messages = [
      {'role': 'system', 'content': kDailyVerifySys},
      {
        'role': 'user',
        'content': '以下是我今日在减脂App中记录的饮食摄入与运动消耗清单（包含原始输入和系统估算/拆解结果）：\n\n$summaryText',
      },
    ];
    return await chat(
      config,
      messages,
      timeoutMs: 60000,
      onUsage: onUsage,
    );
  }

  /// 结合当前时间、今日摄入/消耗、保底 400+ 缺口推荐饮食与运动
  Future<MealRecommendationResult> recommendMeals(
    AiConfig config,
    String promptContext, {
    void Function(Map<String, dynamic>)? onUsage,
  }) async {
    final messages = [
      {'role': 'system', 'content': kMealRecommendationSys},
      {
        'role': 'user',
        'content': '请根据我当前的实际时间、剩余热量缺口及营养摄入现状，为我规划推荐接下来的饮食与运动安排：\n\n$promptContext',
      },
    ];
    final content = await chat(
      config,
      messages,
      timeoutMs: 60000,
      onUsage: onUsage,
    );
    return parseMealRecommendation(content);
  }

  /// 多模态视觉/配料图文识别 chat 调用：
  /// - 若提供 imageBase64，按协议组装图像 payload（OpenAI 兼容 image_url，Gemini inline_data）；
  /// - 若无图片或仅文本，直接回退为高速纯文本调用。
  Future<String> chatVision(
    AiConfig config, {
    required String systemPrompt,
    required String userPrompt,
    String? imageBase64,
    String mimeType = 'image/jpeg',
    int timeoutMs = 60000,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    if (mockVisionHandler != null) {
      return mockVisionHandler!(
        config,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        imageBase64: imageBase64,
        mimeType: mimeType,
        timeoutMs: timeoutMs,
        onUsage: onUsage,
      );
    }
    if (config.apiKey.isEmpty || config.endpoint.isEmpty) {
      throw Exception('未配置 AI：请到「设置 → AI 服务」填写 API Key');
    }

    // 1. Google Gemini 分流
    if (isGeminiProvider(config)) {
      return _chatGeminiVision(
        config,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        imageBase64: imageBase64,
        mimeType: mimeType,
        timeoutMs: timeoutMs,
        onUsage: onUsage,
      );
    }

    // 2. OpenAI 兼容视觉调用
    final base = normalizeEndpoint(config.endpoint);
    final model = config.model.isEmpty ? 'deepseek-flash' : config.model;

    // 组装 user content
    dynamic userContent;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      userContent = [
        {'type': 'text', 'text': userPrompt},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:$mimeType;base64,$imageBase64',
          },
        },
      ];
    } else {
      userContent = userPrompt;
    }

    final messages = [
      if (systemPrompt.isNotEmpty) {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userContent},
    ];

    try {
      final res = await _client().post(
        '$base/chat/completions',
        data: {
          'model': model,
          'temperature': 0.1,
          'messages': messages,
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
          receiveTimeout: Duration(milliseconds: timeoutMs),
        ),
      );
      if (res.statusCode != 200) {
        final serverErr = _extractOpenAiError(res.data, res.statusCode);
        throw Exception(serverErr ?? httpErrorMsg(res.statusCode ?? 0));
      }
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : {};
      final usage = data['usage'];
      if (usage is Map) {
        onUsage?.call(Map<String, dynamic>.from(usage));
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) throw Exception('AI 未返回内容，请重试');
      final ch = choices[0];
      final content = (ch is Map) ? (ch['message'] is Map ? (ch['message'] as Map)['content'] : null) : null;
      if (content is! String || content.isEmpty) throw Exception('AI 未返回识别内容，请重试');
      return content;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final responseData = e.response?.data;
      final serverErr = _extractOpenAiError(responseData, code);
      if (serverErr != null) throw Exception(serverErr);
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      if (e.type == DioExceptionType.connectionTimeout) throw Exception('连接 AI 服务超时：请检查网络');
      if (e.type == DioExceptionType.receiveTimeout) throw Exception('AI 视觉识别响应超时，请重试或手动输入');
      throw Exception(netErrorMsg(e.error ?? e.message));
    }
  }

  /// Gemini 原生多模态请求
  Future<String> _chatGeminiVision(
    AiConfig config, {
    required String systemPrompt,
    required String userPrompt,
    String? imageBase64,
    String mimeType = 'image/jpeg',
    int timeoutMs = 60000,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    final model = config.model.trim().isEmpty ? 'gemini-2.5-flash' : config.model.trim();
    final url = buildGeminiUrl(config.endpoint, model);

    final parts = <Map<String, dynamic>>[];
    parts.add({'text': userPrompt});
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      parts.add({
        'inline_data': {
          'mime_type': mimeType,
          'data': imageBase64,
        }
      });
    }

    final reqBody = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
      },
    };
    if (systemPrompt.isNotEmpty) {
      reqBody['systemInstruction'] = {
        'parts': [
          {'text': systemPrompt}
        ],
      };
    }

    try {
      final res = await _client().post(
        url,
        data: reqBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': config.apiKey.trim(),
          },
          receiveTimeout: Duration(milliseconds: timeoutMs),
        ),
      );
      if (res.statusCode != 200) {
        throw Exception(_extractGeminiError(res.data, res.statusCode));
      }
      final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      return parseGeminiResponse(data, onUsage: onUsage);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (e.response?.data != null) {
        throw Exception(_extractGeminiError(e.response?.data, code));
      }
      if (code != null && code >= 400) throw Exception(httpErrorMsg(code));
      if (e.type == DioExceptionType.connectionTimeout) throw Exception('连接 Google AI 服务超时');
      if (e.type == DioExceptionType.receiveTimeout) throw Exception('Gemini 视觉识别响应超时');
      throw Exception(netErrorMsg(e.error ?? e.message));
    }
  }

  /// 识别预包装食品的营养成分表与配料表，提取基准含量、配料与健康洞察
  Future<FoodPackageScanResult> analyzeFoodNutritionPackage(
    AiConfig config, {
    Uint8List? imageBytes,
    String? imageBase64,
    String mimeType = 'image/jpeg',
    String? rawText,
    void Function(Map<String, dynamic> usage)? onUsage,
  }) async {
    String? base64Str = imageBase64;
    if (base64Str == null && imageBytes != null && imageBytes.isNotEmpty) {
      base64Str = base64Encode(imageBytes);
    }

    final prompt = (rawText != null && rawText.trim().isNotEmpty)
        ? '请对以下食品包装营养成分表/配料表文本进行识别与标准化解析，提取各项基准营养数值与健康建议：\n\n$rawText'
        : '这是一张食品包装袋照片，请重点识别包装上的「营养成分表」（能量、蛋白质、脂肪、碳水、钠等每100g或每份数值）以及「配料表」，并完成千焦至千卡转换及健康度分析。';

    final res = await chatVision(
      config,
      systemPrompt: kNutritionScanSys,
      userPrompt: prompt,
      imageBase64: base64Str,
      mimeType: mimeType,
      timeoutMs: 60000,
      onUsage: onUsage,
    );

    final map = extractJsonObj(res);
    if (map != null) {
      return FoodPackageScanResult.fromJson(map);
    }

    // 若返回非严谨 JSON，使用本地正则容错兜底解析
    final fallback = FoodPackageScanResult.extractFromText(res);
    return fallback;
  }
}

