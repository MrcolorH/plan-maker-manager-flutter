# 技术设计方案（design.md）

版本：v1.1 ｜ 配套：[spec.md](spec.md) ｜ [import-format.md](import-format.md) ｜ [guide-design.md](guide-design.md)
> v1.1 增补（2026-09-01）：首次使用引导 & 使用指引（第 15 章，依据 guide-design.md v0.2 评审稿；范围硬约束：只增不改）

---

## 1. 技术选型总览

| 层 | 选型 | 理由 |
|----|------|------|
| 框架 | uni-app（Vue 3）+ HBuilderX 4.x | 用户指定；个人开发云打包最省事 |
| 工程模板 | HBuilderX「默认模板(Vue3)」 | 无需 CLI/Vite 配置成本，直接云打包 |
| UI | 手写组件 + emoji/文字图标（自定义底部 TabBar） | 界面要求简洁，不引入 uview/uni-ui 与图片图标资产，包体小、样式可控 |
| 状态管理 | 手写响应式 store（Vue3 `reactive` 单例模块 + 变更即同步 uni storage） | 零 npm 依赖，HBuilderX 打开即可运行；4 个 Tab + 详情页共享计划/打卡状态 |
| 本地存储 | `uni.setStorageSync / getStorageSync` | 单机应用，数据量小（< 几百 KB） |
| 本地提醒 | 方案 A：`plus.push.createMessage`（HTML5+ 本地消息，见第 8 节） | 零原生插件依赖；备选方案 B 为插件市场本地通知插件 |
| AI 热量查询 | OpenAI 兼容 `chat/completions`，用户自配 Key（**DeepSeek 默认**/智谱/通义/自定义） | 免后端零成本；用户已有 DeepSeek Key，deepseek-v4-flash 即可胜任 |
| 图表 | 纯 CSS 条形/日历格子 | 不引 echarts/uCharts，保持简洁 |
| 目标平台 | Android APK（Android 8.0+） | 用户自装，不上架应用商店 |

## 2. 总体架构

```
┌─────────────────────────────────────────────┐
│  页面层  today / plan / stats / settings     │
│          food-add / import / template / item │
├─────────────────────────────────────────────┤
│  状态层  Pinia: planStore / recordStore /    │
│          settingsStore（变更即持久化）         │
├─────────────────────────────────────────────┤
│  服务层(utils)                                │
│   plan.js      计划解析/校验/当日任务计算        │
│   reminder.js  提醒调度（plus.push 封装）       │
│   calorie.js   热量缺口/统计聚合                │
│   ai.js        AI 热量查询（请求+容错解析）      │
│   date.js      日期与星期工具                   │
├─────────────────────────────────────────────┤
│  数据层                                       │
│   uni storage（planData / records / settings）│
│   data/food-db.js 内置食物库（离线）            │
│   网络：仅 ai.js 出网（用户自配 endpoint）       │
└─────────────────────────────────────────────┘
```

数据流向：页面 → store 模块方法（reactive 变更 + 同步 uni storage）；store 模块首次 import 时从 storage 水合。提醒调度在 App `onShow`/导入后/设置变更后触发，与页面解耦。

## 3. 目录结构

uni-app 工程位于 `plan/app/`（与本 spec 目录平级）：

```
app/
├── App.vue                      # onLaunch/onShow：store 水合 + 提醒调度 + push 点击监听
├── main.js
├── pages.json                   # 无原生 tabBar（用自定义组件，免 PNG 图标资产）
├── manifest.json                # 名称「知轻」、Push 模块、Android 权限
├── uni.scss                     # 设计变量（见第 11 节）
├── pages/
│   ├── index/index.vue          # 主容器：v-show 挂 4 个 tab 组件 + tab-bar（切 tab 不重载）；onShow 首启判断 → redirectTo 引导（15.2，约 5 行）
│   ├── food/add.vue             # 加餐录入
│   ├── import/import.vue        # JSON 导入
│   ├── template/template.vue    # 模板查看/复制
│   ├── item/detail.vue          # 计划项详情
│   ├── onboarding/onboarding.vue # 首次使用引导（Step0~5，含页内 AI 配置弹层；15.3）
│   └── guide/guide.vue          # 使用指引：列表 + 详情两态（15.5）
├── components/
│   ├── tab-bar.vue              # 自定义底部导航（emoji 图标）
│   ├── tabs/
│   │   ├── today.vue            # Tab：今日
│   │   ├── plan.vue             # Tab：计划
│   │   ├── stats.vue            # Tab：统计
│   │   └── settings.vue         # Tab：设置
│   ├── calorie-summary.vue      # 今日热量汇总卡
│   ├── meal-card.vue            # 餐食卡片（含打卡）
│   ├── exercise-card.vue        # 运动卡片（含打卡）
│   └── empty-state.vue          # 空状态
├── store/                       # Vue3 reactive 单例模块，变更即写 storage
│   ├── plan.js
│   ├── record.js
│   ├── settings.js
│   ├── app.js                   # 全局 UI 态：todayKey（跨天刷新）、focusKey（通知定位）
│   └── onboarding.js            # 引导状态（独立键 onboardingState）+ isLegacyUser 检测（15.2）
├── utils/
│   ├── plan.js                  # normalize/validate/getTasksForDate
│   ├── reminder.js              # plus.push 封装与调度
│   ├── calorie.js               # 热量缺口/统计聚合
│   ├── ai.js                    # AI 热量查询（请求+容错解析）；v1.1 文件末尾追加 generatePlanFromInput（15.4，现有函数零改动）
│   └── date.js                  # 日期与星期工具
├── data/
│   ├── food-db.js               # 内置食物库（离线）
│   ├── template.js              # 模板/示例/提示词文本
│   └── guide.js                 # 使用指引内容源（8 篇图文，15.5）
└── static/
    ├── icons/                   # 应用图标各尺寸 PNG（sips 从用户 jpg 生成）
    └── guide/                   # 指引真实截图素材 PNG ×12（15.5）
```

