# 当日条目快照与历史固化设计：餐食 + 运动（day-snapshot-design.md）

版本：v1.2 ｜ 编写日期：2026-09-03 ｜ 状态：已实现（App v1.0.2，2026-09-03 落地）
对应需求：spec.md F11（v1.5 增补）｜ 上游设计：[design.md](design.md)、[backup-design.md](backup-design.md)、[weight-design.md](weight-design.md)（历史固化哲学同构）
v1.1 变更：运动纳入快照机制（主人 2026-09-03 拍板），DayMealEntry 升级为统一 **DayEntry**（kind 区分餐食/运动），tempTasks 全量退役。
v1.2 变更：**旧备份导入兼容强化**（主人确认）——v1 备份导入管线内直接转换为快照格式（不只依赖启动迁移），消除"换机导入旧备份后历史数据悬空"漏洞；转换核心与启动迁移共用一套函数。
v1.2 实现记录：代码落地于 models/records.dart（DayEntry）、providers/record_provider.dart（syncDayEntries/addDayEntry/updateDayEntry/removeDayEntry/migrateIfNeeded）、utils/legacy_convert.dart（convertLegacyToEntries/sortDayEntries）、utils/calorie_utils.dart（快照路径统计）、widgets/meal_card.dart+exercise_card.dart（快照视图）、pages/today+stats+food、services/backup_service.dart（formatVersion 2 与 v1 转换）、auto_backup_service.dart、providers/plan_provider.dart（计划变更联动）。测试 test/day_snapshot_test.dart（10 例）+ backup_service_test 更新，91 例全绿。

---

## 1. 背景与目标

### 1.1 现状与问题

现有实现中，打卡记录与计划分离，但统计**实时引用计划**：

- 打卡：`checkRecords[date]["meal:<planMealId>"/"exercise:<id>"/"temp:<id>"] = { checkedAt }`，只存时间戳；
- 实际热量：`mealAdjust[date]["meal:<planMealId>"] = { calories, note }`，仅当天覆盖，AI 语境是"计划餐 + 少了/换了什么"；
- 统计：`dailySummary(plan, settings, records, date)` 用 `getTasksForDate(plan, date)` 从**当前计划**投影历史日期的任务列表（餐食与运动都是），再叠加打卡与覆盖值。

由此产生两个与预期不符的行为：

1. **历史随计划漂移**（餐食与运动都存在）：删除计划项、清空计划、覆盖导入后，历史完成度、摄入、运动消耗、缺口全部变动（backup-design FR9.5 风险提示即源于此）；
2. **内容不可改**：计划餐/计划运动的名称内容来自 `MealItem.name` / `ExerciseItem.name`，当日只能覆盖热量与备注，不能改"今天实际吃了什么/练了什么"。

### 1.2 目标（主人原话的需求语义）

- App 餐食默认**早饭/午饭/晚饭**并提供**加餐**；运动同理保留计划项与**临时加练**；
- 导入计划 = 预设食谱/训练表；**计划本质是人提前给自己定的模板**——用了就套用；
- 每天打卡条目固定三字段：
  - 餐食：**食物内容、热量、备注**
  - 运动：**运动内容、消耗热量、备注**
- 计划导入的内容落到当天条目「内容」字段；临时改吃/改练别的时**只改内容**，AI 对新内容**重新测算**热量/消耗；
- **修改即脱钩**：改了内容，当天这一条就清空"来自计划"的身份，变成当天自己的记录，不再跟随计划变化；
- **历史记录绝对固化**：每天的数据一旦落库就是快照，删除/清空/覆盖任何计划，历史记录一点不能变。

### 1.3 非目标（本期不做）

- 不开放修改快照条目的时间与分类（time/slot 跟随计划或录入时刻；运动无分类）；
- 不提供删除"计划来源"快照的入口（避免完成度口径复杂化），只提供"恢复计划内容"复位；手动加餐/加练仍可删除；
- 计划本身的结构（MealItem/ExerciseItem、导入格式 import-format.md）不变——计划仍是完整模板，详情页照旧展示 details/steps/content/duration；
- 不改提醒调度、不改引导页/使用指引。

