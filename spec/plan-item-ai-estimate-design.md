# 计划条目编辑 AI 估算设计（plan-item-ai-estimate-design.md）

版本：v1.0（App **已实现**，2026-09-04）｜ 编写日期：2026-09-04
需求来源：主人原话——「编辑器里微调制作方法和食材数量后，热量还是旧计划里的值，想加个 AI 估算按钮；计划详情里相当详细了，应该很好算」
配套：spec.md FR6.9（v1.6 增补）｜ 先例：FR7.10（引导页编辑确认 AI 重估）、FR11.4（今日页编辑弹窗 AI 按新内容重测）

---

## 1. 背景与目标

### 1.1 现状与问题

计划条目全量编辑器 `lib/widgets/plan_item_edit.dart`（`showPlanItemEditor`）被两处共用：

- **导入预览**（`import_page.dart` FR1.4）：点预览条目弹出，保存原位替换 `_preview` 列表；
- **计划详情页**（`item_detail_page.dart` FR6.8）：AppBar「编辑」弹出，保存走 `PlanProvider.replaceItem`。

编辑器可改餐食的食材清单（含用量）/做法步骤/备注与运动的训练环节/分钟数，但**热量/预计消耗是静态输入框**——用户把「鸡胸肉 100g」改成「鸡胸肉 200g」或做法里多了一勺油后，热量仍需自己心算或留旧值，信息（结构化食材+用量+步骤）明明足够 AI 精确估算却用不上。

### 1.2 目标

编辑器内餐食「热量」与运动「预计消耗」旁各加一个 **✨ AI 估算按钮**：点击后把当前编辑中的名称/食材清单（含用量）/做法步骤/备注（或运动名称/时长/训练环节/注意事项）拼装为描述，调 AI 估算，结果**回填对应输入框**并展示拆解明细；用户可再手改，「保存」才落库。

### 1.3 非目标（本期不做）

- 不自动估算（只在用户点击时触发，不偷流量不偷 token）；
- 不改名称/类型/时间/食材/步骤等任何其他字段（运动估算的 name 返回值丢弃，不回填名称）；
- 不做 days/dates 编辑（维持现状，改执行星期/日期仍需重导覆盖）;
- 不做批量估算（编辑器内只有当前这一条）；
- 引导页（FR7.10）与今日页编辑弹窗（FR11.4）的既有 AI 交互不动。

## 2. 功能定位与范围

| 维度 | 说明 |
|------|------|
| 需求归属 | F6 增补（FR6.9）；因编辑器与 FR1.4 导入预览共用，导入预览自动获得同等能力 |
| 与 FR7.10 关系 | 同为「编辑态 AI 重估」，但输入不同：引导页是单行描述（复用 `queryCalorie`/`estimateBurn`）；本编辑器是**结构化食材清单+做法**（新增专用提示词，估算更准） |
| 与 FR11.4 关系 | 交互范式一致（✨ 按钮、配置引导、拆解展示）；FR11.4 面向「实际吃了什么」的口语内容，本编辑器面向「计划配方」的结构化内容，互不影响 |
| 数据安全 | 估算结果只写输入框（可手改），不点「保存」不落库；编辑器「深拷贝编辑、取消不生效」语义不变 |

## 3. 交互设计

### 3.1 按钮位置与样式

- **餐食卡**：「热量 kcal（留空=自由餐）」输入行改为 `Row`：`Expanded(输入框)` + 「✨ AI 测算」紧凑描边按钮（橙色 `AppColors.orange`，fontSize 12，高度与输入框对齐 ≈38px）。
- **运动卡**：「时长（分钟）/预计消耗 kcal」并排行改为三段：`Expanded(时长)` + `Expanded(预计消耗)` + 「✨ AI 算」按钮（同上样式）。hint 宽度已核对可容纳，无需改文案。
- Loading 态：点击后按钮 icon 位换 14×14 转圈（`CircularProgressIndicator(strokeWidth: 2)`，与今日页惯例一致），期间按钮禁用防连点；**保存按钮不禁用**（估算与保存互不阻塞）。
- 两处入口（导入预览/详情页）共用编辑器，自动一致。

### 3.2 结果展示与错误提示（行内，不用 SnackBar）

