# 技术设计方案（design.md）

版本：v2.0 ｜ 配套：[spec.md](spec.md) ｜ [import-format.md](import-format.md) ｜ [weight-design.md](weight-design.md) ｜ [backup-design.md](backup-design.md)
> v2.0（2026-09-03）：项目已从 uni-app 整体迁移至 **Flutter**，本文按 `lib/` 实际代码重写，数据格式与交互同 uni-app 版保持 1:1 兼容。uni-app 时代方案（v1.x：HBuilderX / plus.push / 云打包等）见 git 历史归档。
> v1.1（2026-09-01）：首次使用引导 & 使用指引（第 15 章）。

---

## 1. 技术选型总览

| 层 | 选型 | 理由 |
|----|------|------|
| 框架 | Flutter（Dart SDK ^3.12） | 性能与长期维护优于 uni-app；1:1 兼容旧版数据格式与交互 |
| 状态管理 | `provider ^6.1.2`（ChangeNotifier 单例） | 贴近旧版 reactive store 风格；6 个 Provider 覆盖全部状态 |
| 本地存储 | `shared_preferences ^2.3.3`（8 个 JSON 字符串键） | 单机应用，数据量小（< 几百 KB）；键名与旧版 uni storage 完全一致，老数据可直接水合 |
| 本地提醒 | `flutter_local_notifications ^18.0.1` + `timezone ^0.10.0` | zonedSchedule 注册到系统 AlarmManager，**重启后调度自动恢复**（旧版 plus.push 做不到）；支持精确闹钟 |
| 网络 | `dio ^5.7.0`（仅 AI 请求出网） | 拦截器/超时/重试成熟；除用户自配 AI endpoint 外无任何出网请求 |
| 备份文件 | `file_picker`（SAF 选文件）+ `share_plus`（系统分享）+ `path_provider`（应用目录）+ MethodChannel/MediaStore（Download 直写） | 安卓 10+ 免权限写 Download；兼容旧版 .dat/.txt 备份 |
| UI | Material（`useMaterial3: false`）+ 手写组件（`lib/theme/app_theme.dart`） | 复刻旧版配色与交互；无第三方 UI 库，包体小、样式可控；图表纯自绘（无 echarts 类依赖） |
| AI 热量查询 | OpenAI 兼容 `chat/completions`，用户自配 Key（**DeepSeek 默认**/Kimi/MiMo/MiniMax/自定义） | 免后端零成本 |
| 目标平台 | Android APK（主要）；iOS 工程保留可构建 | 个人自装，不上架应用商店 |

## 2. 总体架构

```
┌──────────────────────────────────────────────────────┐
│ 页面层  MainShell(IndexedStack 4 Tab)                  │
│   today / plan / stats / settings                     │
│   + food_add / import / item_detail / backup          │
│   + ai_config / onboarding / guide                    │
├──────────────────────────────────────────────────────┤
│ 状态层  Provider（ChangeNotifier，变更即持久化）           │
│   AppProvider（UI 态）      UsageProvider（AI 用量）     │
│   SettingsProvider         RecordProvider（打卡记录）    │
│   PlanProvider（计划）      OnboardingProvider（引导）    │
├──────────────────────────────────────────────────────┤
│ 服务层                                                │
│   utils/plan_utils.dart    计划校验/归一化/当日任务        │
│   utils/calorie_utils.dart 热量缺口/统计聚合              │
│   utils/date_utils.dart    日期与星期工具                │
│   services/reminder_service.dart      提醒调度           │
│   services/ai_service.dart            AI 请求+容错解析     │
│   services/backup_service.dart        备份导出/导入/合并   │
│   services/auto_backup_service.dart   本地自动备份         │
├──────────────────────────────────────────────────────┤
│ 数据层                                                │
│   shared_preferences（8 个存储键，唯一持久化点）           │
│   data/food_db.dart    内置食物库 82 条（离线）           │
│   data/templates.dart  格式说明/示例/AI 提示词           │
│   data/guide_articles.dart 使用指引内容源（8 篇图文）      │
│   网络：仅 ai_service.dart 出网（用户自配 endpoint）       │
└──────────────────────────────────────────────────────┘
```

数据流向：页面 `context.watch/read` Provider → Provider 方法内变更状态并同步 `StorageService.writeMap` → `notifyListeners()` 驱动 UI 重建。启动时序（`main.dart`）：`StorageService.init()` → `ReminderService.init()` → 创建 6 个 Provider 并装配 → `AutoBackupService.attach()`（数据变更防抖监听）→ `reminder.onLaunch()`（兜底重算当天/次日提醒）→ `runApp`。

提醒调度在启动、导入/生成计划后、设置变更后触发，与页面解耦。

## 3. 目录结构

Flutter 工程位于仓库根目录：

