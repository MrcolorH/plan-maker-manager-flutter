/// 模板页数据：格式说明 / 完整示例 / AI 生成提示词（与 spec/import-format.md 同源）
/// 与旧版 template.js 内容完全一致
library;

const String kFormatBrief = '''【JSON 顶层结构】
{
  "version": "1.0",          // 必须为 "1.0"
  "meta": { ... },           // 可选：计划元信息
  "meals": [ ... ],          // 减脂餐计划（有则整体替换）
  "exercises": [ ... ]       // 运动计划（有则整体替换）
}

【meals 餐食项】
- type：breakfast / lunch / dinner / snack（早/午/晚/加餐）
- name：名称（必填）
- time：计划时间 HH:mm 24小时制（必填，如 "12:00"）
- calories：热量 kcal；自由餐填 null（不计入，打卡后补录实际热量）
- days：每周几执行，1=周一 … 7=周日；不填=每天
- dates：具体执行日期数组，如 ["2026-09-05","2026-09-19"]；填写后仅在这些日期生效，days/日期范围忽略（适合"某天吃什么"或"第1、3周周六"这类轮换安排）
- reminder：是否提醒，默认 true
- note：备注（进食顺序等）
- details：食材清单 [{item, amount}]
- steps：做法步骤（字符串数组）

【exercises 运动项】
- name / time 同上（必填）
- duration：时长分钟（必填 1-600）
- caloriesBurned：预估消耗 kcal
- days：每周几执行
- dates：具体执行日期数组（同上）
- startDate / endDate：阶段日期范围 YYYY-MM-DD（表达适应期/启动期等阶段）
- content：训练内容 [{item, detail, minutes}]

【meta】
- planName / startDate / endDate / baseWeight / targetWeight
- dailyCalorieTarget：每日目标摄入（写入设置）
- tdee：每日总消耗（写入设置，参与缺口计算）''';

const String kAiPrompt = '''你是专业的减脂营养师和健身教练。请根据我的个人情况，生成我的减脂计划，并严格按照下面的 JSON 格式输出。
要求：只输出一个完整的 JSON 代码块，不要输出任何其他解释文字。

我的情况：
【身高/体重/年龄/性别，如：175cm / 74kg / 30岁 / 男】
【目标，如：5个月减到65kg】
【饮食习惯偏好，如：自己做饭为主，周六允许一顿自由餐（如KFC）】
【运动基础，如：久坐办公，几乎不运动，只能晚上和周末安排】
【可用时间，如：工作日晚18:30后，每次不超过50分钟】

JSON 格式要求：
{
  "version": "1.0",
  "meta": {
    "planName": "计划名称",
    "startDate": "YYYY-MM-DD",
    "endDate": "YYYY-MM-DD",
    "baseWeight": 起始体重数字,
    "targetWeight": 目标体重数字,
    "dailyCalorieTarget": 每日目标摄入kcal,
    "tdee": 每日总消耗kcal估算
  },
  "meals": [
    {
      "id": "唯一英文id",
      "type": "lunch（breakfast/lunch/dinner/snack 四选一）",
      "name": "餐名",
      "time": "HH:mm（24小时制）",
      "calories": 热量数字或不固定则填null,
      "days": [1,2,3,4,5],
      "reminder": true,
      "note": "备注如进食顺序",
      "details": [{"item": "食材", "amount": "用量"}],
      "steps": ["步骤1", "步骤2"]
    }
  ],
  "exercises": [
    {
      "id": "唯一英文id",
      "name": "训练名",
      "time": "HH:mm",
      "duration": 总分钟数,
      "caloriesBurned": 预估消耗kcal,
      "days": [1,3,5],
      "startDate": "YYYY-MM-DD",
      "endDate": "YYYY-MM-DD",
      "reminder": true,
      "note": "强度原则/注意事项",
      "content": [{"item": "热身", "detail": "具体内容", "minutes": 3}]
    }
  ]
}

额外要求：
1. days 用数字表示星期几：1=周一 … 7=周日；不填表示每天
2. 运动计划按阶段划分，用 startDate/endDate 表达各阶段（如适应期/启动期/巩固期），不同阶段可以有不同 days 频率
3. 每周安排至少1天完全休息（建议周日）
4. 热量为合理估算值；自由餐（如周六KFC）calories 填 null
5. 计划要循序渐进、安全第一，关节疼痛时降强度的原则写入 note''';