## 4. 导航与路由（pages.json）

```jsonc
{
  "pages": [
    { "path": "pages/index/index" },
    { "path": "pages/food/add" },
    { "path": "pages/import/import" },
    { "path": "pages/template/template" },
    { "path": "pages/item/detail" },
    { "path": "pages/onboarding/onboarding", "style": { "navigationBarTitleText": "欢迎使用", "navigationStyle": "custom" } },
    { "path": "pages/guide/guide" }
  ],
  "globalStyle": { "navigationBarTitleText": "知轻", "navigationBarBackgroundColor": "#F6F7FB", "navigationBarTextStyle": "black" }
}
```

不使用原生 tabBar：由 `pages/index/index.vue` 作为主容器，`v-show` 挂载 4 个 tab 组件 + `tab-bar.vue` 自定义底部导航（emoji 图标 🏠📋📊⚙️）。好处：切 tab 零重载、状态即取即用、无需准备 8 张 PNG 图标资产。子页面（加餐/导入/模板/详情）用 `uni.navigateTo` 压栈。

路由参数：`pages/item/detail?type=meal|exercise&id=xxx`；通知点击统一回主容器，通过 `store/app.js` 的 `focusKey` 定位今日页对应卡片并高亮。

## 5. 页面信息设计

### 5.1 今日页（默认首页）

```
┌──────────────────────────────┐
│ 8月27日 周四        3/5 已完成 │
│ ┌──────────────────────────┐ │
│ │ 热量汇总卡                 │ │
│ │  缺口 +620 kcal（绿）      │ │   ← 大数字：缺口
│ │  目标1400 | 已摄入780      │ │
│ │  消耗2000 | 运动+180      │ │   ← TDEE + 打卡运动消耗
│ └──────────────────────────┘ │
│ 今日餐食                       │
│ ┌ 🍚 12:00 冻豆腐虾仁荞麦面…  ✓打卡 │ ← 卡片：时间/名称/热量/打卡按钮
│ │ 🍽 18:00 青椒洋葱炒鸡胸肉  ✓打卡 │
│ │ ☕ 16:00 下午加餐(100)     ✓打卡 │
│ └ ...                        │
│ 今日运动                       │
│ ┌ 🏃 18:30 适应期·快走 40min ✓打卡 │
│ └ ...                        │
│ 加餐记录 (2条 共1200kcal)  [＋记录加餐] │
│  · 14:32 香辣鸡腿堡套餐 1100 [删] │
└──────────────────────────────┘
```

交互要点：
- 打卡按钮点击即生效，动画变对勾；再点取消（仅当日）
- 卡片点击 → 详情页（食材/步骤/训练内容/单项提醒开关）
- 空状态：未导入计划时显示引导按钮「去导入计划」
- `calories:null` 的自由餐打卡成功后 toast「记得记录实际热量」，右上角飘「去记录」快捷入口
- 页面 `onShow` 时刷新（跨天停留场景）

### 5.2 计划页

- 顶部：当前计划卡片（名称、时间段、基础→目标体重、每日目标热量）
- Tab 切换：餐食 / 运动，按时间排序列出全部计划项（显示星期徽标：如「一三五」）
- 底部两个主按钮：「导入计划」「查看模板」
- 每项可点进详情；详情页可删除单项（本地标记删除，不回写 JSON）

### 5.3 导入页

1. 大输入框（textarea 粘贴 JSON）+「从文件导入」按钮（App 端走 SAF 系统文件选择器：`pickBackupFile`，读取委托 `readBackupFile`，兼容本地路径 / file:// / content://）
2. 「解析校验」→ 错误：中文错误列表（定位第 N 条/字段）；成功 → 预览
3. 预览卡：计划名/时间段/餐食 N 项（各类型数量）/运动 M 项/每日目标；提示「增量合并现有 XX 计划（同 id 更新，新增追加）」
4. 「确认导入」→ 写入 planStore → 立即重调度提醒 → 跳转今日页

### 5.4 模板页

三个可折叠区块，每块右上角「复制」按钮（`uni.setClipboardData`）：
- 「JSON 格式说明」（精简版字段表）
- 「完整示例」（template.json 内容，即用户的真实计划样例）
- 「AI 生成提示词」（import-format.md 第 6 节）

### 5.5 加餐录入页

