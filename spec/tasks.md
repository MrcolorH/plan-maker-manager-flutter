# 开发任务计划（tasks.md）

按阶段推进，每阶段以「完成标准」自测通过后再进入下一阶段。
Phase 4（提醒）是最大技术风险点，刻意提前到核心 UI 之后、统计之前，留出方案 B 切换空间。

约定：工程目录 `plan/app/`；文档参照本目录 spec.md / design.md。

---

## Phase 0 ｜ 工程初始化

- [x] 创建 uni-app 工程（Vue3、HBuilderX 结构，无 npm 依赖）到 `plan/app/`
- [x] 配置 `pages.json`：5 个路由（主容器 + 4 子页面），无原生 tabBar（自定义 tab-bar 组件）
- [x] 配置 `manifest.json`：名称「减肥搭子」、vueVersion 3、Push 模块、权限、minSdk 26 / targetSdk 34、图标
- [x] 建立 `uni.scss` 设计变量（design.md 第 11 节色彩/字号）
- [x] 手写响应式 store（Vue3 reactive，替代 Pinia，零依赖）
- [x] 建立目录结构：pages / components / store / utils / data（design.md 第 3 节）
- [ ] HBuilderX 打开 `plan/app/` → 生成 appid → 标准基座真机运行（**用户操作**）

**完成标准**：标准基座真机运行，4 个空白 Tab 可切换。

## Phase 1 ｜ 数据层与计划解析

- [x] `utils/date.js`：formatDate / parseDate(返回 weekday 1-7) / addDays / dateCn(周几中文)
- [x] `utils/plan.js`：`normalizePlan()`（补 id/默认值）、`validatePlan()`（import-format.md 第 5 节全部规则，错误信息中文定位）、`getTasksForDate()`
- [x] `store/plan.js`、`store/record.js`、`store/settings.js`、`store/app.js`：reactive state + 方法 + storage 同步；模块加载时水合
- [x] `data/food-db.js`：种子数据 70+ 条 + 搜索函数
- [ ] 手动构造非法 JSON 用例 10+ 条真机回归（导入页已实现完整校验与中文错误）

**完成标准**：template.json 可通过校验并 normalize；10 条非法用例均返回正确中文错误。

## Phase 2 ｜ 计划导入与模板

- [x] `pages/import/import.vue`：粘贴框 + 解析校验 + 错误列表 + 预览卡 + 确认导入
- [x] 文件导入：`uni.chooseFile` + plus.io 读取 .json（Android 路径兼容处理）
- [x] 导入动作：写 planStore → applyMeta(settings) → 返回今日页
- [x] `pages/template/template.vue`：三区块（AI提示词/格式说明/完整示例）+ 一键复制
- [x] 示例内容与 `spec/template.json` 同源（data/template.js）

**完成标准**：真机完成「复制模板 → 粘贴 → 预览 → 导入」全流程；重复导入正确覆盖。

## Phase 3 ｜ 今日页与打卡

- [x] `components/meal-card.vue` / `exercise-card.vue`（打卡态、自由餐徽标、note 展示、通知定位高亮）
- [x] `components/calorie-summary.vue`（缺口大数字 + 着色阈值 + 4 格汇总）
- [x] `utils/calorie.js`：dailySummary / streakDays / weekData / monthData / trendData
- [x] `components/tabs/today.vue`：日期头 + 汇总卡 + 餐食/运动列表 + 完成进度 + 空状态引导
- [x] `recordStore.toggleCheck` / `addExtraFood` / `removeExtraFood` + 打卡/取消交互
- [x] 自由餐打卡后引导「记录实际热量」
- [x] `pages/item/detail.vue`：食材/步骤/训练内容/单项提醒开关/删除单项
- [x] 跨天刷新（App.onShow → todayKey）

**完成标准**：真机上按 template.json 数据展示当日任务，打卡/取消/刷新持久化正确；汇总卡数字与手算一致。

## Phase 4 ｜ 本地提醒（高风险，真机优先）