## 2. 核心概念：计划 = 模板，快照 = 事实

| | 旧模型（引用式） | 新模型（快照式） |
|---|---|---|
| 计划的角色 | 既是模板又是统计口径 | 仅是**模板**：每天实例化一次（餐食+运动同构） |
| 当天条目 | 不存在，渲染时从 plan 现算 | `DayEntry`：内容/热量/备注，落库 |
| 改"吃了什么/练了什么" | 不支持（只能覆盖热量+备注） | 直接改内容，AI 按新内容测算 |
| 条目与计划的关联 | 永久按 id 关联 | 导入时关联，**修改即脱钩** |
| 历史统计 | 实时按当前 plan 投影 → 会漂移 | 只读当日快照 → **永不漂移** |
| 明天是否受今天修改影响 | 否（覆盖仅当天） | 否（每天生成新快照，天然隔离） |
| 临时加餐/加练 | tempTasks 独立列表 | 快照层的 `source != 'plan'` 条目（**tempTasks 退役**） |

一条数据的生命周期：

```
计划项 (MealItem / ExerciseItem)
        │ 当天首次实例化 / 计划变更同步（仅今天）
        ▼
DayEntry（快照，独立于计划）
        ├─ 打卡 → checkRecords（沿用，键空间不变）
        ├─ 改热量/备注 → 快照覆盖（不脱钩）
        └─ 改内容 → detached = true（脱钩，永不跟随计划）
        一旦落库，只属于那一天；计划怎么变都与它无关
```

## 3. 数据模型

### 3.1 新增：DayEntry（lib/models/records.dart 内新增类，替代 v1.0 的 DayMealEntry 草案）

```dart
/// 当日条目快照（v1.5）：计划导入时生成，之后独立于计划；餐食与运动统一模型
class DayEntry {
  String id;            // 快照 id（genId 生成；迁移时沿用 planItemId / temp id）
  String kind;          // 'meal' | 'exercise'
  String slot;          // breakfast|lunch|dinner|snack（餐食来自计划 type 或录入选择；运动为 ''）
  String time;          // HH:mm（来自计划或录入时刻）
  String content;       // 内容文本：食物内容 / 运动内容（计划导入时=计划 name；可自由编辑，多行）
  int? calories;        // kcal：餐食=摄入，运动=消耗；null = 待补录（自由餐/未测算）
  String note;          // 备注（纯用户字段，从不跟随计划）
  String source;        // 'plan' | 'manual' | 'library' | 'ai'
  String planItemId;    // 关联的计划项 id；脱钩后仍保留（供"恢复计划内容"），'' 表示无
  bool detached;        // 是否已与计划脱钩（内容被修改过）
  bool caloriesDirty;   // 热量/消耗是否被用户手改过（false 时同步算法跟随计划值）
}
```

- **打卡状态不放进快照**：`checkRecords` 沿用为打卡状态唯一事实源（键空间 `meal:<planItemId>` / `exercise:<planItemId>` 不变），`toggleCheck`/备份合并逻辑零改动。快照管"内容"，checkRecords 管"状态"。
- **运动不存 duration**：快照三字段之外不带时长；详情回看计划项，AI 测算消耗直接用「运动内容（可含时长描述）+ 备注」文本。
- `detached` 的唯一触发条件是**内容与计划导入值不一致并保存**；只改热量/备注不脱钩（"当日覆盖"语义）。
- `source != 'plan'` 的条目（手动/食物库/AI）即"计划外录入"：加餐与加练统一由此表达。

### 3.2 存储：新顶层键 `dayEntries`

```
dayEntries: { "2026-09-03": [ DayEntry(kind=meal|exercise), ... ] }   // 同 kind 内按 time 升序
```