```
┌──────────────────────────────┐
│ [搜索食物：香辣鸡腿堡…]        │ ← 本地库即时过滤
│ 内置库结果                     │
│  香辣鸡腿堡套餐  ≈1100 kcal [＋] │
│  吮指原味鸡(1块) ≈240 kcal  [＋] │
│  —— 没找到？ [AI 查询热量]     │ ← 需已配置 API，否则引导去设置
│ AI 结果（可编辑热量）           │
│  黄焖鸡米饭(大份) [780] [确认记录] │
│ 手动录入                       │
│  名称[____] 热量[___kcal] [记录] │
└──────────────────────────────┘
```

### 5.6 统计页

- 顶部：连续完成 X 天 ｜ 累计完成 Y 天
- 本周：7 列，每列显示 完成度 n/m + 缺口数字，着色同 FR4.6
- 月历：格子按完成率着色（浅绿=部分 / 深绿=全部 / 灰=无数据）；未来或今天已排计划但未打卡 → 空心绿圈「待开始」（图例含待开始）；计划开始日（`meta.startedAt`，首次导入日期，老数据用最早打卡日回填）绿点标记，开始前视为无计划（`getTasksForDate` 直接返回空任务，不产生任务/不计完成度）
- 近 14 天缺口条形图（0 轴基线，正向上绿、负向下红）
- 某日详情弹层：月历格子或周图列点击任意一天（含未来）→ `dayDetail(date)` 弹层，顶部三格（完成度 n/m、已摄入、缺口）+ 逐项清单（计划餐✓/○与实际热量及备注、临时加餐＋含来源徽标、运动消耗；未打卡行置灰）；未来的日期：标题「未开始」标签 + 「还没到这天，以下是计划安排」，摄入显示 —、缺口显示「待开始」（不产生 TDEE 假缺口）；计划开始前的日期显示「计划开始前，无统计数据」
- 月回顾弹层：月历标题旁「月回顾」按钮 → `monthReview(y, m)` 弹层，顶部三格（计划完成天数、总缺口、日均缺口）+「本月已记录 N 天」；下方两卡片——**消耗最多的一天 / 摄入最多的一天**，各显示日期 + 三列数据（热量缺口、总摄入、总消耗 kcal；缺口正绿/负橙着色，消耗最多的一天附「基础 X + 运动 Y kcal」拆分），每卡片「查看详情 ›」按钮 → 在回顾层之上叠加 `dayDetail(date)` 弹层（详情层 z-index 更高，关闭后回到月回顾）；统计口径：只统计开始日后、今天之前有记录的日子（未来与开始前不参与），本月无记录显示空状态

### 5.7 设置页（分组列表）

- 热量：TDEE（输入 + 公式估算器弹层：性别/身高/体重/年龄/活动系数 → BMR×系数）
- 提醒：总开关 / 提前量（0/5/10/15/30 分钟）/ 通知权限状态与申请按钮 / 省电白名单引导
- AI 查询：服务商（智谱/DeepSeek/通义/自定义）→ 自动填 endpoint 与默认模型 / API Key（密码框）/ 模型名 / 测试连接
- 数据：清空打卡记录 / 清空全部数据（二次确认）
- 关于：版本号、格式版本 1.0

## 6. 数据模型

### 6.1 计划项（与 import-format.md 一致，存储前 normalize）

```ts
interface MealItem {
  id: string            // 缺省自动生成 m-时间戳-随机
  type: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  name: string
  time: string          // "HH:mm"
  calories: number | null
  days: number[]        // 1-7，空数组=每天
  reminder: boolean     // 默认 true
  note?: string
  details?: { item: string; amount?: string }[]
  steps?: string[]
  startDate?: string; endDate?: string
}
interface ExerciseItem {
  id: string
  name: string
  time: string
  duration: number      // 分钟
  caloriesBurned: number // 默认 0
  days: number[]
  startDate?: string; endDate?: string
  reminder: boolean
  note?: string
  content?: { item: string; detail?: string; minutes?: number }[]
}
interface PlanData {
  version: string
  meta: { planName?, startDate?, endDate?, baseWeight?, targetWeight?,
          dailyCalorieTarget?, tdee? }
  meals: MealItem[]
  exercises: ExerciseItem[]
  deletedIds: string[]   // 本地单项删除标记，导入时清空
}
```

### 6.2 存储键（storage schema）

| 键 | 类型 | 结构 |
|----|------|------|
| `planData` | PlanData | 见上；meals/exercises 空数组表示无该类计划 |
| `checkRecords` | object | `{ "2026-08-27": { "meal:lunch-weekday": { checkedAt: 1724... }, "exercise:phase1-cardio": {...} } }` 键=`类型:id`（temp 打卡键已废弃，加餐不再打卡） |
| `tempTasks` | object | `{ "2026-08-27": [ { id, type:'snack', name, time:"14:32", calories, source: 'manual'\|'db'\|'ai' } ] }` 今日加餐：添加即计入缺口，仅当天有效 |
| `mealAdjust` | object | `{ "2026-08-27": { "meal:lunch-weekday": { calories: 440, note: "没买到豆浆" } } }` 当日实际热量覆盖，仅当天生效 |
| `extraFoods` | （已废弃） | 旧加餐记录，模块加载时自动迁移并入 tempTasks |
| `settings` | object | `{ tdee: 2000, dailyCalorieTarget: 1400, reminderEnabled: true, reminderAdvance: 0, ai: { provider, endpoint, apiKey, model } }` |
| `apiUsage` | object | `{ calls, promptTokens, cacheHitTokens, completionTokens }` 本 App 累计 API 用量；chat 响应 usage 字段埋点；费用按 deepseek-v4-flash 非峰值牌价现算（store/usage.js），官方美元价分峰谷 × 汇率折算 |
| `reminderState` | 内存态 | 已调度 key 集合（`date\|time\|advance\|type\|id`）仅存进程内存：进程重启后已注册消息与 keys 同时丢失，冷启动全量重排即无重复无遗漏 |
| `onboardingState` | object | `{ done: boolean, profile: { gender, age, height, weight, activity } }` 引导状态（15.2，独立键；`done` 仅在确认完成/跳过时置 true；settings 键不加字段） |