```
lib/
├── main.dart                    # 入口：初始化存储/提醒 → MultiProvider 装配 → MaterialApp(home: MainShell)
├── theme/
│   └── app_theme.dart           # AppColors 色板 + AppTheme + 通用组件（AppCard/Tag/PrimaryButton/EmptyState 等）
├── models/
│   ├── plan_data.dart           # PlanData/PlanMeta/MealItem/ExerciseItem/DetailItem/ContentItem
│   ├── records.dart             # RecordStore：checkRecords/mealAdjust/tempTasks/extraFoods 四个 Map
│   ├── settings.dart            # AppSettings + AiConfig + kAiProviders 预设 + kRetiredModelMap
│   └── onboarding.dart          # 引导状态 { done, profile }
├── providers/
│   ├── app_provider.dart        # 全局 UI 态：activeTab / todayKey（跨天刷新）/ focusKey（通知定位）
│   ├── plan_provider.dart       # 计划 CRUD/导入/清空，变更后联动提醒调度
│   ├── record_provider.dart     # 打卡/临时任务/热量调整，变更后联动通知
│   ├── settings_provider.dart   # 设置读写/估算器/AI 配置，变更后联动重调度
│   ├── usage_provider.dart      # AI 用量统计（calls/tokens/费用）
│   └── onboarding_provider.dart # 首启判定 shouldOnboard / isLegacyUser / 完成与跳过
├── services/
│   ├── storage_service.dart     # shared_preferences 封装（8 键常量 + readMap/writeMap）
│   ├── reminder_service.dart    # flutter_local_notifications 调度（单例）
│   ├── ai_service.dart          # AI 请求 + 提示词 + 容错解析 + 用量埋点（单例）
│   ├── backup_service.dart      # 备份编解码/校验/合并/Download 读写（单例）
│   └── auto_backup_service.dart # 自动备份：防抖 15s + 退后台即写 + 冷启动兜底 + 开关门禁
├── utils/
│   ├── plan_utils.dart          # validateRaw/normalizePlan/getTasksForDate/genId（与旧版 plan.js 1:1）
│   ├── calorie_utils.dart       # baseBurn/dailySummary/streakDays/weekData/monthData/trendData/dayDetail/monthReview
│   └── date_utils.dart          # todayStr/parseDate/addDays/weekday 工具
├── data/
│   ├── food_db.dart             # 内置食物库 82 条（FoodItem）
│   ├── templates.dart           # kFormatBrief/kAiPrompt/kExample（与 import-format.md 同源）
│   └── guide_articles.dart      # 使用指引 8 篇图文内容源
├── widgets/
│   ├── meal_card.dart           # 餐食卡片（含打卡）
│   ├── exercise_card.dart       # 运动卡片（含打卡）
│   ├── calorie_summary.dart     # 今日热量汇总卡
│   ├── ai_config_sheet.dart     # AI 配置弹层（showAiConfigSheet + ensureAiConfigured 前置校验）
│   └── plan_item_edit.dart      # 计划条目全量编辑器（导入预览/详情页共用底部弹层）
└── pages/
    ├── main_shell.dart          # 主壳：IndexedStack 4 Tab + 底部导航 + 首启引导拦截
    ├── today/today_page.dart    # Tab：今日（打卡/缺口/加餐/加练）
    ├── plan/plan_page.dart      # Tab：计划（餐食/运动管理、导入与引导入口）
    ├── stats/stats_page.dart    # Tab：统计（周图/月历/趋势/日详情/月回顾）
    ├── settings/settings_page.dart  # Tab：设置（热量/提醒/AI/数据与计划/帮助/关于）
    ├── settings/backup_page.dart    # 导入备份（概要/增量/覆盖/自动备份恢复卡）
    ├── settings/ai_config_page.dart # AI 配置页
    ├── food/food_add_page.dart  # 加餐录入（食物库/AI/手动）
    ├── import/import_page.dart  # 导入计划（AI 生成 / 手动 JSON 双模式 + 预览确认）
    ├── item/item_detail_page.dart   # 计划项详情（食材/步骤/训练内容/单项提醒开关/编辑/删除）
    ├── onboarding/onboarding_page.dart  # 首次使用引导（Step0~5，含页内 AI 配置弹层）
    └── guide/guide_page.dart    # 使用指引：列表 + 详情两态
```

## 4. 导航与路由

- `MaterialApp(home: MainShell)`；MainShell 用 `IndexedStack` 常驻 4 个 Tab 页（切 tab 零重载、状态保留），底部导航为自绘组件（emoji 图标 🏠📋📊⚙️，对应旧版 tab-bar.vue）。
- 子页面统一走 `AppRoutes.fade(page)`（`PageRouteBuilder` 160ms 淡入，替代 MaterialPageRoute 默认 300ms 位移动画——低端机观感更轻快）：加餐录入、导入计划、计划项详情、备份导入、AI 配置、引导页、指引页。
- 首启拦截：`MainShell.initState` 的 `addPostFrameCallback` 中 `OnboardingProvider.shouldOnboard()` 命中 → `push(OnboardingPage)`（老用户升级由 isLegacyUser 豁免，不弹）。
- 通知点击定位：flutter_local_notifications 回调解析 payload `{"focus":"meal:xxx"}` → `NotificationTapBus.focus` → 首帧后 `AppProvider.onNotificationTap(focus)` 切到今日页并高亮对应卡片。

## 5. 页面信息设计

### 5.1 今日页（默认首页）