- `storage_service.dart` 新增 `kDayEntries = 'dayEntries'`；
- **不参与 `_prune()` 的 400 天滚动裁剪**（历史固化是硬需求）。体量估算：每条约 120-150 字节，每天 6-10 条，10 年 ≈ 2-4 MB，可接受（对策见 §10）；
- `RecordStore` 增加 `dayEntries` 字段；`tempTasks` 保留模型与读写（v1 备份/迁移兼容），**新逻辑停写**。

### 3.3 备份格式与旧备份兼容（v1.2 强化）

- 备份快照 9 项（F10 后）→ **10 项**（+`dayEntries`）；`formatVersion: 2`；旧键（checkRecords/mealAdjust/tempTasks/extraFoods/planData）**照常导出**——v2 备份回滚到旧版 App 也能读（旧版忽略 dayEntries 键），双向不锁死；
- **旧备份（v1）导入 = 管线内自动转换为新格式**，详见 §6.1；识别规则：`formatVersion == 2` 或存在非空 `dayEntries` 键 → 按 v2 处理，否则按 v1 转换；
- **导入 v2 备份**：dayEntries 按「同 date 内同 id 合并、新 id 追加、导入优先」并入；旧键照常合并（幂等，无副作用）；
- **导入概要（FR9.4）**：v1 备份显示「旧格式备份，导入后将自动转换为快照格式」提示，转换结果并入概要条数。

## 4. 快照生命周期

### 4.1 实例化与同步算法（核心：syncDayEntries，餐食与运动一套）

```
syncDayEntries(date):
  tasks     = getTasksForDate(plan, date)          // 当天计划餐 + 计划运动
  planItems = tasks.meals.map(kind='meal') + tasks.exercises.map(kind='exercise')
  entries   = dayEntries[date] 或 []

  // ① 保留与刷新
  kept = []
  for e in entries:
      if e.source != 'plan': kept.add(e); continue  // 计划外条目原样保留，永不触碰
      p = planItems.find(id == e.planItemId)
      if p == null:
          if e.detached: kept.add(e)                // 脱钩条目：计划里没了也永久保留
          else: drop(e)                             // 未脱钩且计划里已删 → 移除
      else:
          if !e.detached:
              e.content = p.name; e.time = p.time
              e.slot = (kind==meal) ? p.type : ''
              if !e.caloriesDirty: e.calories = p.calories / p.caloriesBurned
          kept.add(e)                               // detached 条目一字不动

  // ② 追加新条目（餐食与运动同构）
  for p in planItems where planItemId 不在 kept 中:
      kept.add(DayEntry(
        id: p.id, kind: ...,
        slot: (kind==meal) ? p.type : '',
        time: p.time, content: p.name,
        calories: (kind==meal) ? p.calories : p.caloriesBurned,
        note: '', source: 'plan', planItemId: p.id,
        detached: false, caloriesDirty: false))

  dayEntries[date] = kept（同 kind 内按 time 排序）
```

该算法同时覆盖三种情形：

| 情形 | 效果 |
|------|------|
| 某天快照为空 + 当天有计划项 | 全部追加 → **首次实例化** |
| 计划变更（导入/编辑/删除/分模块清空）后对今天再同步 | 未脱钩跟随、失效未脱钩移除、新增追加、**脱钩条目永不动** |
| 换计划整体覆盖导入 | 同上；旧计划的未脱钩条目被移除、脱钩条目保留 |

**触发时机**：

1. App 启动 / 回到前台：`syncDayEntries(today)`；
2. 导入计划成功后（`importPlan` 尾部）、计划项编辑/删除/分模块清空（餐食或运动）后：`syncDayEntries(today)`——只同步今天；历史快照永不触碰；
3. 统计某日详情打开时：若该天（今天以前）无快照且有记录 → 先走 §6 迁移兜底，仍无则按旧口径渲染（理论上迁移后不存在此情形）。