- [x] `utils/reminder.js`：ensureScheduled/fullReschedule 封装（内存 keys 去重，重启自动全量重排）
- [x] App.vue onLaunch/onShow 接入调度（含日期变更检测）
- [x] 通知点击监听 → today 页 focusKey 定位高亮
- [x] Android 13+ POST_NOTIFICATIONS 运行时申请（设置页入口）
- [x] 提前量/总开关设置项联动重调度
- [ ] **真机矩阵测试（小米14 + 小米10）**：息屏/杀进程/后台三种状态，提醒 5 分钟后到达率
- [ ] （条件触发）到达率不达标 → 集成方案 B 本地通知插件并回归

**完成标准**：真机杀进程+息屏场景，提前量 0/5/15 分钟提醒 100% 到达；改设置立即生效。

## Phase 5 ｜ 加餐录入与 AI 查询

- [x] `pages/food/add.vue`：本地库搜索 + 结果列表 + 手动录入表单 + 今日已记录列表
- [x] `utils/ai.js`：queryCalorie（OpenAI 兼容契约，DeepSeek 默认）+ 容错解析 + 超时 15s
- [x] AI 结果可编辑确认 → addExtraFood(source:'ai')
- [x] 未配置 API 的引导跳转设置页（**已升级**：全部 AI 入口改为弹出 AI 配置弹层，页内保存后立即继续）
- [x] 今日页加餐列表（含删除、合计）
- [x] 设置页 AI 配置组：服务商预设/Key/模型/测试连接

**完成标准**：搜「香辣鸡腿堡套餐」本地库命中；断网/无 Key/坏返回三种失败路径均正确兜底；配 Key 后 AI 查询「黄焖鸡米饭」返回可确认结果。

## Phase 6 ｜ 统计页

- [x] 本周完成度+缺口条形（week chart）
- [x] 月历组件（当月翻页），完成率着色 + 图例
- [x] 某日详情弹层：月历/周图点某天查看当天逐项清单（吃了什么、打卡状态、实际/计划热量、临时加餐、运动），utils/calorie.js `dayDetail(date)`
- [x] 计划开始日：首次导入记 `meta.startedAt`（老数据用最早打卡日回填）；月历开始日绿点标记，开始前/无打卡的日子灰色不标「未完成」
- [x] 未开始的计划可见：月历未来/今天已排计划未打卡显示「待开始」空心绿圈，任意日期可点开详情；未来日期弹层展示计划安排（摄入 —、缺口「待开始」不产生假缺口）
- [x] 近 14 天缺口趋势（CSS 正负条形）
- [x] 连续/累计完成天数计算
- [x] 月回顾弹层：utils/calorie.js `monthReview(y, m)`——计划完成天数/总缺口/日均缺口 + 消耗、摄入最多的一天（当天热量缺口/总摄入/总消耗三列 + 「查看详情」下钻 `dayDetail`，详情层叠于回顾层之上）

**完成标准**：造 3 周样本数据，周视图/月历/趋势/连续天数与手算一致；空数据不崩。

## Phase 7 ｜ 设置页收尾

- [x] TDEE 编辑 + Mifflin-St Jeor 估算器弹层（性别/身高/体重/年龄/活动系数）
- [x] 通知权限检测与申请按钮（Android 13+）
- [x] 小米 ROM 省电白名单图文引导弹层
- [x] 清空打卡记录/清除计划/清空全部数据（二次确认）
- [x] 应用图标（用户提供的 640×640 jpg → sips 生成 72/96/144/192/1024 PNG）

**完成标准**：全部 FR6.x 验收通过。

## Phase 8 ｜ 打包发布与整体验收

- [x] 自定义 TabBar（emoji 图标，无需 PNG 资产）
- [x] 应用图标/版本号 1.0.0（static/icons 已就绪）
- [ ] 云打包 Android APK（公共测试证书）—— **用户操作：HBuilderX 打开 `plan/app/` → 发行 → 云打包**
- [ ] 按 [checklist.md](checklist.md) 全量回归（含小米14/小米10 真机矩阵）
- [ ] 安装到日常手机，实跑 3 天：真实提醒/打卡/加餐数据
- [ ] 交付：APK + 使用说明（导入流程、白名单设置一页纸）

**完成标准**：连续 3 天真机实跑无 P0 级问题，提醒不漏。

## Phase 9 ｜ AI 智能导入与体验优化（2026-08-28 增补）