```
┌──────────────────────────────┐
│ 8月27日 周四        3/5 已完成 │
│ ┌──────────────────────────┐ │
│ │ 热量汇总卡                 │ │
│ │  缺口 +620 kcal（绿）      │ │   ← 大数字：缺口
│ │  目标1400 | 已摄入780      │ │
│ │  消耗2000 | 运动+180      │ │   ← 基础消耗 + 打卡运动消耗
│ └──────────────────────────┘ │
│ 今日餐食                       │
│ ┌ 🍚 12:00 冻豆腐虾仁荞麦面…  ✓打卡 │
│ │ 🍽 18:00 青椒洋葱炒鸡胸肉  ✓打卡 │
│ └ ...                        │
│ 今日运动                       │
│ ┌ 🏃 18:30 适应期·快走 40min ✓打卡 │
│ └ ...                        │
│ ＋ 今日加餐（虚线按钮）           │
└──────────────────────────────┘
```

- 打卡点击即生效（对勾 + 变色），再点取消（仅当日）；打卡后汇总卡热量实时重算。
- 卡片点击 → 计划项详情页（食材/步骤/训练内容/单项提醒开关/删除单项）。
- ✎ 调整当日实际热量：弹窗手填或 AI 估算（没吃到计划的量时用）；仅当天生效。
- 自由餐（calories:null）打卡后提示「记得记录实际热量」并可跳转加餐页。
- 临时加餐/临时锻炼（加练）：添加即计入当日缺口，仅当天有效，不参与完成度。
- 跨天停留：`AppProvider.refreshToday()` 驱动今日页刷新为新一天。

### 5.2 计划页

- 顶部：当前计划卡片（名称、时间段、基础→目标体重、每日目标热量、计划开始日）。
- 子 Tab 切换：餐食 / 运动，按时间排序列出全部计划项（星期徽标如「一三五」）。
- 每项可点进详情；详情页可「编辑」整项（弹 `widgets/plan_item_edit.dart`：餐食=名称/类型/时间/热量/食材清单/做法步骤/备注，运动=名称/时间/时长/预计消耗/训练内容/注意事项；保存走 `PlanProvider.replaceItem` → 提醒重排 + 今日未脱钩快照跟随）；也可删除单项（写入 `deletedIds`，不回写 JSON）。
- 底部：「＋ 导入计划」（进导入页）等主操作；分模块清空入口（跟随子 Tab）。

### 5.3 导入页

1. 双模式切换：**AI 生成**（粘贴计划文档 → AI 转 JSON）｜ **手动 JSON**（粘贴/选择 .json 文件，`file_picker`）。
2. 「解析校验」→ 错误：中文错误列表（定位第 N 条/字段，`validateRaw`）；成功 → 预览。
3. 预览卡：meta 摘要（计划名/时间段/目标摄入）+ 条目列表 + 实时统计（摄入Σ/消耗Σ/预计缺口）；提示「增量合并现有计划（同 id 更新，新增追加）」。每个条目行内直接展示完整细节（餐食=食材清单/做法步骤/备注，运动=训练内容各环节·分钟/注意事项），点条目弹全量编辑器逐条调整、✕ 删除；**预览中所有增删改在确认导入时生效（确认导入以预览数据 `plan.toJson()` 为准，而非原始 raw——避免「编辑后导入仍是原样」）**。
4. 「确认导入」→ `PlanProvider.importPlan`（normalize + 增量合并 + 吸收 meta）→ 立即重调度提醒 → 跳转今日页。
5. AI 生成未配 Key 时弹统一 AI 配置弹层（`ensureAiConfigured`），配置后原操作继续。

### 5.4 模板与格式说明

- 格式说明 / 完整示例 / AI 生成提示词三个数据块由 `data/templates.dart` 承载（与 import-format.md 同源，内容与旧版 template.js 完全一致），供 AI 生成模式与提示词组装复用。
- 旧版独立「模板查看页」在 Flutter 版未保留独立路由；格式要求已内嵌在导入页 AI 模式与提示词中，用户无需自行拼提示词。

### 5.5 加餐录入页

```
┌──────────────────────────────┐
│ [搜索食物：香辣鸡腿堡…]        │ ← 本地库即时过滤（name/alias/tags）
│ 内置库结果                     │
│  香辣鸡腿堡套餐  ≈1100 kcal [＋] │
│  —— 没找到？ [AI 查询热量]     │ ← 需已配置 API（ensureAiConfigured）
│ AI 结果（可编辑热量）           │
│  黄焖鸡米饭(大份) [780] [确认记录] │
│ 手动录入                       │
│  名称[____] 热量[___kcal] [记录] │
└──────────────────────────────┘
```

来源标记：`db`（食物库）/ `ai`（AI 查询）/ `manual`（手动），随临时任务入库。

### 5.6 统计页

- 顶部：连续完成 X 天 ｜ 累计完成 Y 天。
- 本周：7 列，每列显示完成度 n/m + 缺口数字，着色同 FR4.6。
- 月历：格子按完成率着色（浅绿=部分 / 深绿=全部 / 灰=无数据）；未来或今天已排计划未打卡 → 空心绿圈「待开始」；计划开始日（`meta.startedAt`）绿点标记，开始前视为无计划（`getTasksForDate` 直接返回空任务）。
- 近 14 天缺口条形图（0 轴基线，正向上绿、负向下橙红）。
- 某日详情弹层：月历/周图点任意一天（含未来）→ `dayDetail(date)`，顶部三格（完成度 n/m、已摄入、缺口）+ 逐项清单（计划餐✓/○与实际热量及备注、临时加餐＋来源徽标、运动消耗；未打卡行置灰）；未来日期：标题「未开始」、摄入 —、缺口「待开始」；开始前显示「计划开始前，无统计数据」；近 3 天（前天～今天）支持补打卡/补录/删除临时记录，更早只读。
- 月回顾弹层：顶部三格（计划完成天数、总缺口、日均缺口）+ 两卡片「消耗最多的一天 / 摄入最多的一天」（缺口正绿/负橙；消耗最多的一天附「基础 X + 运动 Y」拆分）；「查看详情 ›」在回顾层之上叠加日详情；只统计开始日后、今天之前有记录的日子。