**未来日期不生成快照**（计划可能变），只渲染计划预览。

### 4.2 口径（变化点汇总）

**打卡**：
- 照旧 `toggleCheck(date, 'meal'/'exercise', planItemId)`；今日页以快照条目渲染，打卡键沿用 `meal:<planItemId>` / `exercise:<planItemId>`；
- `source != 'plan'` 条目不打卡：**加餐与加练都是添加即计**（沿用 tempTasks 语义）。

**完成度**（`dailySummary` 快照路径）：
- `taskCount` = 当天 `source=='plan'` 的快照条目数（餐+运动、含 detached、含计划 snack）；
- `doneCount` = 其中已打卡数；**detached 条目仍参与完成度**（它就是"那条计划任务"的当天实际形态）。

**摄入**：
- 正餐与计划 snack 快照：打卡后才计入（沿用现状）；
- `source != 'plan'` 的 snack 快照：添加即计（沿用 tempIntake 语义）；
- `plannedIntake`（顶部"计划摄入"）= Σ plan 餐食快照 calories（null 计 0）。

**运动消耗**：
- plan 运动快照：打卡后计入（沿用 planBurn 语义；`caloriesBurned` 静态计划值 → 快照 calories）；
- `source != 'plan'` 的运动快照（临时加练/补录）：添加即计（沿用 tempBurn 语义）；
- `exerciseBurn` = 两部分之和；**tempIntake/tempBurn 字段由快照路径接管后归零**（统计公式里并入快照计算）。

**其他**：
- `dayActive`（打卡天判定）：增加 `dayEntries[date] 非空` 一项；
- 月历/周图/趋势/月回顾/某日详情：数据源经 `dailySummary`/`dayDetail` 自动获得快照路径，接口签名不变。

### 4.3 编辑弹窗（餐食与运动同构，替代现 `_AdjustSheet`；运动卡新增 ✎ 入口）

```
┌──────────────────────────────────────┐
│ 编辑这一餐 / 编辑这次运动        ✕    │
│ 午餐 · 12:00 / 运动 · 18:30 [已改]   │
│ ┌──────────────────────────────────┐ │
│ │ 内容（多行输入）                  │ │
│ │ 冻豆腐虾仁荞麦面 → 「外卖黄焖鸡」 │ │
│ │ 适应期·快走40分钟 → 「慢跑5公里」 │ │
│ └──────────────────────────────────┘ │
│ [✨ AI 测算]   [热量/消耗输入框 kcal] │
│ AI 拆解：黄焖鸡米饭≈640 kcal          │
│ 备注（可选）：＿＿＿＿＿＿             │
│ [恢复计划内容]（仅脱钩且计划项在时）   │
│ [保存]  [保存并打卡]                  │
└──────────────────────────────────────┘
```

- 打开时：内容 = 快照当前 content；热量 = calories（空=待补）；备注 = note；
- 「✨ AI 测算」：餐食走 `estimateMeal`、运动走 `estimateBurn`（见 §5），对**当前内容 + 备注**测算，回填并展示拆解；
- 保存语义：
  - content 与快照原值不同 → `detached = true`（弹窗内文案提示："修改后这一条不再跟随计划"）；
  - calories 被改 → `caloriesDirty = true`；
  - 「保存并打卡」：保存后未打卡则自动打卡（仅 plan 来源条目）；
- 「恢复计划内容」：仅 `detached == true` 且 `planItemId` 仍存在于计划中时显示；一键复位 content/热量为计划值、note=''、detached=false、caloriesDirty=false；
- 计划外条目（加餐/加练）同一弹窗可编辑，无「恢复计划内容」。

## 5. AI 测算改造

### 5.1 Prompt 调整（ai_service.dart）

