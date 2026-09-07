# 知轻 · 设计文档（spec）

安卓减脂计划打卡提醒 App ｜ Flutter（自 uni-app 迁移，1:1 兼容）｜ 单机离线优先

## 文档导航

| 文档 | 内容 | 读者场景 |
|------|------|----------|
| [spec.md](spec.md) | 需求规格：背景、场景、功能需求（F1-F11 含验收标准）、非功能需求 | 明确做什么、做到什么程度算合格 |
| [design.md](design.md) | 技术设计：选型、架构、页面设计、数据模型、核心算法、**提醒方案（最大风险点）**、AI 查询、食物库、UI 规范、打包 | 怎么实现（v2.0 起为 Flutter 版，以 `lib/` 实际代码为准） |
| [import-format.md](import-format.md) | JSON 导入格式规范：字段表、校验规则、**AI 生成提示词** | 开发校验逻辑 / 用户拿提示词去找 AI 生成计划 |
| [template.json](template.json) | 可直接复制的导入模板（按用户真实减脂餐/运动计划生成的完整示例） | App 内置模板的内容源 |
| [tasks.md](tasks.md) | 开发计划：Phase 0-13 分阶段任务、里程碑 | 按顺序执行开发 |
| [checklist.md](checklist.md) | 测试与验收清单：分模块用例 + 真机矩阵 + 发布前检查 | 每阶段自测、发布前回归 |
| [guide-design.md](guide-design.md) | 首次使用引导 & 使用指引设计方案（v0.2 已评审）：流程、首次判定、只增不改的改动分层 | 了解 F7/F8 的设计推演与范围约束 |
| [backup-design.md](backup-design.md) | 历史数据导入导出设计方案（v1.1，含本地自动备份）：备份文件格式、合并/覆盖规则、热量风险提示、文件读写方案、单文件自动备份与保护规则 | 了解 F9 的设计推演与实现约束 |
| [weight-design.md](weight-design.md) | 体重记录与基础消耗按日沿用设计方案（v1.0，App v1.0.2 **已实现**）：体重录入、历史缺口稳定机制（基准固化 + 按日沿用链）、日历展示、运动 AI 测算结合个人资料、备份 10 项快照 | 了解 F10 的设计推演与实现约束 |
| [day-snapshot-design.md](day-snapshot-design.md) | 当日条目快照与历史固化设计方案·餐食+运动（v1.2，App v1.0.2 **已实现**）：计划=模板/快照=事实、DayEntry 统一模型（内容/热量/备注，kind 区分餐食与运动）、实例化与同步算法、修改即脱钩、AI 单餐单次测算、旧数据→快照（启动迁移 + **v1 老备份导入管线内直接转换**，共用转换核心）、备份 formatVersion 2 | 了解 F11 的设计推演与实现约束 |
| [cloud-sync-design.md](cloud-sync-design.md) | 云端账号与数据同步方案（v0.1 草案，待评审）：技术选型、目标架构、接口契约、快照同步策略、**学习清单与准备清单**、路线图 P0-P4 | 规划「服务器+账号+云同步」时按此学习和采购，拍板后动工 |
| [ai-profile-design.md](ai-profile-design.md) | AI 服务商多配置管理设计方案（v1.0，**设计中待评审**）：AiProfile 配置档案 + 激活指针（修复切服务商 baseUrl 不跟随的 bug）、同刻仅启用一个、已配置项只读不展示（仅服务商名+配置时间）、旧单配置迁移与备份双向兼容 | 了解 AI 服务配置页重构的设计推演与实现约束 |
| [plan-item-ai-estimate-design.md](plan-item-ai-estimate-design.md) | 计划条目编辑 AI 估算设计方案（v1.0，App **已实现**）：条目编辑器（导入预览+详情页共用）热量/消耗旁 ✨ 估算按钮、结构化食材清单+做法的描述拼装与专用提示词（estimateItemMeal）、运动复用 estimateBurn、行内拆解展示（弹层遮挡 SnackBar 规避）与边界清单 | 了解 FR6.9 的设计推演与实现约束 |

## 一句话产品定义

只做三件事——**导入计划（JSON）→ 到点提醒 → 打卡**，外加**热量缺口计算**（加餐/外卖/KFC 查热量）。计划数据由用户找其他 AI 按 [import-format.md](import-format.md) 格式生成，App 只提供模板与提示词。

## 关键设计决策速览

1. **餐食用「周几」周期、运动用「日期范围+周几」双维度**——正好覆盖「周一到五同款午餐」与「9月一三五快走→10月一二四五走跑」的真实结构
2. **`calories: null` 表示自由餐**——周六 KFC 不硬编热量，吃完通过内置食物库/AI 查询补录，自然进入缺口计算
3. **提醒走 flutter_local_notifications（zonedSchedule + AlarmManager）**——重启自恢复、精确闹钟，优于旧版 plus.push；国产 ROM 仍需白名单引导（design.md 第 8 节）
4. **AI 查询走用户自配 Key（OpenAI 兼容）**——零后端零成本，内置 82 条 KFC/外卖库离线兜底
5. **不引入 UI 框架与图表库**——手写组件 + 纯自绘条形/日历图，满足「界面简洁」

## 后续开发入口

工程已在仓库根目录就绪（入口 `lib/main.dart`）。当前状态：**v1.0.2 已实现并落地**（F10 体重记录 + F11 当日快照，备份 formatVersion 2 / 10 项），release APK 见 `build/app/outputs/flutter-apk/`。改动清单与验收见 [weight-design.md](weight-design.md) §8、[day-snapshot-design.md](day-snapshot-design.md) §9；测试与验收按 [checklist.md](checklist.md) 第 11/12 章执行，开发历史见 [tasks.md](tasks.md)。