### 5.7 设置页（分组列表）

```
热量
├── 每日基础消耗 / 每日目标摄入（仅展示行）
├── 基础信息摘要行（性别/年龄/身高/体重/活动量，与引导共用 onboardingState.profile）
└── 「更新数据」→ 估算器弹层（性别/身高/体重/年龄/活动系数 → BMR，可重新估测）
提醒
├── 总开关 / 提前量（0/5/10/15/30 分钟）
└── 通知权限状态与申请按钮 / 省电白名单引导
AI 查询
├── 服务商（DeepSeek/Kimi/MiMo/MiniMax/自定义，自动填 endpoint 与默认模型）
├── API Key（密码框）/ 模型名 / 测试连接 / 余额查询
数据与计划
├── 导出历史数据备份 (.txt) ›
├── 导入历史数据备份 ›
├── 自动备份 [开关]（副标题注明保存到系统 Download 目录）
├── 清空打卡与加餐记录 ›
├── 清空餐食计划（N 项）› / 清空运动计划（N 项）›
└── 清空全部数据（红色，二次确认 + 留底）
帮助
└── 📖 使用指引（图文教程 N 篇）›
关于
└── 版本号（当前 1.0.0）/ 格式版本 1.0
```

- 估算器保存时把基础信息一并持久化到 `onboardingState.profile`，与引导 Step1 共用同一份口径（`estimateBmr`）。
- 版本号当前在设置页与备份 `appVersion` 字段中硬编码（随 pubspec 版本更新，见 weight-design.md §8）。

## 6. 数据模型

### 6.1 计划项（models/plan_data.dart，与 import-format.md 一致）

```dart
class MealItem {
  String id;              // 缺省 genId('m')：前缀-时间戳36进制-随机36进制（与 JS 版同构）
  String type;            // breakfast | lunch | dinner | snack
  String name;
  String time;            // "HH:mm"
  int? calories;          // null = 自由餐
  List<int> days;         // 1-7，空数组=每天
  List<String> dates;     // 具体日期数组（命中优先于 days/范围）
  bool reminder;          // 默认 true
  String note;
  List<DetailItem> details;   // {item, amount}
  List<String> steps;
  String startDate, endDate;  // 空 = 不限
}
class ExerciseItem {
  String id; String name; String time;
  int duration;           // 分钟 1-600
  int caloriesBurned;     // 默认 0
  List<int> days; List<String> dates;
  String startDate, endDate;
  bool reminder; String note;
  List<ContentItem> content;  // {item, detail, minutes}
}
class PlanData {
  String version;         // "1.0"
  PlanMeta meta;          // planName/startDate/endDate/baseWeight/targetWeight/dailyCalorieTarget/tdee + startedAt(首次导入日)
  List<MealItem> meals;
  List<ExerciseItem> exercises;
  List<String> deletedIds;    // 本地单项删除标记
}
```

校验与归一化（`plan_utils.dart`）对 AI 输出做了容错：数字字符串、带秒时间、中文 type（「早餐」等）均自动纠正；`normalizePlan` 补默认值并按 id 去重。

### 6.2 存储键（storage_service.dart，与旧版 uni storage 完全一致）

| 键 | 常量 | 结构 |
|----|------|------|
| `planData` | kPlan | PlanData；meals/exercises 空数组表示无该类计划 |
| `checkRecords` | kCheckRecords | `{ "2026-08-27": { "meal:lunch-weekday": { checkedAt: 1724... } } }` 键=`类型:id` |
| `mealAdjust` | kMealAdjust | `{ "2026-08-27": { "meal:lunch-weekday": { calories: 440, note: "..." } } }` 当日实际热量覆盖（v1.0.2 起停写，旧数据保留） |
| `tempTasks` | kTempTasks | `{ "2026-08-27": [ { id, type:'snack'\|'exercise', name, time, calories, source } ] }` 今日加餐/加练（v1.0.2 起停写退役，迁移并入 dayEntries，模型与 v1 备份兼容保留） |
| `extraFoods` | kExtraFoods | （已废弃）旧加餐记录，迁移并入 tempTasks，兼容保留 |
| `dayEntries` | kDayEntries | `{ "2026-08-27": [ DayEntry ] }` 当日条目快照（F11）：餐食与运动统一（kind 区分），内容/热量/备注，修改即脱钩；不参与 400 天裁剪 |
| `weightRecords` | kWeightRecords | `{ baseline: {base,date}, records: { "2026-08-27": { weight, bmr, updatedAt } } }` 体重记录与基础消耗固化（F10）；一天一条；不参与 400 天裁剪 |
| `settings` | kSettings | `{ tdee, bmr, dailyCalorieTarget, reminderEnabled, reminderAdvance, autoBackupEnabled, ai: { provider, endpoint, apiKey, model } }` |
| `apiUsage` | kApiUsage | `{ calls, promptTokens, cacheHitTokens, completionTokens }` |
| `onboardingState` | kOnboarding | `{ done, profile: { gender, age, height, weight, activity } }` |

