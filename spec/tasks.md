# 开发任务计划（tasks.md）

按阶段推进，每阶段以「完成标准」自测通过后再进入下一阶段。
Phase 4（提醒）是最大技术风险点，刻意提前到核心 UI 之后、统计之前，留出方案 B 切换空间。

> **v2.0 迁移注记（2026-09-03）**：工程已从 uni-app 整体迁移至 **Flutter**（仓库根目录，`lib/`）。
> Phase 0~10 为 uni-app 时代执行记录（文件名为当时工程 `plan/app/`，功能已全部由 Flutter 版 1:1 承接，对应实现见 [design.md](design.md) v2.0；其中未勾选项随迁移废弃，不再执行）；
> Phase 11（引导）与 Phase 12（备份）在 Flutter 版完成实现，条目文件名已更新为 Flutter 实际落点；
> Phase 13 起均为 Flutter 版开发计划。

约定：Flutter 工程位于仓库根目录（入口 `lib/main.dart`）；文档参照本目录 spec.md / design.md。

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
- [x] ~~云打包 Android APK（公共测试证书）~~ → Flutter 版：`flutter build apk --release` 产出 `build/app/outputs/flutter-apk/app-release.apk`（design.md 第 13 节）
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

## Phase 11 ｜ 首次使用引导 & 使用指引（2026-09-01 增补；Flutter 版已实现）

设计依据：[guide-design.md](guide-design.md) v0.2（已评审）；需求：spec.md F7/F8；技术：design.md 第 15 章。
**范围硬约束：只增不改**——Flutter 版触碰仅限 2 个接入点（主壳首启拦截 + 设置页帮助分组），现有功能回归用例见 checklist.md 第 9 节。以下为 **Flutter 实际落点**（uni-app 版条目见 git 历史）：

- [x] `lib/providers/onboarding_provider.dart`：独立键 `onboardingState`（done + profile）+ `shouldOnboard` / finish / skip / rerun + `isLegacyUser` 升级豁免（有计划/有打卡/bmr>0/有 Key 任一命中即豁免）
- [x] 接入点 ①：`lib/pages/main_shell.dart` initState `addPostFrameCallback` 首启判断 → `AppRoutes.fade` push 引导页
- [x] `lib/pages/onboarding/onboarding_page.dart` 骨架：5 步流转（欢迎 → 基础信息 → 计划录入 → AI 生成 → 编辑确认 → 完成）+ 进度指示 + 返回键策略（Step0 退出确认）
- [x] Step0 欢迎页（三能力卡 + 开始/跳过）
- [x] Step1 基础信息：实时 BMR/基础消耗/参考总消耗（与设置页估算器同口径）+ 推荐目标摄入（参考总消耗−400，下限女 1200/男 1500）+ 即存即持久化 + profile 存 onboardingState
- [x] Step2 计划录入双模式：逐条录入（餐类/时间/星期 chips/热量，含运动条目）⇄ 整日一句话；草稿跨模式保留；「手动完成」直达编辑确认
- [x] AI 生成：`lib/services/ai_service.dart` 计划生成（提示词复用 `data/templates.dart`，输出对齐 import-format.md，容错解析 + 用量统计）→ `normalizePlan` 校验归一 → 失败重试 1 次/转手动
- [x] 编辑确认：条目行内编辑 + 删除撤销 + 追加；单条/全部 AI 重估（复用 `queryCalorie`/`estimateBurn`，失败保留原值）+ 汇总条实时着色
- [x] 完成：`PlanProvider.importPlan` 增量合并 + finishOnboarding + 回首页；完成页「查看使用指引 ›」入口
- [x] 接入点 ②：设置页「帮助」分组 + 使用指引入口行（`lib/pages/settings/settings_page.dart`）
- [x] `lib/pages/guide/guide_page.dart`：列表 ⇄ 详情两态 + 上一篇/下一篇 + 「重新体验首次引导」
- [x] `lib/data/guide_articles.dart`：8 篇图文内容源（步骤文案 + 标注）
- [x] 截图素材：Flutter 模拟器/真机截图（uni-app H5 截图方案随迁移废弃）
- [ ] checklist.md 第 9 节全量自测 + 现有功能回归（对照第 1~8 节抽测）

**完成标准**：新装真机首启自动进引导，走完「基础信息 → 录入 → AI 生成 → 编辑 → 确认」全流程后今日页正常展示、提醒正常调度；老用户升级不弹引导；现有功能行为与改前一致。

## Phase 12 ｜ 历史数据导入导出（2026-09-01 增补）

设计依据：[backup-design.md](backup-design.md) v1.0；需求：spec.md F9。以下文件名为 **Flutter 实际落点**。
**范围约束（只增不改）**：现有文件改动仅设置页「数据与计划」分组增补 + 各 Provider 追加小方法；其余全部为新增 `lib/services/backup_service.dart`。