> 日期一律 `YYYY-MM-DD` 本地时区字符串；记录按月聚合清理（保留 12 个月）。

### 6.3 响应式 store 模块（store/）

不用 Pinia（免 npm 依赖），用 Vue3 `reactive` 单例模块：每个 store 一个文件，导出 `state（reactive）` + 操作方法，方法末尾同步写 storage；模块顶层首次 import 时从 storage 水合。

- `store/plan.js`：`plan`（PlanData）；`importPlan(raw)`（校验+增量合并+调度提醒）、`removeItem(type,id)`、`clearMeals()` / `clearExercises()`（分模块清空）、`clearPlan()`（仅清空全部数据使用）；getter `hasPlan()`
- `store/record.js`：`checkRecords` / `extraFoods` / `mealAdjust` / `tempTasks`；`toggleCheck(date,type,id)`（任意日期可写，供近 3 天补打卡）、`addTempTask(date,{type:'snack'|'exercise',...})`、`removeTempTask(date,id)`、`getAdjust` / `setAdjust`、`clearRecords()`
- `store/settings.js`：`settings`；`update(patch)`（联动重调度提醒）、`applyMeta(meta)`（导入时吸收 tdee/dailyCalorieTarget）、`estimateTdee(form)`、`clearAll()`
- `store/app.js`：`todayKey`（跨天刷新用）、`focusKey`（通知点击定位卡片）、`activeTab`（当前 tab）

## 7. 核心算法

### 7.1 当日任务计算（utils/plan.js）

```js
// weekday: 1=周一...7=周日
function getTasksForDate(plan, dateStr) {
  const { weekday } = parseDate(dateStr)
  const inRange = it =>
    (!it.startDate || dateStr >= it.startDate) && (!it.endDate || dateStr <= it.endDate)
  const matchDays = it =>
    !it.days?.length || it.days.includes(weekday)
  const visible = it => !plan.deletedIds.includes(it.id)
  const byTime = (a, b) => a.time.localeCompare(b.time)
  return {
    meals: plan.meals.filter(it => inRange(it) && matchDays(it) && visible(it)).sort(byTime),
    exercises: plan.exercises.filter(it => inRange(it) && matchDays(it) && visible(it)).sort(byTime),
  }
}
```

### 7.2 热量缺口（utils/calorie.js）

```
// 口径：当日消耗 = 基础消耗（不含运动）+ 当日实际运动；避免活动系数与运动打卡双算
baseBurn = settings.bmr > 0 ? round(settings.bmr × 1.2) : settings.tdee
function dailySummary(dateStr) {
  const tasks = getTasksForDate(plan, dateStr)
  const rec = checkRecords[dateStr] || {}
  const done = key => !!rec[key]
  const plannedIntake = sum(tasks.meals.filter(m => m.calories != null).map(m => m.calories))
  const mealIntake = sum(tasks.meals
    .filter(m => done(`meal:${m.id}`) && m.calories != null).map(m => m.calories))
  const tempIntake = sum(tempTasks[dateStr].filter(t => t.type !== 'exercise').map(t => t.calories))
  const extraIntake = sum((extraFoods[dateStr] || []).map(f => f.calories))
  const planBurn = sum(tasks.exercises
    .filter(e => done(`exercise:${e.id}`)).map(e => e.caloriesBurned || 0))
  const tempBurn = sum(tempTasks[dateStr].filter(t => t.type === 'exercise').map(t => t.calories))
  const exerciseBurn = planBurn + tempBurn
  const intake = mealIntake + tempIntake + extraIntake
  const deficit = (baseBurn + exerciseBurn) - intake
  return { baseBurn, exerciseBurn, intake, deficit, ... }
}
```

约定：缺口为正是好事；未打卡的计划餐不计入已摄入（用户漏打卡时缺口虚高，属可接受语义，页面注明「已打卡口径」）。临时加餐（tempTasks type='snack'）添加即计入摄入；临时锻炼（type='exercise'）添加即计入消耗，均不参与完成度。统计页日历点开近 3 天（前天～今天）支持补录：点击餐食/运动行补打卡、补录计划外加餐或锻炼、删除临时记录，更早的日期只读。