- [x] AI 生成导入：粘贴计划文档 → AI 转 JSON → 校验 → 预览 → 导入（导入页默认模式）
- [x] 手动 JSON / 文件导入 / 格式说明合并为导入页「手动 JSON」模式（第二入口）
- [x] 计划页卡片「清空计划」一键操作（确认弹窗，打卡记录保留）
- [x] AI 错误交互统一：HTTP 状态码中文映射（401 Key 无效 / 402 余额不足 / 404 地址或模型错…），配置弹层内联显示测试结果（测试=先保存再实测）
- [x] 设置页「查询余额」行（DeepSeek /user/balance，弹窗展示总余额与构成）
- [x] 校验层容错：数字字符串、带秒时间、中文 type、单个数字 days 均自动归一（兼容 AI 输出习惯），非法输入仍严格拦截

## Phase 10 ｜ 当日实际执行与加餐整合（2026-08-28 增补）

- [x] 每餐「今日实际」热量覆盖（✎ 弹窗：实际值 + 备注，仅当天生效，明天恢复计划值）
- [x] 实际热量 AI 估算（大白话描述"没买到豆浆只吃了包子"→ AI 算 kcal + 拆解展示）
- [x] 加餐功能整合：「今日加餐」为唯一计划外加餐入口（食物库/AI/手动），添加即计入缺口（无需打卡），不参与完成度统计，明天自动消失；旧「加餐记录」区块移除并自动迁移历史数据
- [x] API 用量统计：累计调用次数/tokens/估算费用（store/usage.js，chat 响应 usage 字段埋点），余额查询弹窗同屏展示，支持清零

## Phase 11 ｜ 首次使用引导 & 使用指引（2026-09-01 增补）

设计依据：[guide-design.md](guide-design.md) v0.2（已评审）；需求：spec.md F7/F8；技术：design.md 第 15 章。
**范围硬约束：只增不改**——现有文件触碰仅限 4 处（3 个接入点 + 1 处末尾追加，见 design.md 15.1），现有功能回归用例见 checklist.md 第 9 节。

- [ ] `store/onboarding.js`：独立键 `onboardingState`（done + profile）+ `shouldOnboard` / `finishOnboarding` / `skipOnboarding` / `rerunOnboarding` + `isLegacyUser` 升级豁免
- [ ] 接入点 ①②：`pages.json` 注册 2 个新页面；`index.vue` onShow 首启判断 redirectTo（约 5 行）
- [ ] `pages/onboarding/onboarding.vue` 骨架：5 步流转 + 进度圆点 + 返回键策略（Step0 退出确认）
- [ ] Step0 欢迎页（三能力卡 + 开始/跳过）
- [ ] Step1 基础信息：实时 BMR/基础消耗/参考总消耗（复用 `estimateBmr`，与设置页口径一致）+ 推荐目标摄入（参考总消耗−400，下限女 1200/男 1500）+ 经 `settings.update()` 保存 + profile 存 onboardingState
- [ ] Step2 计划录入双模式：逐条录入（餐类/时间/星期 chips/热量，含运动条目）⇄ 整日一句话；草稿跨模式保留；「手动完成」直达 Step4
- [ ] `utils/ai.js` 末尾追加 `generatePlanFromInput`（GUIDE_PLAN_PROMPT，输出对齐 import-format.md，复用 chat/容错/用量统计；现有函数零改动）
- [ ] Step3 AI 生成：`hasAIConfig` 检测 → 页内精简配置弹层（调现有 switchProvider/updateAI/testAI，可跳过转手动）→ normalizePlan 校验 → 失败重试 1 次/转手动
- [ ] Step4 编辑确认：条目行内编辑 + 删除撤销（5s）+ 追加；dirty 标记 + 单条/全部 AI 重估（复用 `queryCalorie`/`estimateBurn`，并发 ≤2，失败保留原值）+ 汇总条实时着色
- [ ] Step5 完成：`importPlan(draft)` + `finishOnboarding` + redirectTo 首页；完成页「查看使用指引 ›」入口
- [ ] 接入点 ③：设置页「帮助」分组 + 使用指引入口行
- [ ] `pages/guide/guide.vue`：列表 ⇄ 详情两态 + 上一篇/下一篇 + 「重新体验首次引导」
- [ ] `data/guide.js`：8 篇图文内容源（步骤文案 + marks 标注坐标）
- [ ] 截图素材：HBuilderX 跑 H5 → DevTools 412×915 视口 → 预置演示数据 → 12 张真实截图入 `static/guide/`（guide-design.md §6.1 清单）
- [ ] checklist.md 第 9 节全量自测 + 现有功能回归（对照第 1~8 节抽测）