- `kMealEstSys`：从「计划餐 + 少了/换了什么」的预设语境改为**通用单餐测算**——"用户描述这一餐实际吃了什么（可能是完整菜名/口语描述/带份量备注），估算总热量"，输出 `{calories, detail}` 不变；
- `kBurnEstSys`：保留消耗估算与个人资料结合（F10 FR10.6 的性别/年龄/身高/体重扩展**不变**），用户输入侧从"一句话描述"改为快照的「运动内容（+备注）」——内容文本本身可含时长/距离/强度描述；
- `queryCalorie`（食物库搜索/加餐 AI 查询）不动。

### 5.2 调用链变化

| 场景 | 旧行为 | 新行为 |
|------|--------|--------|
| 计划餐 ✎ | 大白话 → AI 估"这餐实际多少" → 覆盖热量 | 改内容（可选）→ AI 对新内容测算 → 回填；只作用于快照 |
| 自由餐（calories=null）补录 | ✎ 弹窗大白话估算 | 编辑弹窗 AI 按内容测算（预填计划 name，可改） |
| 计划运动 ✓ 前后 | 无编辑入口，消耗=计划静态值 | ✎ 打开编辑弹窗：改运动内容 → AI 按新内容（结合体重资料）测算消耗 → 回填 |
| 加餐（今日页/统计页补录） | queryCalorie/手动 → addTempTask | → addDayEntry(kind='meal', slot='snack', source=…) |
| 加练/补录锻炼 | estimateBurn → addTempTask(type='exercise') | estimateBurn → addDayEntry(kind='exercise', source=…) |

## 6. 旧数据 → 快照：一套转换核心，两个触发点（v1.2）

**目标**：任何路径进入的数据（本机存量 / v1 备份导入）最终都以快照格式落库；旧格式永不直接"不可用"。

### 6.1 转换核心：convertLegacyToEntries()（共用函数）

输入一组旧格式数据（plan 投影源 + checkRecords + mealAdjust + tempTasks + extraFoods），输出 `{ date: [DayEntry] }`。**启动迁移与 v1 备份导入都调用它**，保证两处逻辑永不漂移：

```
convertLegacyToEntries(planSrc, checks, adjusts, temps, extras):
  // planSrc = 用于投影的计划数据（启动迁移传本机 plan；v1 备份导入传备份内 planData）
  // 先做 extraFoods → tempTasks 的旧迁移（复用现有 _migrateExtraFoods 逻辑，纯内存）
  dates = ∪(checks.keys, adjusts.keys, temps.keys)
  out = {}
  for date in dates (升序):
      entries = []
      // ① 计划餐 → 快照（当天计划投影；含未打卡项）
      for m in getTasksForDate(planSrc, date).meals:
          adj = adjusts[date]?["meal:${m.id}"]
          entries.add(DayEntry(id: m.id, kind:'meal', slot: m.type, time: m.time,
            content: m.name, calories: adj?.calories ?? m.calories, note: adj?.note ?? '',
            source:'plan', planItemId: m.id, detached: false,
            caloriesDirty: adj != null))
      // ② 计划运动 → 快照
      for e in getTasksForDate(planSrc, date).exercises:
          entries.add(DayEntry(id: e.id, kind:'exercise', slot:'', time: e.time,
            content: e.name, calories: e.caloriesBurned, note: '',
            source:'plan', planItemId: e.id, detached: false, caloriesDirty: false))
      // ③ tempTasks 全量 → 计划外快照（加餐与临时加练）
      for t in temps[date]:
          entries.add(DayEntry(id: t.id, kind: t.isExercise ? 'exercise' : 'meal',
            slot: t.isExercise ? '' : 'snack', time: t.time,
            content: t.name, calories: t.calories, note: '',
            source: t.source, planItemId: '', detached: true, caloriesDirty: true))
      out[date] = entries（同 kind 内按 time 排序）
  return out
```

转换规则要点：