**关键决策**：估算结果拆解与错误信息都用**编辑器内行内小字**展示，不用 SnackBar——编辑器是 `showModalBottomSheet` 弹层，`ScaffoldMessenger` 的 SnackBar 显示在底层 Scaffold 底部，会被弹层遮挡（既有 `_AdjustSheet` 的 SnackBar 报错即存在此隐患）。

- 估算成功：热量输入行下方追加一行 12px 小字（`AppColors.textSub`）展示 AI 拆解（如「鸡胸肉150g≈250，橄榄油10g≈90，合计570」），常驻显示直到再次估算或关闭弹层；结果已回填输入框。
- 估算失败：同一位置展示橙色错误文案（`e.toString().replaceFirst('Exception: ', '')`），**输入框原值不变**。

## 4. AI 能力设计（ai_service.dart）

### 4.1 新增：estimateItemMeal + kItemCalSys 提示词

餐食估算不复用 `estimateMeal`（其提示词面向「实际吃了什么」的口语描述，FR11.4 专用），新增专用方法与提示词——输入是**计划配方的结构化清单**，强调按用量逐项估算并计入烹饪隐藏热量：

```dart
const String kItemCalSys = '''你是减脂计划餐食的热量估算助手。用户给出一份计划餐食的结构化描述：餐名、食材清单（含用量）、做法步骤、备注。
请按中国常见食物热量，对食材清单逐项按给出的用量估算；做法步骤中提到的烹饪用油/糖/酱料/勾芡等隐藏热量必须计入；未标注用量的食材按常见份量估算。
严格只返回一个 JSON 对象，不要输出任何其他文字：
{"calories":整餐总热量整数kcal,"detail":"一句话拆解，如：鸡胸肉150g≈250，橄榄油10g≈90，合计340"}
备注中提到的替代/增减（如"不放糖"）以备注为准。''';
```

方法签名与校验（与 `estimateMeal` 同构，仅换提示词）：

```dart
/// 计划条目编辑器：整餐热量估算（结构化食材清单+做法），resolve { calories, detail }
Future<Map<String, dynamic>> estimateItemMeal(AiConfig config, String desc,
    {void Function(Map<String, dynamic>)? onUsage}) async
```

- 解析失败 → `Exception('AI 返回格式异常，请手动填写热量')`；数值校验 0–5000（超范围 → `Exception('AI 估算的热量超出合理范围，请手动填写')`），沿用服务层既有口径；
- DeepSeek 思考模式禁用、usage 上报、错误码中文映射全部复用 `chat()` 现状，零改动。

### 4.2 运动：复用 estimateBurn，不动签名

`estimateBurn(config, desc, weight/gender/age/height)` 原样复用：

- **体重口径**：当天生效体重（`weightForDate(store, todayStr())`）优先，回落引导 profile.weight——与今日页/统计页 F10.6 完全同口径。说明：计划条目面向多天执行，不逐日取执行日体重（估算本就是参考值，执行当天仍可在快照上重测）；
- **个人资料**：`profile.complete` 时传 gender/age/height，同 F10.6；
- 返回 `{name, calories, detail}`——**name 丢弃**（不改用户管理的条目名称），calories 回填消耗框，detail 行内展示。

### 4.3 描述拼装规则（编辑器内实现）

餐食（传给 `estimateItemMeal`）：

```
餐名：{name}（{kTypeCn[type]}）          ← name 为空省略此行
食材清单：
- {item} {amount}                        ← item 非空的行；amount 空则只写 item
做法步骤：
1. {step}                                ← 非空步骤按序号列出
备注：{note}                             ← 非空才拼接
```

运动（传给 `estimateBurn` 的 desc）：

```
训练名：{name}（总时长 {duration} 分钟）   ← name 为空省略
训练内容：
- {item}（{minutes}分钟）：{detail}       ← item 非空的行；minutes=0 省略括号
注意事项：{note}                          ← 非空才拼接
```

**有效内容判定**（全空不浪费请求）：餐食 = name 非空 ∨ 存在非空食材 ∨ 存在非空步骤；运动 = name 非空 ∨ 存在非空环节。不满足时按钮提示行内文案「请先填写餐名/食材或训练内容」。

## 5. 状态与依赖（plan_item_edit.dart）

编辑器目前零 Provider 依赖，本次需引入（均为应用级单例，弹层 context 直接 `context.read`，与今日页编辑弹窗同模式）：