const String kExampleJson = '''{
  "version": "1.0",
  "meta": {
    "planName": "我的减脂计划（2026.9 - 2027.1）",
    "startDate": "2026-09-01",
    "endDate": "2027-01-31",
    "baseWeight": 74,
    "targetWeight": 65,
    "dailyCalorieTarget": 1400,
    "tdee": 2000
  },
  "meals": [
    {
      "id": "lunch-weekday",
      "type": "lunch",
      "name": "冻豆腐虾仁荞麦面 + 焦边煎蛋",
      "time": "12:00",
      "calories": 500,
      "days": [1, 2, 3, 4, 5],
      "reminder": true,
      "note": "进食顺序：白菜→虾仁→冻豆腐→面→煎蛋；不喝汤",
      "details": [
        { "item": "荞麦面(干)", "amount": "35克" },
        { "item": "冻豆腐", "amount": "80克" },
        { "item": "虾仁", "amount": "80克" },
        { "item": "白菜", "amount": "200克" },
        { "item": "鸡蛋", "amount": "1个" },
        { "item": "食用油", "amount": "5-8克" }
      ],
      "steps": [
        "不粘锅5-8克油，中小火煎蛋至底面焦脆、蛋黄半凝固",
        "水开后先煮冻豆腐和白菜梗1分钟",
        "放荞麦面和虾仁煮3-4分钟，最后放白菜叶",
        "碗底：1勺生抽+半勺蚝油+1勺香醋+少许胡椒粉，舀少量面汤化开",
        "捞出拌匀，煎蛋铺顶"
      ]
    },
    {
      "id": "dinner-weekday",
      "type": "dinner",
      "name": "青椒洋葱炒鸡胸肉（无主食）",
      "time": "18:00",
      "calories": 400,
      "days": [1, 2, 3, 4, 5],
      "reminder": true,
      "note": "先吃青椒洋葱，再吃鸡胸肉",
      "details": [
        { "item": "鸡胸肉", "amount": "150克" },
        { "item": "青椒", "amount": "150克" },
        { "item": "洋葱", "amount": "100克" },
        { "item": "食用油", "amount": "10克" }
      ],
      "steps": [
        "鸡胸肉切片：1勺生抽+半勺淀粉+黑胡椒腌好，周末分装备好",
        "热锅10克油爆香蒜末，炒鸡胸肉至断生盛出",
        "底油炒软洋葱，再下青椒",
        "倒回鸡胸肉，加半勺蚝油大火翻炒1分钟"
      ]
    },
    {
      "id": "snack-afternoon",
      "type": "snack",
      "name": "下午加餐（二选一）",
      "time": "16:00",
      "calories": 100,
      "days": [1, 2, 3, 4, 5, 6, 7],
      "reminder": true,
      "note": "黑咖啡（不加糖奶） 或 水煮蛋1个/纯牛奶1盒"
    },
    {
      "id": "lunch-saturday",
      "type": "lunch",
      "name": "周六快乐日·自由餐（如KFC）",
      "time": "12:00",
      "calories": null,
      "days": [6],
      "reminder": true,
      "note": "热量不固定，吃完后在「加餐」里查询实际热量并记录"
    },
    {
      "id": "dinner-saturday",
      "type": "dinner",
      "name": "周六晚餐·清淡简餐",
      "time": "18:00",
      "calories": 300,
      "days": [6],
      "reminder": true,
      "note": "热牛奶 + 黄瓜/水煮青菜 + 水煮蛋"
    },
    {
      "id": "lunch-sunday",
      "type": "lunch",
      "name": "周日午餐·正常吃面（面条减到20-25克）",
      "time": "12:00",
      "calories": 450,
      "days": [7],
      "reminder": true
    },
    {
      "id": "dinner-sunday",
      "type": "dinner",
      "name": "周日晚餐·清蒸鱼/虾 + 凉拌黄瓜",
      "time": "18:00",
      "calories": 350,
      "days": [7],
      "reminder": true
    }
  ],
  "exercises": [
    {
      "id": "phase1-cardio",
      "name": "适应期·快走训练",
      "time": "18:30",
      "duration": 40,
      "caloriesBurned": 180,
      "days": [1, 3, 5],
      "startDate": "2026-09-01",
      "endDate": "2026-09-30",
      "reminder": true,
      "note": "全程能正常说话；微微出汗即可；腿部酸痛则休息一天",
      "content": [
        { "item": "热身", "detail": "原地踏步或慢走", "minutes": 3 },
        { "item": "有氧", "detail": "户外快走（公园/小区/河边）", "minutes": 30 },
        { "item": "拉伸", "detail": "肩颈 + 大腿后侧 + 小腿，每个动作15-20秒", "minutes": 7 }
      ]
    },
    {
      "id": "phase2-mix",
      "name": "启动期·走跑结合 + 基础力量",
      "time": "18:30",
      "duration": 45,
      "caloriesBurned": 250,
      "days": [1, 2, 4, 5],
      "startDate": "2026-10-01",
      "endDate": "2026-10-31",
      "reminder": true,
      "note": "深蹲/平板支撑二选一交替；关节疼立即停止",
      "content": [
        { "item": "热身", "detail": "慢速高抬腿或慢速开合跳", "minutes": 3 },
        { "item": "有氧", "detail": "走3分钟→慢跑1分钟，循环6组", "minutes": 24 },
        { "item": "力量A", "detail": "徒手深蹲 10个×3组，组间休息30秒（或平板支撑30秒×3组）", "minutes": 8 },
        { "item": "拉伸", "detail": "大腿前后侧、小腿、臀部", "minutes": 7 }
      ]
    },
    {
      "id": "phase3-shape",
      "name": "巩固塑形期·慢跑 + 力量AB组",
      "time": "18:30",
      "duration": 50,
      "caloriesBurned": 300,
      "days": [1, 2, 4, 5, 6],
      "startDate": "2026-11-01",
      "endDate": "2026-12-31",
      "reminder": true,
      "note": "AB两组单次选一组；运动后30分钟内补牛奶或水煮蛋",
      "content": [
        { "item": "热身", "detail": "慢速开合跳或原地小跑", "minutes": 4 },
        { "item": "有氧", "detail": "走2分钟→慢跑3分钟，循环6组", "minutes": 30 },
        { "item": "力量A组", "detail": "臀腿核心：深蹲12个×3组 + 平板支撑45秒×3组", "minutes": 11 },
        { "item": "力量B组", "detail": "上肢核心：俯身划船12个×3组 + 跪姿俯卧撑8-10个×3组", "minutes": 11 },
        { "item": "拉伸", "detail": "全身拉伸（肩背臀腿小腿）", "minutes": 6 }
      ]
    },
    {
      "id": "sunday-stretch",
      "name": "周日·全身拉伸（休息日）",
      "time": "10:00",
      "duration": 10,
      "caloriesBurned": 30,
      "days": [7],
      "startDate": "2026-09-01",
      "endDate": "2027-01-31",
      "reminder": true,
      "note": "周日完全休息，仅做10分钟拉伸"
    }
  ]
}''';