打卡天口径：某日存在任一记录（打卡 / 临时任务 / 当日热量覆盖 / 旧加餐）即视为「打卡天」，完全无记录才算中断。连续打卡/累计打卡按此计算（与计划是否全部完成无关）。本周图为中轴 0 线形式：正缺口向上绿柱、超标向下橙柱（与近 14 天趋势图一致），不展示计划完成度（完成细节在月历点开查看）。

### 7.3 提醒调度（utils/reminder.js，详见第 8 节）

```
reschedule():
  if !settings.reminderEnabled → clearAll(); return
  keys = []
  for date in [today, tomorrow]:
    for task in getTasksForDate(date) where reminder==true 且未被删除:
      fireAt = date + task.time - reminderAdvance 分钟
      delaySec = (fireAt - now) / 1000
      if delaySec > 0:
        plus.push.createMessage(正文, payload, { title, delay: delaySec, cover: false })
        keys.push(`${date}|${taskType}|${task.id}`)
  reminderState = { lastScheduledDate: today, scheduledKeys: keys }
```

触发时机：`App.onLaunch`、`App.onShow`（仅当日期变更或 reminderState 脏标记时全量重排）、导入成功后、设置变更后。
上限保护：单日调度 ≤ 30 条，超出截断并 console.warn（正常计划远达不到）。

### 7.4 统计聚合

- 周视图：取本周一到今天，逐日 `dailySummary` + 完成度 `done数/计划数`
- 月历：逐日完成率 `rate = done/total`；着色阈值 0 / (0,1) / =1；无任务=灰
- 连续完成：从今天往回数，`done==total && total>0` 连续天数（今天未全部完成则从昨天起算）

## 8. 提醒技术方案（关键风险点）

### 8.1 方案 A（v1.0 采用）：plus.push 本地消息

HTML5+ 的 `plus.push.createMessage(content, payload, options)` 支持本地延迟通知，`options.delay` 单位秒：

```js
plus.push.createMessage(
  `${task.name}${task.note ? '｜' + task.note : ''}`,
  { date, type: 'meal' | 'exercise', id: task.id },          // payload，点击时取回
  { title: type === 'meal' ? '用餐提醒' : '运动提醒',
    cover: false, delay: delaySec, sound: 'system' }
)
plus.push.addEventListener('click', msg => { /* 跳转 today?focusId=... */ })
```

要点与限制：
- manifest「App 模块配置 → Push(消息推送)」勾选，**不配置任何 push 服务**，仅用本地消息能力（打包前真机验证：标准基座即可测，无需自定义基座）
- Android 13+ 需运行时申请 `POST_NOTIFICATIONS`：`plus.android.requestPermissions`，设置页提供状态检测与申请按钮
- **手机重启后已注册消息可能丢失**：接受该限制，App 任意一次启动/前台化即恢复当天及明日调度（设置页与文档说明）
- 部分国产 ROM（MIUI/EMUI/ColorOS）需用户手动允许「自启动 + 电池不限制」，否则延迟消息被系统吞：设置页放图文引导（FR2.7）

### 8.2 方案 B（备用，方案 A 真机不可靠时切换）

插件市场本地通知插件（如 Ba-LocalNotification 类，基于 AlarmManager + 广播接收器 + 开机重注册）：
- 优点：精确闹钟、重启自恢复、通知渠道可控
- 成本：需自定义基座调试 + 云打包时勾选插件；API 面换成插件 API（reminder.js 内部替换，页面无感）
- 决策点：Phase 4 真机测试若「杀进程+息屏 30 分钟」场景提醒到达率 < 100%，立即切换

### 8.3 否决项

- Native.JS 直接调 AlarmManager：无法注册静态广播接收器，重启后无法恢复，且代码侵入大
- uni-app `uni.` 无本地定时通知 API（`uni.createPushMessage` 为 App 侧即时消息）

## 9. AI 热量查询设计（utils/ai.js）

### 9.1 请求契约（OpenAI 兼容）

```
POST {endpoint}/chat/completions
Authorization: Bearer {apiKey}
{ "model": model,
  "temperature": 0.2,
  "messages": [
    { "role": "system", "content": SYSTEM_PROMPT },
    { "role": "user",   "content": "用户输入的食物描述" } ] }
```

SYSTEM_PROMPT：

```
你是食物热量估算助手。用户描述一份食物或套餐，请估算总热量。
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"name":"食物名","calories":总热量整数kcal,"unit":"份量描述","confidence":0到1}
描述含多种食物时合并估算总值。无法判断时 confidence 给低值。
```

### 9.2 服务商预设