> 日期一律 `YYYY-MM-DD` 本地时区字符串；打卡/调整/临时任务等按 400 天裁剪；`dayEntries`/`weightRecords` 因「历史固化」语义不裁剪（体量估算见各自设计文档）。
> v1.0.2（2026-09-03 落地）：`weightRecords`（F10）与 `dayEntries`（F11）已随 App v1.0.2 实现，详见 [weight-design.md](weight-design.md) 与 [day-snapshot-design.md](day-snapshot-design.md)；备份 10 项、formatVersion 2。

### 6.3 Provider 层（providers/）

| Provider | 职责 | 关键方法 |
|----------|------|----------|
| AppProvider | 全局 UI 态（不持久化） | `setActiveTab` / `refreshToday()`（跨天刷新）/ `onNotificationTap(focus)` |
| PlanProvider | planData 读写 | `importPlan`（校验+增量合并+调度）/ `removeItem` / `clearMeals` / `clearExercises` / `hasPlan` |
| RecordProvider | 打卡/临时任务/调整 | `toggleCheck`（任意日期可写，供补打卡）/ `addTempTask` / `removeTempTask` / `setAdjust` / `clearRecords` |
| SettingsProvider | settings 读写 | `update(patch)`（联动重调度）/ `applyMeta`（导入吸收 tdee/目标摄入）/ `estimateTdee` / AI 多配置 `addAiProfile`/`activateAiProfile`/`removeAiProfile`/`replaceSettings`（多服务商、仅启用一个、已配置只读，详见 ai-profile-design.md） |
| UsageProvider | AI 用量统计 | `recordUsage`（chat 响应埋点）/ `clearUsage` |
| OnboardingProvider | 引导状态 | `shouldOnboard()`（!done && !isLegacyUser）/ `finish` / `skip` / `rerun` |

变更通知约定：任何影响缺口/提醒的数据变更（打卡、加餐、调整、计划、设置）都会 `notifyListeners()`；自动备份服务 `attach()` 后监听全部 Provider 变更做防抖落盘。

## 7. 核心算法

### 7.1 当日任务计算（utils/plan_utils.dart）

```dart
TaskSet getTasksForDate(PlanData planData, String dateStr) {
  // 计划开始日（meta.startedAt，首次导入日）之前视为「无计划」：
  // 不产生任务、不计完成度、不参与统计
  if (startedAt 非空 && dateStr < startedAt) return const TaskSet();
  // 命中规则：填了 dates 仅按具体日期生效（days/范围忽略）；
  // 否则按 days 周几 + startDate/endDate 范围
  // 结果按 time 升序排列
}
```

### 7.2 热量缺口（utils/calorie_utils.dart）

```
// 口径：当日消耗 = 基础消耗（不含运动）+ 当日实际运动；避免活动系数与运动打卡双算
baseBurn(settings) = settings.bmr > 0 ? round(settings.bmr × 1.2) : settings.tdee

dailySummary(dateStr):
  tasks      = getTasksForDate(plan, dateStr)
  mealIntake = Σ 已打卡且 calories != null 的计划餐热量
  tempIntake = Σ tempTasks[date] 中 type != 'exercise' 的热量
  extraIntake= Σ extraFoods[date]（已废弃，兼容保留）
  planBurn   = Σ 已打卡运动的 caloriesBurned
  tempBurn   = Σ tempTasks[date] 中 type == 'exercise' 的热量
  intake     = mealIntake + tempIntake + extraIntake
  deficit    = (baseBurn + planBurn + tempBurn) − intake
```

约定：缺口为正是好事；未打卡的计划餐不计入已摄入（用户漏打卡时缺口虚高，页面注明「已打卡口径」）。临时加餐/加练添加即计入，均不参与完成度。

**打卡天口径**：某日存在任一记录（打卡 / 临时任务 / 当日热量覆盖 / 旧加餐）即视为「打卡天」，完全无记录才算中断。连续打卡/累计打卡按此计算（与计划是否全部完成无关）。

> ⚠️ **v1.0.2 起历史固化（已落地，原缺陷已修复）**：
> ① 基础消耗按日取值——`dailySummary` 改调 `baseBurnForDate(settings, records, dateStr)`（沿用链：最近 ≤date 且 bmr>0 的体重记录 ×1.2 → 基准固化 baseline → 现状口径 fallback），录体重/改估算器不再漂移历史缺口，详见 [weight-design.md](weight-design.md) §3；
> ② 当日条目快照——`dailySummary`/`dayDetail`/月历等对该日已有 `dayEntries` 时**只读快照**（完成度/摄入/运动消耗与当前计划无关），无快照日走旧口径 fallback，详见 [day-snapshot-design.md](day-snapshot-design.md) §4.2。

### 7.3 提醒调度（services/reminder_service.dart，详见第 8 节）