**完成标准**：新装真机首启自动进引导，走完「基础信息 → 录入 → AI 生成 → 编辑 → 确认」全流程后今日页正常展示、提醒正常调度；老用户升级不弹引导；现有功能行为与改前一致。

## Phase 12 ｜ 历史数据导入导出（2026-09-01 增补）

设计依据：[backup-design.md](backup-design.md) v1.0；需求：spec.md F9。
**范围约束（只增不改）**：现有文件改动仅 settings.vue「数据与计划」分组增补 + 各 store 末尾追加小函数；其余全部为新增 utils/backup.js。

- [x] `spec/backup-design.md`：备份文件格式（.dat 壳 + JSON 内容 + app/type/formatVersion 标识）、8 项全量快照、增量/覆盖合并规则、热量风险与隐私提示、plus.io 读写方案
- [x] spec.md 增补 F9（FR9.1~9.6 验收标准）、页面清单、P1 候选移除「数据导出备份」；README 导航增补
- [x] `store/plan.js` 追加 `replacePlan(data)`（覆盖导入用：整体替换 + persist + fullReschedule）
- [x] `store/record.js` 追加 `mergeRecords(bundle)`（打卡按 checkedAt 取新 / mealAdjust、tempTasks 按 id 合并，导入优先）+ `replaceRecords(bundle)`（清空后整体写入）
- [x] `store/settings.js` 追加 `replaceSettings(data)`（DEFAULTS 深度合并补缺后整体替换）
- [x] `store/onboarding.js` 追加 `replaceOnboarding(data)`；`store/usage.js` 追加 `replaceUsage(data)`
- [x] `utils/backup.js`（新）：`buildBackupData`（8 项快照聚合）/ `exportBackup`（写 .dat 到 Download 目录 + 返回路径）/ `parseBackupText`（JSON 解析 + 结构校验 + 容错归一）/ `buildBackupSummary`（导入前概要）/ `mergeBackup`（增量）/ `restoreBackup`（覆盖）
- [x] `components/tabs/settings.vue`：「数据与计划」分组新增「导出历史数据备份 / 导入历史数据备份」两行；导出确认（隐私提示）+ 成功弹窗（路径 + 分享按钮）；导入：选文件 → 读取 → 概要弹层（增量/覆盖/取消）→ 增量风险确认 / 覆盖强确认 → 执行
- [ ] checklist.md 第 10 节全量自测 + 现有功能回归（第 7 节设置相关抽测）

**完成标准**：真机导出 .dat → 微信发送另一设备 → 覆盖导入后计划/打卡/设置/用量与导出时一致、提醒正常调度；增量导入同 id 不重复、打卡不倒退、settings 不被覆盖；选错文件中文报错且数据不变。

---

## 依赖关系

```
Phase 0 → 1 → 2 → 3 → 4(真机) → 5 → 6 → 7 → 11(引导) → 8(打包)
                   ↑ 风险点：若 Phase 4 需切方案B，则插件集成后回归 Phase 3/4
Phase 11 复用 Phase 1（normalize）/2（导入动作）/5（AI）/7（设置口径）的现成产物，接入点改动在 Phase 8 打包前完成回归
Phase 12 复用 Phase 1（store 读写模式）/2（文件读取模式）/4（fullReschedule）的现成产物，独立于 Phase 11，随下个安装包发布
```

## 里程碑定义

- M1 可用版（Phase 0-3）：导入计划 + 看到当日任务 + 手动打卡
- M2 合格版（Phase 0-5）：提醒可靠 + 加餐/热量缺口闭环 ← **核心价值达成**
- M3 发布版（Phase 0-8）：统计完善 + 设置齐全 + 打包实跑
- M4 引导完整版（Phase 11）：新装用户「开箱即用」，指引随时回看（随下个安装包发布）