| 服务商 | endpoint | 默认模型 | 备注 |
|--------|----------|----------|------|
| 智谱 AI | `https://open.bigmodel.cn/api/paas/v4` | `glm-4-flash` | 有免费模型，推荐默认 |
| DeepSeek | `https://api.deepseek.com` | `deepseek-v4-flash` | 旧名 `deepseek-chat`/`deepseek-reasoner` 已于 2026-07-24 退役，启动时自动迁移 |
| 阿里通义 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus` | |
| 自定义 | 用户填 | 用户填 | 任意 OpenAI 兼容网关 |

### 9.3 容错解析与失败处理

1. 剥离 markdown 代码块围栏 → 正则 `\{[\s\S]*\}` 提取首个 JSON → `JSON.parse`，失败再试 `eval` 前置校验（仅允许数字/字符串/中英文）
2. 校验 `calories` 为 0-20000 数字，否则视为失败
3. 网络失败/超时(15s)/未配置：分别提示「网络异常，请重试」「识别失败，请手动输入」，一律可回退手动录入
4. **未配置 AI 时统一弹出 AI 配置弹层**：服务商预设 + 接口地址 + API Key + 模型 + 测试连接，保存后立即继续原操作（不跳转设置页）。所有 AI 入口共用同一弹层——导入页生成 / 加餐热量估算 / 今日实际摄入估算 / 运动消耗估算 / 引导页生成计划；引导页额外给「暂不，手动模式」，手填永远兜底。Flutter 版实现：`lib/widgets/ai_config_sheet.dart`（`showAiConfigSheet` + `ensureAiConfigured` 前置校验）
5. Key 仅存本地 storage，不打印日志

### 9.4 测试连接

设置页「测试连接」发送固定询问「一个水煮蛋的热量」，成功标准：HTTP 200 且解析出合法 JSON，展示返回值。

## 10. 内置食物库（data/food-db.js）

条目结构：

```js
{ id: 'kfc-001', name: '香辣鸡腿堡套餐（汉堡+中薯+中可乐）',
  alias: ['肯德基', 'kfc套餐', '香辣鸡腿堡'],
  calories: 1100, unit: '1份', tags: ['kfc', '快餐', '套餐'] }
```

搜索：name/alias/tags 不区分大小写包含匹配，返回前 20 条。

种子数据约 60-80 条（数值为公开资料估算值，App 内展示「≈」前缀）：

| 分类 | 示例条目（热量为估算） |
|------|------------------------|
| KFC 单品 | 香辣鸡腿堡≈590、新奥尔良烤鸡腿堡≈500、劲脆鸡腿堡≈590、吮指原味鸡(1块)≈240、黄金鸡块(5块)≈270、薯条(中)≈330、蛋挞≈290、老北京鸡肉卷≈490、可乐(中)≈180、九珍果汁≈160 |
| KFC 套餐 | 香辣鸡腿堡套餐≈1100、新奥尔良烤鸡腿堡套餐≈1000、儿童套餐≈600 |
| 麦当劳 | 巨无霸≈550、麦辣鸡腿堡≈570、麦乐鸡(6块)≈250、薯条(中)≈330、套餐≈1100 |
| 常见外卖主食 | 黄焖鸡米饭(大份)≈750、麻辣烫(一碗)≈700、蛋炒饭≈700、炒河粉≈750、螺蛳粉≈750、兰州牛肉面≈650、沙县拌面+炖罐≈600、猪脚饭≈850、麻辣香锅(1人份)≈900 |
| 轻食 | 鸡胸肉沙拉≈350、金枪鱼三明治≈350、牛肉谷物碗≈500、关东煮(6串)≈300 |
| 饮品零食 | 珍珠奶茶(全糖大杯)≈450、美式咖啡≈10、拿铁(大杯)≈230、薯片(1包)≈550、巧克力(1板)≈550、可乐(330ml)≈140、啤酒(1瓶)≈150 |
| 通用 | 白米饭(1碗200g)≈230、水煮蛋≈70、纯牛奶(250ml)≈160、黑咖啡≈5 |

> 数值随官方营养信息更新，dev 阶段以最新公开数据核对一遍；表结构预留 `dataVersion` 便于后续扩充。

## 11. UI 设计规范

色彩（uni.scss 变量）：

```scss
$primary: #00B578;        // 主色·健康绿（打卡/强调）
$primary-light: #E6F7F0;  // 打卡完成底色
$accent: #FF8F1F;         // 热量橙（数字/加餐）
$danger: #FA5151;         // 超标红
$warning: #FF9F0A;        // 过猛/临界橙
$text-1: #17181A; $text-2: #666C7A; $text-3: #B0B6C1;
$bg: #F6F7FB; $card: #FFFFFF; $line: #EEF0F4;
```

字号/间距（rpx）：页面标题 36-40、卡片标题 30、正文 28、辅助 24、热量大数字 56；卡片圆角 20、按钮胶囊圆角 44、页面左右边距 32、卡片间距 20、卡片内边距 24。

组件规范：
- **MealCard / ExerciseCard**：左侧时间竖排（HH:mm + 类型 emoji），中间名称+热量（`500 kcal` 或 `自由餐`徽标），右侧打卡按钮（56rpx 圆形，未打卡描边、已打卡实心+对勾）；note 可展开一行
- **CalorieSummary**：缺口大数字居中着色（FR4.6 阈值），下方 2×2 网格（目标/已摄入/消耗/运动）
- **EmptyState**：插画（emoji 即可）+ 一句话 + 主操作按钮
- 列表交互统一 600ms 内反馈；危险操作（清空数据）用模态二次确认

图标：emoji + 文字为主（🍚🏃📋⚙️ 等），不引入字体图标库与图片资产；应用图标由用户提供的 jpg 经 sips 生成各尺寸 PNG 放 `static/icons/`。

## 12. manifest.json 关键配置

```jsonc
{
  "name": "知轻",
  "appid": "",                      // HBuilderX 打开项目时生成（需登录 DCloud 账号）
  "versionName": "1.0.0",
  "vueVersion": "3",
  "app-plus": {
    "modules": { "Push": {} },      // 本地消息能力（不配 push 服务）
    "distribute": {
      "android": {
        "permissions": [
          "<uses-permission android:name=\"android.permission.POST_NOTIFICATIONS\"/>"
        ],
        "minSdkVersion": 26,        // Android 8.0+
        "targetSdkVersion": 34
      },
      "icons": {
        "android": {
          "hdpi": "static/icons/icon-72.png",
          "xhdpi": "static/icons/icon-96.png",
          "xxhdpi": "static/icons/icon-144.png",
          "xxxhdpi": "static/icons/icon-192.png"
        }
      }
    }
  }
}
```

## 13. 构建与发布

1. HBuilderX 云打包：发行 → 原生 App-云打包 → Android → 使用公共测试证书（个人使用足够）→ 得到 APK
2. 包名 `com.colorh.jianfei`（一旦定了不改）
3. 安装：APK 直接传手机安装；开启「允许安装未知来源」
4. 安装后首跑检查：通知权限弹窗、一键去白名单引导

## 14. 风险与对策

| 风险 | 等级 | 对策 |
|------|------|------|
| plus.push 延迟消息在部分 ROM 不可靠 | 高 | Phase 4 首周真机矩阵测试；不可达即切方案 B 插件（第 8.2 节） |
| 重启后提醒丢失 | 中 | 接受+文档说明；任一次打开 App 即恢复；方案 B 可根治 |
| AI 返回非严格 JSON | 中 | 强容错解析（9.3）+ 热量数值可编辑 + 手动录入兜底 |
| 用户未配 AI Key | 低 | 内置库覆盖高频外卖/KFC；手动录入永不缺席 |
| 计划 JSON 被生成得不规范 | 中 | 校验错误中文定位 + 模板页提示词强制「只输出 JSON」 |

## 15. 首次使用引导 & 使用指引（v1.1 增补）

完整设计方案与页面线框见 [guide-design.md](guide-design.md) v0.2（已评审），本章记录技术要点。**范围硬约束：只增不改**——对现有文件的触碰仅限 3 个最小接入点 + 1 处末尾追加（15.1），现有函数/页面行为零变化。

### 15.1 接入点清单（全部触碰范围）

| # | 文件 | 改动 | 不触碰 |
|---|------|------|--------|
| ① | `pages.json` | 注册 `pages/onboarding/onboarding`（custom 导航栏）与 `pages/guide/guide` | 现有 5 个页面配置 |
| ② | `pages/index/index.vue` | onShow 开头：`if (shouldOnboard()) { uni.redirectTo('/pages/onboarding/onboarding'); return }` | 现有渲染/tab/focus 逻辑 |
| ③ | `components/tabs/settings.vue` | 「关于」分组上方插入「帮助」分组（使用指引入口行） | 现有 5 个分组 |
| ④ | `utils/ai.js` | 文件**末尾**追加 `generatePlanFromInput()`（内含 GUIDE_PLAN_PROMPT） | 现有全部函数（物理隔离：追加区与原代码间以注释分界） |

### 15.2 首启判定与引导状态（store/onboarding.js，新增）

```js
// 独立存储键，settings.js 零改动
const KEY = 'onboardingState'
// { done: false, profile: { gender, age, height, weight, activity } }