```
ensureScheduled(plan, settings):        // 增量调度：今天+明天
  if !settings.reminderEnabled → return
  for date in [today, tomorrow]:
    for task in getTasksForDate(date) where reminder==true:
      fireAt = 日期 + task.time − reminderAdvance 分钟
      if fireAt 已过 → 跳过
      key = "date|time|advance|type|id"；本进程已调度（_scheduledKeys）→ 跳过
      zonedSchedule(...)；单日上限 30 条
  清理本次未涉及且非未来日期的 key（防膨胀）

fullReschedule(plan, settings):         // 全量重排：cancelAll（异常吞掉不阻塞）→ 清 keys → ensureScheduled
```

触发时机：`main.dart` 启动兜底（`onLaunch`）、导入/生成计划后、提醒设置变更后。通知 id 按 `date+id` 稳定哈希（0-999），重复调度直接覆盖不叠加。

### 7.4 统计聚合（utils/calorie_utils.dart）

- 周视图 `weekData`：本周一到今天，逐日 `dailySummary` + 完成度。
- 月历 `monthData`：逐日完成率着色；无任务=灰；开始前=灰。
- 连续完成 `streakDays`：从今天往回数，`done==total && total>0` 连续天数（今天未全部完成则从昨天起算）。
- 趋势 `trendData`（近 14 天正负条）、`dayDetail`（单日明细）、`monthReview`（月度回顾）口径见 5.6 节。

## 8. 提醒技术方案（关键风险点）

### 8.1 采用方案：flutter_local_notifications（v2.0 现行）

`zonedSchedule` 注册到系统 **AlarmManager**（`AndroidScheduleMode.exactAllowWhileIdle`），相比旧版 plus.push 的本质提升：

| 能力 | plus.push（旧） | flutter_local_notifications（现） |
|------|----------------|--------------------------------|
| 重启后调度 | 可能丢失，需开 App 恢复 | **系统级自动恢复**（App 仍做启动兜底重算） |
| 精确闹钟 | 依赖 ROM | exactAllowWhileIdle（未授权自动降级 inexact，偏差数分钟仍可提醒） |
| 通知渠道 | 不可控 | 自建渠道 `jianfei_dazi_reminder`（计划提醒，importance high） |

要点与限制：

- Android 13+ 运行时申请 `POST_NOTIFICATIONS`：`requestNotifPermission()` / `checkNotifPermission()`，设置页提供状态检测与申请按钮（插件 manifest 自动合并权限声明，主 Manifest 无需手写）。
- 精确闹钟权限（部分 ROM 默认关闭「闹钟和提醒」）：`zonedSchedule` 抛异常时降级 inexact 重试（reminder_service 内已实现），时间可能偏差数分钟。
- 通知点击：payload `{"focus":"meal:xxx"}` → `NotificationTapBus` → 定位今日页卡片。
- 旧版插件残留的坏通知 JSON 可能导致 `cancelAll` 反序列化失败：已捕获并忽略（坏数据 cancel 不到也无妨，同 id 重调度会覆盖）。
- 部分国产 ROM（MIUI/EMUI/ColorOS）仍需用户手动允许「自启动 + 省电策略无限制 + 通知类别开启」：设置页图文引导（FR2.7）。

### 8.2 旧版方案归档

uni-app 时代的 plus.push 本地消息与插件市场方案（v1.x 方案 A/B）随迁移废弃，详见 git 历史 design.md v1.x 第 8 节。

## 9. AI 热量查询设计（services/ai_service.dart）

### 9.1 请求契约（OpenAI 兼容）

```
POST {endpoint}/chat/completions
Authorization: Bearer {apiKey}
{ "model": model, "temperature": 0.2, "messages": [...], "stream": false,
  "thinking": { "type": "disabled" } }   // 仅 DeepSeek 服务商附加（原因见 9.2 思考模式注记）
```

提示词组（常量内置于 ai_service.dart）：热量查询（kCalQuerySys，返回 `{name, calories, unit, confidence}`）、运动消耗估算（kBurnEstSys，按体重/时长估算并返回拆解）、计划生成（复用 templates.dart 的 kAiPrompt + 格式说明）、文档转计划（generatePlan）。所有响应过统一容错解析：剥离 markdown 围栏 → 正则提取首个 JSON → 数值范围校验（热量 0-20000）。

### 9.2 服务商预设（models/settings.dart `kAiProviders`）

| 服务商 | endpoint | 默认模型 |
|--------|----------|----------|
| DeepSeek（默认） | `https://api.deepseek.com` | `deepseek-v4-flash` |
| Kimi（月之暗面） | `https://api.moonshot.cn/v1` | `kimi-k3` |
| MiMo（小米） | `https://api.xiaomimimo.com/v1` | `mimo-v2.5` |
| MiniMax | `https://api.minimaxi.com/v1` | `MiniMax-M3` |
| 自定义 | 用户填 | 用户填 |

退役模型自动迁移（`kRetiredModelMap`）：`deepseek-chat → deepseek-v4-flash`、`deepseek-reasoner → deepseek-v4-flash`。