- **打卡状态不转换**：checkRecords 在 v1/v2 格式中同构，照常按 checkedAt 合并即可（快照条目 id 与打卡键 `meal:<id>`/`exercise:<id>`/`temp:<id>` 天然对应）；
- **plan 投影之外的覆盖值**：mealAdjust 里存在、但 planSrc 当天投影中找不到的 id → 跳过（现状统计同样不可见这些值，不引入退化，如实记录在导入概要的转换说明中）；
- **只在有记录的天转换**：无记录的历史日期没有"数据"可固化（统计显示无数据，与现状一致）；未来/未到达日期永不生成；
- **幂等**：同输入重复转换结果一致；转换产物并入 dayEntries 走「同 id 合并、导入优先」，重复导入同一份 v1 备份不产生重复条目。

### 6.2 触发点一：升级后首启迁移（本机存量）

```
migrateToDayEntries():   // 幂等：dayEntries 非空或 dataVersion ≥ 2 则跳过
  out = convertLegacyToEntries(本机 plan, 本机 checkRecords/mealAdjust/tempTasks/extraFoods)
  写入 dayEntries + dataVersion = 2
```

- 迁移后 `checkRecords` 继续照常读写（打卡状态源，备份兼容）；`mealAdjust` 与 `tempTasks` **停写**（旧数据保留不删，v1 备份合并逻辑保留）；
- **固有限制（如实声明）**：历史某天的"当时计划"不可考，迁移用的是**当前计划对历史日期的投影**——若用户中途换过计划，历史内容按当前计划呈现。这不是迁移引入的退化（现状统计同样如此），迁移只是把现状固化，此后不再漂移；
- 与 `startedAt`、`earliestCheckDate`、`baseBurnForDate`（F10 按日沿用基础消耗）无冲突，互不依赖。

### 6.3 触发点二：v1 备份导入（换机/重装/双设备，v1.2 新增）

v1 备份**不再依赖启动迁移兜底**，导入管线内直接转换：

```
导入 v1 备份（增量 / 覆盖通用）:
  1. 解析校验通过后，从备份数据取 planData（备份自带，与本机 plan 无关）
  2. legacyEntries = convertLegacyToEntries(备份 planData, 备份 checkRecords/mealAdjust/tempTasks/extraFoods)
  3a. 增量导入：legacyEntries 按「同 date 内同 id 合并、新 id 追加、导入优先」并入本机 dayEntries；
       备份旧键照常合并（checkRecords 按 checkedAt 取新 / mealAdjust·tempTasks 按 id 导入优先 / planData 走 importPlan）
  3b. 覆盖导入：dayEntries = legacyEntries 整体替换（其余 9 项按现有覆盖规则替换）
  4. 导入概要（FR9.4）显示「旧格式备份，已自动转换为快照格式」+ 转换后条数
```

- **换机场景验证**：新装 App（dayEntries 空）→ 导入 v1 备份 → 历史全部进快照 → 统计页立即正确且固化，之后再删/换计划历史不动；
- 用**备份内 planData** 投影（不是本机 plan）——备份的历史必须按备份自己的计划还原，否则覆盖导入前转换会用错计划；
- v2 备份走现有路径（dayEntries 直接合并），无需转换；
- FR9.5 原有的「可能导致历史日期热量统计变化」风险提示，对 v1 备份在本方案下**降级消失**（转换后历史固化，不再随本机计划漂移）；对 v2 备份同样不再需要——两处提示文案更新。

### 6.4 边界情况

| 情况 | 处理 |
|------|------|
| 备份内 planData 缺失/为空 | 仅 tempTasks/extraFoods 有记录的日期生成计划外条目；plan 投影条目无从生成（该备份本就无计划，与现状一致） |
| mealAdjust 覆盖值找不到对应计划项 | 跳过（现状统计亦不可见），概要注明转换跳过数 |
| 同一 v1 备份重复导入 | 转换产物按 id 合并、导入优先，幂等不重复 |
| v1 备份导入后又导入 v2 备份 | dayEntries 与旧键都按各自规则合并，互不冲突 |
| 旧版 App 读 v2 备份 | 忽略 dayEntries 未知键，旧键数据完整可用（双向不锁死） |