export function shouldOnboard() { ... }   // !done && !isLegacyUser()
function isLegacyUser() {                 // 升级豁免：任一命中即老用户
  return hasPlan()
    || Object.keys(uni.getStorageSync('checkRecords') || {}).length > 0
    || settings.bmr > 0
    || !!settings.ai.apiKey
}
export function finishOnboarding(profile) // done = true + persist
export function skipOnboarding()          // done = true（跳过）
export function rerunOnboarding()         // done = false（指引页「重新体验」用）
```

- Step1 保存：`settings.update({ tdee: 基础消耗, bmr, dailyCalorieTarget })`（现有方法）+ `onboardingState.profile`。
- 「清空全部数据」不改 `clearAll()`：清空后 done 仍 true 不自动重弹；重走引导走指引页 `rerunOnboarding()`（主动行为）。
- 推荐目标摄入 = `round(BMR × activity) − 400`，下限 clamp（女 1200 / 男 1500）。

### 15.3 引导页（pages/onboarding/onboarding.vue，新增）

- 5 步流转：`step: 0欢迎 → 1基础信息 → 2计划录入 → 3AI生成 → 4编辑确认 → 5完成redirectTo`；组件内 v-if 切换，进度圆点。
- **Step1**：字段 UI 自写；计算直接 import 现有 `estimateBmr`（口径与设置页估算器一致）；即存即持久化（用户中断后重进预填）。
- **Step2 双模式**：模式 A 逐条（餐类 emoji chips / 时间默认 07:30·12:00·18:00·15:30 / 星期 chips 对应 `days`）；模式 B 整日一句话 textarea；共用同一份 draft（`{ meta, meals, exercises }` 草稿结构，内存态不落盘）。
- **Step3**：`hasAIConfig()` 检测 → 未配置弹页内精简配置层（服务商 picker + Key + 测试连接，调现有 `switchProvider/updateAI/testAI`）→「暂不」转手动；AI 调用 `generatePlanFromInput`（15.4）→ 结果过 `normalizePlan` → 进 Step4。loading 态文案轮播 + 90s 超时（与导入页 generatePlan 一致）。
- **Step4**：条目卡行内编辑（名称/时间/星期/热量或时长/餐类）+ 删除（撤销 toast 5s）+ 追加；dirty 标记 + 单条重估（`queryCalorie` / `estimateBurn(desc, profile.weight)`）；「全部重估」对 dirty 条目并发 2 路逐条执行，失败保留原值；汇总条本地实时算（摄入Σ/消耗Σ/预计缺口，FR4.6 着色复用 `numClass` 同款阈值）。
- **Step5**：`importPlan(draft)`（现有：增量合并 + applyMeta + fullReschedule）→ `finishOnboarding()` → redirectTo 首页。**重跑场景安全性**：importPlan 增量合并天然幂等（同 id 更新），打卡记录不受影响。
- 物理返回键：Step0 弹确认「退出引导？下次还会出现」（确认退出不置 done）；其余步骤返回上一步。

### 15.4 引导计划生成（utils/ai.js 追加，现有函数零改动）

```js
// ===== v1.1 追加区（引导计划生成）——以上代码不做任何修改 =====
const GUIDE_PLAN_PROMPT = `你是减脂计划生成助手。根据用户的饮食/运动描述与个人资料，
生成结构化计划 JSON。严格只输出一个 JSON 对象：
{"version":"1.0","meta":{"planName":"我的减脂计划","dailyCalorieTarget":用户目标},
 "meals":[{"type":"breakfast|lunch|dinner|snack","name":"...","time":"HH:mm",
           "calories":整数kcal或null(自由餐),"days":[1-7]或[],"note":"..."}],
 "exercises":[{"name":"...","time":"HH:mm","duration":分钟,"caloriesBurned":整数,
               "days":[],"note":""}]}
要求：按描述拆分餐次（早/午/晚/加餐）；时间为常见用餐/训练时间；热量按中国常见
食物份量估算；days 空数组=每天；不遗漏用户提到的任何条目。`