> **思考模式注记（2026-09-03 真机排障）**：DeepSeek V4（v4-flash / v4-pro）**默认开启思考模式**（effort=high），
> 非流式小任务（热量/消耗估算、单餐 JSON）会被内部链式推理拖慢到 20~40s。App 内所有 DeepSeek 请求显式携带
> OpenAI 格式开关 `thinking: {type: disabled}`（ai_service.chat() 按 provider/endpoint 判定，非 DeepSeek 不传）。
>
> 官方别名映射：旧 `deepseek-chat` = v4-flash 非思考模式、旧 `deepseek-reasoner` = v4-flash **思考模式**，两者均落在
> **v4-flash 而非 v4-pro**（v4-pro 输出单价约 3.1 倍：$0.87 vs $0.28 /M token）。reasoner 老用户迁移到 v4-pro 是常见误区；
> 本 App 因强制非思考，迁移到 v4-flash 即保留可用性且不白付 pro 差价。旧别名 `deepseek-chat` / `deepseek-reasoner`
> 已于 2026-07-24 停用（请求直接报错）。另：thinking 模式下 temperature/top_p 等参数无效（不报错）；高峰 surge 定价
> （北京 09:00–12:00 / 14:00–18:00 翻倍）已宣布、未激活。

### 9.3 函数面与容错

| 函数 | 用途 |
|------|------|
| `queryCalorie(desc)` | 食物热量查询（加餐页/AI 估算/重估） |
| `estimateMeal(...)` | 计划生成前的单餐估算（引导/导入编辑态） |
| `estimateItemMeal(desc)` | **v1.6 增补**：计划条目编辑器整餐估算——结构化食材清单（含用量）+ 做法步骤 + 备注，专用提示词强调按用量逐项与烹饪隐藏热量（plan-item-ai-estimate-design.md §4.1） |
| `estimateBurn(desc, weight, ...)` | 运动消耗估算（带体重）；**v1.0.1 扩展 gender/age/height 个人基础信息**（weight-design.md §6）；v1.6 起计划条目编辑器复用（当天生效体重口径） |
| `generatePlan(doc)` | 文档转计划 JSON（导入页 AI 模式） |
| `testAI(config)` | 测试连接（固定询问「一个水煮蛋的热量」） |
| `queryBalance()` | DeepSeek 账户余额（仅 deepseek 端点显示） |

- 失败处理：自动重试 1 次 → 中文错误（网络异常/识别失败/未配置），手动录入永远兜底。
- **未配置 AI 时统一弹出 AI 配置弹层**（`widgets/ai_config_sheet.dart`：`showAiConfigSheet` + `ensureAiConfigured` 前置校验，保存后立即继续原操作）。所有 AI 入口共用：导入生成 / 加餐查询 / 今日实际摄入估算 / 运动消耗估算 / 引导页生成。
- 用量统计：chat 响应 `usage` 字段埋点入 `apiUsage`；余额查询弹窗同屏展示账户余额 + 本 App 用量（次数/tokens/估算费用，按 DeepSeek 牌价现算）。
- Key 仅存本地 storage，不打印日志。

## 10. 内置食物库（data/food_db.dart）

- 82 条 `FoodItem`：`{ name, alias[], calories, unit, tags[] }`。
- 搜索：name/alias/tags 不区分大小写包含匹配，返回前 20 条；中文/拼音首字母不要求。
- 覆盖：KFC 单品/套餐、麦当劳、常见外卖主食（黄焖鸡/麻辣烫/螺蛳粉等）、轻食、饮品零食、通用（米饭/水煮蛋/牛奶等）。数值为公开资料估算值，App 内展示「≈」前缀。

## 11. UI 设计规范（theme/app_theme.dart）

色彩（`AppColors`，柔和化复刻旧版配色）：

```dart
primary      #5BA47C  // 主绿（打卡/强调/按钮）
primaryBg    #E9F3ED  // 浅绿底（chips/完成态卡片）
orange       #DB9558  // 柔和橙（时间/kcal/警示数字）
danger       #E25C50  // 红（超标/危险操作）
bg           #F6F6F3  // 页面背景（米白）
card         #FFFFFF  // 卡片
text         #3C3C3E / textSub #A6A6AA / textFaint #C6C6C4
chartGray    #D8DAD6  // 图表无数据
```

主题取向（性能优先，低端机优化）：

- `useMaterial3: false`；关闭水波纹（`NoSplash`），点击反馈用一次性淡灰高亮（列表滚动不再持续计算 splash 动画）。
- 页面转场统一 160ms 淡入（`FastPageTransitionsBuilder` + `AppRoutes.fade`），替代默认 300ms 位移+缩放。

通用组件（对应旧版 class/组件）：`AppCard`（圆角 16 白卡）、`SectionTitle`、`Tag`（default/green/orange/red）、`PrimaryButton` / `PlainButton` / `DangerButton`（胶囊 44/42 高）、`DashedAddButton`（虚线胶囊「＋ 今日加餐/导入计划」）、`EmptyState`（emoji + 文案 + 副文案，页面级垂直居中）、`DashedBorderContainer`（CustomPaint 虚线描边）。

字号：页面标题 19 / 区块标题 15 / 正文 13-14 / 辅助 11-12 / 缺口大数字按汇总卡规格。图标：emoji + 文字为主（🍚🏃📋⚙️），不引入字体图标库；应用图标用用户 jpg 生成的 PNG（`android/app/src/main/res/mipmap-*`）。

## 12. Android 工程配置