- [x] `spec/backup-design.md`：备份文件格式（.txt 纯文本 + JSON 内容 + app/type/formatVersion 标识）、8 项全量快照、增量/覆盖合并规则、热量风险与隐私提示、Download 读写方案
- [x] spec.md 增补 F9（FR9.1~9.6 验收标准）、页面清单、P1 候选移除「数据导出备份」；README 导航增补
- [x] `lib/providers/plan_provider.dart` 追加 `replacePlan(data)`（覆盖导入用：整体替换 + persist + fullReschedule）
- [x] `lib/providers/record_provider.dart` 追加 `mergeRecords(bundle)`（打卡按 checkedAt 取新 / mealAdjust、tempTasks 按 id 合并，导入优先）+ `replaceRecords(bundle)`（清空后整体写入）
- [x] `lib/providers/settings_provider.dart` 追加 `replaceSettings(data)`（默认值深度合并补缺后整体替换）
- [x] `lib/providers/onboarding_provider.dart` 追加 `replaceOnboarding(data)`；`lib/providers/usage_provider.dart` 追加 `replaceUsage(data)`
- [x] `lib/services/backup_service.dart`（新）：快照聚合（8 项）/ `exportBackup`（写 .txt 到 Download 目录 + 返回路径）/ 解析校验（JSON + 结构校验 + 容错归一）/ 概要统计 / 增量合并 / 覆盖恢复
- [x] `lib/pages/settings/settings_page.dart`：「数据与计划」分组新增「导出历史数据备份 / 导入历史数据备份」两行；导出确认（隐私提示）+ 成功弹窗（路径 + 分享按钮）；导入：选文件 → 读取 → 概要弹层（增量/覆盖/取消）→ 增量风险确认 / 覆盖强确认 → 执行
- [ ] checklist.md 第 10 节全量自测 + 现有功能回归（第 7 节设置相关抽测）

**完成标准**：真机导出 .txt → 微信发送另一设备 → 覆盖导入后计划/打卡/设置/用量与导出时一致、提醒正常调度；增量导入同 id 不重复、打卡不倒退、settings 不被覆盖；选错文件中文报错且数据不变。

## Phase 13 ｜ 本地自动备份（2026-09-03 增补，F9/FR9.7-9.8）

设计依据：[backup-design.md](backup-design.md) v1.1 §11；需求：spec.md FR9.7/FR9.8。Flutter 版实际文件名。

- [x] `lib/services/backup_service.dart`：`exportBackup` 支持固定 `fileName`（单文件覆盖）；新增 `readAutoBackupText` / `autoBackupFileName` / `hasBackupContent`
- [x] `lib/services/auto_backup_service.dart`（新）：`captureBackupData` 8 项快照聚合；防抖 15 秒 / paused 立即写 / 启动 10 秒兜底；内容去重 + 空数据保护两道防线；`_run` 开头**开关门禁**（`autoBackupEnabled` 为 false 不落盘）；全程静默
- [x] `lib/models/settings.dart`：`AppSettings.autoBackupEnabled`（**默认 false**，fromJson 缺字段回落 false，老版本升级不自启）
- [x] `lib/providers/settings_provider.dart`：`update()` 支持 `autoBackupEnabled` patch 持久化；`replaceSettings` 透传开关
- [x] `android/.../MainActivity.kt`：新增 `readFromDownloads`（MediaStore 按名查询 + 老版本直读，异常返回 null）；`writeViaMediaStore` 同名覆盖（免 `xxx (1).txt` 副本）
- [x] `lib/main.dart`：创建并 `attach()` 自动备份服务（挂 5 个 Provider 监听）
- [x] `lib/pages/settings/backup_page.dart`：导入页「自动备份」卡片（更新时间 + 一键恢复 + 文案随开关状态）；覆盖导入前自动留底
- [x] `lib/pages/settings/settings_page.dart`：「自动备份」改**开关行**（`_SwitchRow` 支持副标题，明示保存到系统 Download 目录）；清空全部数据前自动留底
- [x] `test/backup_service_test.dart`：自动备份专项用例（固定文件名 / 单文件覆盖 / hasBackupContent / 读回一致）
- [x] `test/settings_model_test.dart`（新）：开关默认关 / 老数据回落关 / 开启与关闭的序列化往返持久化 共 6 用例
- [ ] checklist.md §10.5（本地自动备份，含开关与持久化）真机自测 + 第 10 节整体回归

**完成标准**：真机上开关默认关，开启后 Download 只有一份 auto 文件且重启不丢开关状态；改数据后退后台 15 秒内更新时间变化；关闭后不再写入；空数据不冲掉好备份；覆盖导入/清空全部前均有带时间戳留底；导入页一键恢复全流程可用。

## Phase 14 ｜ AI 服务商多配置管理（2026-09-04 增补；对应 ai-profile-design.md v1.0，已实现）