export function generatePlanFromInput(inputText, profile) {
  return chat([
    { role: 'system', content: GUIDE_PLAN_PROMPT },
    { role: 'user', content: '用户资料：性别/体重/目标摄入…；描述：' + inputText }
  ], 90000).then(content => { /* extractJsonObj + version 修正，同 generatePlan */ })
}
```

- 失败处理：自动重试 1 次 → 中文错误（复用 `httpErrorMsg`）+「重试 / 手动模式」。
- 重估**不新增函数**：页面直接调现有 `queryCalorie`（餐食）与 `estimateBurn(desc, weight)`（运动，体重来自 onboardingState.profile）。
- token 成本：整日生成单次约 1~2k tokens，走现有 `apiUsage` 统计。

### 15.5 使用指引（pages/guide/guide.vue + data/guide.js，新增）

- 内容源接口：

```ts
interface GuideStep { img?: string; marks?: { x: number; y: number; label: string }[]; text: string }
interface GuideArticle { id; icon; title; summary; steps: GuideStep[] }
// 8 篇：onboarding / checkin / import / add-snack / add-exercise / ai-config / reminder / stats
```

- 页面两态：列表（条目卡）⇄ 详情（v-if 切换；步骤卡 = 截图 `uni.previewImage` 全屏 + 文字 + 序号标注绝对定位叠加）；底部上一篇/下一篇。
- 「▶ 重新体验首次引导」：`rerunOnboarding()` + redirectTo 引导页（仅重跑，不清数据）。
- 截图素材制作（开发阶段一次性执行）：HBuilderX 运行到 Chrome（H5，`#ifdef APP-PLUS` 代码自动剔除）→ DevTools 手机视口 412×915 → 预置演示数据（template.json 导入 + 造打卡/加餐记录）→ 按 guide-design.md §6.1 的 12 张清单截图 → `static/guide/`。若 H5 与真机视觉差异不可接受，改真机截图（其余流程不变）。
- 加餐/加练引导 = 归档内「add-snack」「add-exercise」「checkin」三篇；现有页面不加任何轻引导（范围硬约束）。

### 15.6 边界行为汇总

| 场景 | 行为 |
|------|------|
| 老用户升级 | isLegacyUser 命中 → 静默置 done，不弹 |
| 引导中杀 App | 基础信息已存；草稿丢弃，重进 Step1 预填 |
| 跳过引导 | done 置位不再弹；指引页可回看 |
| 清空全部数据 | 不改 clearAll；done 仍 true；重走引导走指引页主动入口 |
| 重跑引导 + 已有计划 | importPlan 增量合并幂等，打卡记录保留 |
| AI 失败/未配 Key | 重试 1 次 → 手动模式兜底；热量手填/自由餐语义不变 |
| 卸载丢数据 | 低 | v1 接受；P1 导出备份 |
| 引导 AI 生成结构不稳定（整日一句话模式字段多） | 中 | 复用 normalizePlan 校验管线 + 字段自动补默认 + 重试 1 次 + 手动模式永远兜底（第 15 章） |