| 项 | 值 |
|----|-----|
| 包名 applicationId | `com.colorh.jianfei_dazi`（一旦定了不改） |
| 应用名 | 知轻（Manifest `android:label`） |
| compileSdk | 36（`android/build.gradle.kts` 对所有插件模块强制，file_picker 等旧插件硬编码 34 的冲突已统一拉齐） |
| 版本号 | pubspec `version: 1.0.0+1`（versionName+versionCode；v1.0.1 计划 `1.0.1+2`） |
| 权限 | `INTERNET`（AI 请求，release 必需）；`WRITE_EXTERNAL_STORAGE maxSdkVersion=28`（Android 9 及以下写 Download）；通知权限运行时申请（插件合并） |
| Download 写入 | Android 10+ 走 MediaStore（MainActivity.kt 原生方法，免权限）；Android 9 及以下直写文件路径 |
| 依赖镜像 | `android/.local-maven-repo`（本地 Maven 仓库，含 Flutter 引擎 AAR 全系列；`build.gradle.kts` allprojects 置于仓库链最前，离线/弱网环境可稳定构建） |

## 13. 构建与发布

1. 构建：`flutter build apk --release` → 产物 `build/app/outputs/flutter-apk/app-release.apk`。
2. 本机构建要点（Windows/macOS 通用）：确保 `~/.gradle` 中 io.flutter 引擎 jar 按 debug/release 分别缓存完整；缺 jar 时按 `download.flutter.io` 模板**串行单连接**补入本地镜像仓库后再构建（详见项目记忆，勿并行下载）。
3. 测试：`flutter test`（需先清代理环境变量 `HTTP(S)_PROXY` 等，否则 flutter_tester 的 localhost WebSocket 握手被劫持导致全部测试连不上）；`flutter analyze` 不受影响。
4. 安装：APK 直接传手机安装；开启「允许安装未知来源」。
5. 安装后首跑检查：通知权限弹窗、省电白名单引导、自动备份开关（默认关）。

## 14. 风险与对策

| 风险 | 等级 | 对策 |
|------|------|------|
| 部分 ROM 精确闹钟/后台限制导致提醒偏差或延迟 | 中 | exact→inexact 自动降级仍可提醒；设置页省电白名单图文引导；启动兜底重算 |
| AI 返回非严格 JSON | 中 | 强容错解析（9.3）+ 数值可编辑 + 手动录入兜底 |
| 用户未配 AI Key | 低 | 内置库 82 条覆盖高频外卖/KFC；手动录入永不缺席 |
| 计划 JSON 被生成得不规范 | 中 | validateRaw 中文错误定位 + normalizePlan 自动补默认 + 重试 1 次 |
| 老版本备份读 1.0.1+ 备份忽略新键 | 低 | formatVersion 保持 1，`_normalizeBackup` 白名单模式天然兼容（weight-design.md §7 已知限制） |
| 插件 compileSdk 冲突（file_picker 等硬编码 34） | 已解决 | build.gradle.kts 强制全插件 compileSdk=36 |

## 15. 首次使用引导 & 使用指引（v1.0 已实现）

设计方案见 [guide-design.md](guide-design.md) v0.2，本章记录 Flutter 实际落点。

### 15.1 首启判定与引导状态（providers/onboarding_provider.dart）

- 独立存储键 `onboardingState`：`{ done, profile }`；`done` 仅在确认完成/跳过时置 true。
- `shouldOnboard()` = `!done && !isLegacyUser()`；老用户豁免：有计划 / 有打卡 / `bmr > 0` / 有 AI Key 任一命中即静默置 done，绝不打扰。
- 「清空全部数据」不重弹引导（数据复位与引导重看解耦）；重走引导走指引页「重新体验首次引导」（主动行为，不清数据，确认完成走增量合并不破坏现有计划）。

### 15.2 引导页（pages/onboarding/onboarding_page.dart）

- 5 步流转：欢迎 → 基础信息（实时算 BMR/基础消耗/参考总消耗，`estimateBmr` 与设置页同口径；即存即持久化）→ 计划录入（逐条 / 整日一句话双模式，草稿内存态不落盘）→ AI 生成（未配 Key 弹页内精简配置层，「暂不」转手动；失败重试 1 次 + 手动兜底）→ 编辑确认（行内编辑 + 单条/全部 AI 重估 + 汇总条实时着色 + 删除撤销）→ 确认完成（importPlan 增量合并 + finish → 回首页）。
- 推荐目标摄入 = `round(BMR × activity) − 400`，下限保护（女 1200 / 男 1500）。
- 重估复用现有 `queryCalorie` / `estimateBurn`（体重取引导 profile）；token 成本走 apiUsage 统计。

### 15.3 使用指引（pages/guide/guide_page.dart + data/guide_articles.dart）

- 8 篇图文：onboarding / checkin / import / add-snack / add-exercise / ai-config / reminder / stats；列表态（条目卡）⇄ 详情态（分步图文 + 全屏预览 + 底部上一篇/下一篇）。
- 入口：设置页「帮助」分组；截图素材为 Flutter 模拟器/真机截图（旧版 HBuilderX H5 截图方案随迁移废弃）。
- 加餐/加练引导 = 归档内三篇图文承载，现有页面零轻引导（范围硬约束延续）。