## 7. 页面与交互改动

### 7.1 今日页（today_page.dart）

- 餐食区与运动区均改为渲染 `dayEntries[today]`（按 kind 分组，同组按 time 排序），不再从 `getTasksForDate` 现算；
- 页面 build 前（initState / AppProvider.refreshToday）确保 `syncDayEntries(today)` 已执行；
- "＋ 今日加餐"入口不变 → FoodAddPage 保存改 `addDayEntry(kind='meal', slot='snack')`；
- "＋ 今日运动"弹窗保存改 `addDayEntry(kind='exercise', source='manual'/'ai')`。

### 7.2 餐卡（meal_card.dart）

- 中栏主行显示**食物内容**（最多 2 行，替代 meal.name）；detached 时类型 tag 旁加「已改」小标（橙色）；
- 子行：
  - 未脱钩且有计划热量：`{calories} kcal`（+ 备注/计划 note 摘要）——与现状一致；
  - 未脱钩但热量被覆盖：`实际 {cal} kcal` + 划线计划值——与现状一致；
  - 脱钩：只显示 `{calories} kcal` + 备注，**不再显示划线计划值**；
  - calories=null：保留「自由餐/待补录」提示；
- ✎ 对全部餐食快照可用；加餐快照保留 ✕ 删除。

### 7.3 运动卡（exercise_card.dart）

- 中栏主行显示**运动内容**（替代 exercise.name）；detached 时「已改」小标；
- 子行：`消耗 {cal} kcal`（+ 备注摘要）；未脱钩时展示计划值语义与现状一致；
- **新增 ✎ 编辑入口**（打开 §4.3 运动编辑弹窗）；计划外快照保留 ✕ 删除；打卡圆圈沿用（手动条目不打卡）。

### 7.4 统计页（stats_page.dart）

- 某日详情的餐食/运动列表从快照生成；「补录加餐 / 补录锻炼」弹层保存改 `addDayEntry(date, kind, source)`（支持历史日期补录，补录即固化）；
- 月历/周图/趋势/月回顾经 `dailySummary` 自动走快照路径。

### 7.5 计划页与详情页

- 不变（计划仍是完整模板；详情页继续展示 details/steps/content/duration/note）。

## 8. 代码改动清单（对齐"最小改动"惯例）

| 文件 | 改动 |
|------|------|
| `models/records.dart` | 新增 `DayEntry`；`RecordStore` 增 `dayEntries` 字段与序列化 |
| `services/storage_service.dart` | 增 `kDayEntries` 常量 |
| `providers/record_provider.dart` | 增 `syncDayEntries` / `addDayEntry` / `updateDayEntry` / `removeDayEntry` / `migrateToDayEntries` / **`convertLegacyToEntries`（转换核心，§6.1）**；`_persistAll`/`_prune`（dayEntries 不裁剪）/备份合并/覆盖替换补 dayEntries；`addTempTask`/`removeTempTask` 保留（兼容）但 UI 入口全部改走 DayEntry |
| `providers/plan_provider.dart` | `importPlan`/`updateItem`/`removeItem(s)`/`clearMeals`/`clearExercises` 尾部回调 `syncDayEntries(today)`（构造注入或事件通知） |
| `utils/calorie_utils.dart` | `dailySummary`/`dayDetail`/`dayActive` 增加快照路径（旧口径保留为 fallback） |
| `services/ai_service.dart` | `kMealEstSys` 文案改通用单餐测算；`kBurnEstSys` 不变（输入侧换内容文本）；函数签名均不变 |
| `pages/today/today_page.dart` | 餐食区+运动区改渲染快照；`_AdjustSheet` → 三字段编辑弹窗（餐/动同构，含 AI 测算/恢复计划内容）；运动卡加 ✎ |
| `widgets/meal_card.dart` | 主行显示 content、「已改」标记、子行脱钩样式 |
| `widgets/exercise_card.dart` | 同上（运动内容/已改/消耗/备注），加 ✎ |
| `pages/food/food_add_page.dart` | 保存改走 `addDayEntry(kind='meal')`（source 映射保留） |
| `pages/stats/stats_page.dart` | 补录弹层改走 `addDayEntry(date, kind, source)`；某日详情列表走快照 |
| `services/backup_service.dart` | formatVersion 2：导出含 dayEntries（旧键照常导出，双向兼容）；导入 v2 合并；**v1 导入管线内调 convertLegacyToEntries 转换**（备份 planData 投影）；概要与提示文案更新 |
| `services/auto_backup_service.dart` | 快照序列化补 dayEntries；dayEntries 变更计入防抖信号 |
| `main.dart`（或 app_provider） | 启动时执行 `migrateToDayEntries()` → `syncDayEntries(today)` |