设计依据：[ai-profile-design.md](ai-profile-design.md) v1.0；需求：切换服务商 baseUrl 不跟随的 bug + 多服务商仅启用一个 + 已配置项只读不展示。

- [x] `lib/models/settings.dart`：新增 `AiProfile`（id/provider/endpoint/apiKey/model/createdAt，只读）；`AppSettings` 增加 `aiProfiles`/`activeAiProfileId`，`ai` 改为 getter 实时映射激活档案；`fromJson`/`toJson` 支持旧单 `ai` 迁移与备份兼容
- [x] `lib/providers/settings_provider.dart`：删除 `switchProvider`/`updateAI`；新增 `addAiProfile`（保存即启用、上限 5 条）/`activateAiProfile`（只改指针）/`removeAiProfile`（删激活项自动切第一条）；`_load` 与 `replaceSettings` 加迁移与 `kRetiredModelMap` 映射
- [x] `lib/widgets/ai_config_sheet.dart`：改为仅新建模式，切 chip 只改本地表单不持久化，保存调 `addAiProfile`
- [x] `lib/pages/settings/ai_config_page.dart`：重构为配置管理页（列表仅服务商名+配置时间+激活标记，无任何明文 key/endpoint；点击切换确认、滑动/按钮删除、添加复用弹层；测试连接/余额查询作用于激活档案）
- [x] `lib/pages/settings/settings_page.dart`：入口行副标题改为「已启用 {服务商} · {模型} / 未配置」
- [x] `test/backup_service_test.dart`：构造改用 `aiProfiles` 新格式
- [x] `flutter analyze`：No issues found

**完成标准**：切换服务商后 endpoint/key/model 整体跟随（不再出现 A provider + B baseUrl）；列表仅显示服务商名与配置时间；已配置项不可编辑、不展示明文；同一时刻仅一个生效；旧单配置首次升级自动迁移为一条档案并激活；新旧备份格式导入均兼容。

## Phase 15 ｜ 计划条目编辑 AI 估算（2026-09-04 增补；对应 plan-item-ai-estimate-design.md v1.0）

设计依据：[plan-item-ai-estimate-design.md](plan-item-ai-estimate-design.md) v1.0；需求：spec.md FR6.9。编辑器为导入预览（FR1.4）与详情页（FR6.8）共用，两处自动生效。

- [x] `spec/plan-item-ai-estimate-design.md`：交互设计（✨ 按钮/行内拆解展示规避弹层遮挡 SnackBar）、描述拼装规则、专用提示词 kItemCalSys、边界清单与验收要点
- [x] spec.md 增补 FR6.9 + 版本行 v1.6 + 配套文档；README 导航增补；checklist 第 13 节增补；design.md §9.3 函数面表补行
- [x] `lib/services/ai_service.dart`：新增 `kItemCalSys` 提示词与 `estimateItemMeal`（校验 0-5000，返回 {calories, detail}，DeepSeek 禁思考/usage 上报复用 chat 现状）
- [x] `lib/widgets/plan_item_edit.dart`：餐食热量行/运动消耗行 ✨ 按钮（Loading 转圈禁用）、`_mealDesc/_exDesc` 拼装、`_aiEstimate`（ensureAiConfigured → 估算 → 回填 + 行内提示）、Provider 引入（Settings/Usage/Onboarding/Record）
- [x] `flutter analyze` 通过（No issues found）；全量 `flutter test` 108/108（顺手修复 weight_records_test 硬编码「2026-09-03」致跨天必挂的存量缺陷 → 改用 todayStr()）；真机回归两处入口待自测
- [ ] checklist.md 第 13 节真机自测

**完成标准**：编辑器内改食材用量/做法/训练环节后点 ✨ 即得新热量/消耗并展示拆解明细；未配置 Key 引导配置后自动继续；失败原值不变行内报错；两处入口行为一致；不点保存计划数据零变化。

---

## 依赖关系

```
Phase 0 → 1 → 2 → 3 → 4(真机) → 5 → 6 → 7 → 11(引导) → 8(打包)
                   ↑ Flutter 版提醒方案（flutter_local_notifications）已落地，无方案 B 切换问题
Phase 11 复用 Phase 1（normalize）/2（导入动作）/5（AI）/7（设置口径）的现成产物，接入点改动在 Phase 8 打包前完成回归
Phase 12 复用 Phase 1（存储读写模式）/2（文件读取模式）/4（fullReschedule）的现成产物，独立于 Phase 11，随下个安装包发布
```

## 里程碑定义

- M1 可用版（Phase 0-3）：导入计划 + 看到当日任务 + 手动打卡
- M2 合格版（Phase 0-5）：提醒可靠 + 加餐/热量缺口闭环 ← **核心价值达成**
- M3 发布版（Phase 0-8）：统计完善 + 设置齐全 + 打包实跑
- M4 引导完整版（Phase 11）：新装用户「开箱即用」，指引随时回看（随下个安装包发布）