/// AI 计划转换提示词（导入页「AI 生成」模式，作为 system 消息发送）
const String kPlanConvertPrompt = '''你是减脂计划结构化转换助手。用户会提供减脂餐计划和/或运动计划的文档（Markdown、纯文本等任意格式），请把它严格转换为下面的 JSON 格式。

只输出一个 JSON 对象，不要输出任何解释文字，不要 markdown 代码块围栏。

JSON 结构：
{
  "version": "1.0",
  "meta": { "planName": "计划名", "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD", "baseWeight": 起始体重数字, "targetWeight": 目标体重数字, "dailyCalorieTarget": 每日目标摄入kcal, "tdee": 每日总消耗kcal },
  "meals": [
    { "id": "唯一英文id", "type": "breakfast/lunch/dinner/snack四选一", "name": "餐名", "time": "HH:mm", "calories": 热量kcal数字, "days": [1,2,3,4,5], "dates": ["YYYY-MM-DD"], "reminder": true, "note": "备注", "details": [{ "item": "食材", "amount": "用量" }], "steps": ["步骤1", "步骤2"] }
  ],
  "exercises": [
    { "id": "唯一英文id", "name": "训练名", "time": "HH:mm", "duration": 总分钟数字, "caloriesBurned": 消耗kcal数字, "days": [1,3,5], "dates": ["YYYY-MM-DD"], "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD", "reminder": true, "note": "注意事项", "content": [{ "item": "环节名", "detail": "具体内容", "minutes": 分钟数字 }] }
  ]
}

转换规则：
1. days 用数字表示星期几：1=周一 … 7=周日；「周一到周五」= [1,2,3,4,5]；「每天」= [1,2,3,4,5,6,7]；「周六」= [6]
2. meta 中文档没提到的字段直接省略；热量没有明确数据时按营养学常识给出合理整数估算
3. 运动计划分阶段（如适应期/启动期/巩固期）时，每个阶段生成一条 exercise，用 startDate/endDate 表达阶段范围；文档没写具体日期则省略这两个字段
4. 自由餐/作弊餐（热量不固定，如周六KFC）calories 填 null
5. 食材清单表 → details；做法步骤 → steps；训练环节表 → content；注意事项/进食顺序 → note
6. time 用24小时制 HH:mm；文档没写时间的按常识：早餐07:30、午餐12:00、加餐16:00、晚餐18:00、运动18:30
7. 保持文档原意，不要遗漏任何一餐或训练安排；文档只有运动计划就只输出 exercises，只有餐食计划就只输出 meals
8. 文档提到具体日期（如「9月10日」）或按周次/单双周轮换（如「第1、3周周六吃KFC，第2、4周周六吃日式」「单周跑步双周游泳」「隔周一次」）时：把日期换算成具体 YYYY-MM-DD 写入该条目的 dates 数组（用户消息开头给了今天日期，"第N周"从今天所在周起算）；dates 条目不要再填 days/startDate/endDate；轮换的每个单元生成独立条目，覆盖文档提到的完整周期（文档没写周期上限按 3 个月）''';