不改动：提醒调度（reminder_service）、计划模型（plan_data.dart）、导入校验（plan_utils.dart 校验部分）、onboarding、guide、体重记录（F10）。

## 9. 风险与限制

1. **迁移的投影偏差**：换过计划的老用户，历史内容按当前计划投影固化（§6 已声明；现状本就如此）；
2. **存储增长**：dayEntries 永久保留，10 年 ≈ 2-4 MB 量级；若未来超预期，可加"归档压缩"（把 2 年前的天合并为 `{date, intake, burn, deficit}` 摘要行），本期不做；
3. **双层一致性**：打卡状态在 checkRecords、内容在 dayEntries。计划来源条目不可删（无悬空打卡键）、计划外条目删除联动清键（沿用 removeTempTask 联动逻辑）；覆盖导入 v2 备份整体替换两侧，一致性由备份原子性保证；
4. **AI 测算输入变化**：新 prompt 对"计划原样"的测算结果可能与旧 prompt 略有差异（估算类语义，可接受）；热量/消耗仍可手改，AI 仅辅助；
5. **tempTasks 退役灰度**：旧数据保留、v1 备份合并逻辑保留；若迁移后发现遗漏场景，tempTasks 读取兼容可快速兜底。

## 10. 验收要点（速览）

1. 导入计划 → 今日页出现早/午/晚（+计划加餐）与计划运动条目：内容 = 计划名，热量/消耗 = 计划值；
2. 改某餐内容为"外卖黄焖鸡米饭"→ AI 测算回填 → 卡片「已改」、无划线计划值、打卡计入新热量；
3. 改某运动内容为"慢跑 5 公里"→ AI 按内容+体重资料测算消耗 → 回填；打卡计入新消耗；
4. 删除计划项（餐或运动）/ 清空计划 / 覆盖导入新计划：**今天**脱钩条目保留、未脱钩失效条目消失、新增条目出现；
5. 上述任何操作后，**历史日期**（任意天详情 + 月历 + 趋势 + 月回顾）的完成度、摄入、运动消耗、缺口与操作前**逐项一致**；
6. 明天打开：各条恢复计划内容（今天的修改不影响明天）；
7. 升级安装老数据：历史打卡天数/摄入/消耗/缺口与升级前一致（迁移前后对比）；临时加餐/加练全部出现在快照层；
8. **旧备份兼容（v1.2）**：① 新装 App 导入 v1 老备份 → 历史全部进快照，统计立即正确；随后删除/清空/覆盖计划，历史逐项不变；② 同一 v1 备份重复增量导入不产生重复条目；③ v2 备份在旧版 App 上可读（旧键完整）；
9. 清空所有计划后：历史记录完整可查（F6.6「打卡记录保留」语义升级为"历史完全固化"）；
10. 统计页历史日期补录加餐/锻炼 → 写入该日快照、即计缺口、不参与完成度。