| 依赖 | 用途 |
|------|------|
| `SettingsProvider` | `settings.ai` 取激活 AiProfile（内部走 `ensureAiConfigured` 所需） |
| `UsageProvider` | `usage.addUsage` token/次数上报 |
| `OnboardingProvider` | `profile`（运动估算个人资料） |
| `RecordProvider` | `store`（当天生效体重） |
| `ensureAiConfigured`（ai_config_sheet.dart） | 未配置 AI 时弹精简配置层，配好返回 true 继续估算 |

State 新增：`bool _aiLoading = false`、`String? _aiInfo`（拆解/错误行内文案，含状态区分）。

异步纪律：`ensureAiConfigured` 与 AI 请求两处 `await` 之后均 `if (!mounted) return;`（弹层可能中途被关闭，结果丢弃不崩）。

## 6. 代码改动清单（对齐「最小改动」惯例）

| 文件 | 改动 | 量级 |
|------|------|------|
| `lib/services/ai_service.dart` | +`kItemCalSys` 提示词、+`estimateItemMeal` 方法（复制 estimateMeal 换提示词与文案） | ~35 行新增 |
| `lib/widgets/plan_item_edit.dart` | 热量/消耗行加 ✨ 按钮、`_buildMealDesc/_buildExDesc` 拼装、`_aiEstimate(bool isMeal)` 逻辑、`_aiInfo` 行内展示、Provider 引入 | ~110 行新增，无既有逻辑删改 |
| spec 同步 | spec.md（v1.6 + FR6.9）、README 导航、tasks.md Phase 15、checklist 第 13 节、design.md §9.3 函数面表（实现时补） | 文档 |

不触碰：模型层、Provider 层、存储键、备份格式、提醒调度、导入校验、今日页/详情页/导入页页面代码（编辑器对外契约 `showPlanItemEditor` 签名不变）。

## 7. 边界情况

| # | 场景 | 行为 |
|---|------|------|
| 1 | 未配置 AI Key | `ensureAiConfigured` 弹配置层；配好自动继续估算；取消则不估算 |
| 2 | 内容全空就点按钮 | 行内提示「请先填写餐名/食材或训练内容」，不发请求 |
| 3 | AI 超时/网络异常/HTTP 错误 | 行内橙色错误（中文映射），输入框原值不变，可重试 |
| 4 | AI 返回超范围（<0 或 >5000） | 服务层拦截，同失败路径 |
| 5 | 已手填热量被估算覆盖 | 预期行为（估算=用户主动点击），行内拆解可核对，可再手改；未保存前随时可还原为任意值 |
| 6 | 自由餐（热量框为空） | 估算后填入，保存即有热量——正是本功能价值场景之一 |
| 7 | 请求返回时弹层已关闭 | `mounted` 检查丢弃结果，不崩不报错 |
| 8 | 导入预览页使用 | 行为完全一致（共用组件）；预览中估算只影响本条预览数据，确认导入才落库 |
| 9 | 连续多次点击 | Loading 期间按钮禁用，无并发请求 |
| 10 | 非 DeepSeek 服务商 | `chat()` 不传 thinking 字段（现状），估算正常 |

## 8. 风险与限制

- **估算准确性**：用量模糊（如「适量」）时 AI 按常见份量估，拆解明细供核对；估算值永远可手改，不锁定；
- **做法隐藏热量识别**：提示词已强调计入油/糖/酱料，但 AI 漏算个别步骤热量仍可能，属估算类功能的固有误差；
- **token 成本**：单次约 300–600 tokens，走 `apiUsage` 统计（设置页余额弹窗可见），无新增可见成本入口；
- **弹层高度变化**：行内提示使弹层变高一行（~18px），`SingleChildScrollView` 已有，无溢出风险。

## 9. 验收要点（速览）

1. 编辑器内把「鸡胸肉 100g」改为「200g」→ 点 ✨ → 热量回填新值，行内展示逐项拆解；
2. 做法里加「放油 20g」→ 估算结果比改前明显上升（隐藏热量计入）；
3. 未配置 Key → 弹配置层，配好后自动完成本次估算；取消则不动；
4. 断网点击 → 行内中文错误，原热量不变，恢复网络重试成功；
5. 运动改「快走 30 分钟」为「慢跑 40 分钟」→ 消耗回填，拆解含体重口径（detail 可验证）；
6. 估算后不点保存直接关闭 → 计划数据零变化（详情页/导入预览核对）；
7. 导入预览与详情页两处入口行为一致；用量统计 +1（设置页可查）。
