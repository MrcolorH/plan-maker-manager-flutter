# AI 服务商多配置管理设计（ai-profile-design.md）

版本：v1.0（2026-09-04）｜ 配套：[spec.md](spec.md) ｜ 关联代码：`models/settings.dart`、`providers/settings_provider.dart`、`pages/settings/ai_config_page.dart`、`widgets/ai_config_sheet.dart`
状态：**已评审并实现（2026-09-04，Flutter 版 v1.3）**

---

## 1. 背景与需求

### 1.1 现状 Bug：切换服务商后基础 URL 不跟随

`AiConfigPage` 的服务商 ChoiceChip 直接调用 `switchProvider()`（`settings_provider.dart:88`），该调用**立即改写并持久化** `settings.ai.provider/endpoint/model`；但页面上的三个 TextEditingController（endpoint / apiKey / model）**不会随之刷新**。后果有两个：

1. 用户切换服务商后点「保存配置」→ `_save()` 把**旧服务商的 endpoint/key/model** 回写进新 provider 的配置 → 出现「切了 DeepSeek 但 baseUrl 还是 Kimi」的脏配置；
2. 用户切换服务商后直接返回（不保存）→ `settings.ai` 已经被 switchProvider 持久化改写，apiKey 却还是旧服务商的（或为空）→ 配置处于半成品状态，AI 调用直接报「未配置/鉴权失败」。

`AiConfigSheet` 里 `_switchProvider` 虽然会同步刷新 controller，但同样是「先持久化、后取消无效」，取消弹层也留下半成品配置。

**根因：单份 `AiConfig` 既承担「正在使用的配置」又承担「编辑表单的数据源」，切服务商是原地改写而非整体切换。**

### 1.2 需求（用户提出）

| # | 需求 |
|---|------|
| R1 | 支持配置**多个** AI 服务商，可随时切换，**同一时刻只能启用一个** |
| R2 | 切换时 endpoint / apiKey / model 作为整体跟随切换，不允许出现「A 家的 provider + B 家的 baseUrl」 |
| R3 | 已配置好的 API（接口地址 / Key / 模型）**禁止修改、不展示明文**；列表只展示**服务商名称 + 配置时间**（用于区分） |
| R4 | 配错了的处理方式 = 删除该配置后重新添加（代替「编辑」） |

---

## 2. 方案总览

把「一份 AI 配置」升级为「**配置档案（Profile）列表 + 激活指针**」：

1. 新增 `AiProfile`：一次完整配置（provider + endpoint + apiKey + model + createdAt），创建后**只读**；
2. `AppSettings` 持有 `aiProfiles: List<AiProfile>` 与 `activeAiProfileId: String`；AI 调用永远取 `activeProfile`；
3. 「切换服务商」从「原地改写字段」改为「切换激活指针」，endpoint/key/model 天然整体跟随（修复 R2）；
4. 设置页改为**配置管理页**：列表只显示服务商名 + 配置时间 + 激活标记；「添加配置」复用现有 `AiConfigSheet`（仅新建场景可编辑字段，R3）。

---

## 3. 数据模型（`models/settings.dart`）

### 3.1 AiProfile（新增）

```dart
class AiProfile {
  final String id;        // 时间戳毫秒 + 随机后缀，如 '1756953600000-37f2'
  final String provider;  // kAiProviders 的 value（deepseek/kimi/mimo/minimax/custom）
  final String endpoint;
  final String apiKey;
  final String model;
  final int createdAt;    // 配置时间（毫秒），列表区分同服务商多条配置的唯一依据
}
```

- `createdAt` 在「保存配置成功」那一刻生成，之后不可变；
- 不需要 label/备注字段——按 R3，同服务商多条配置就用配置时间区分。

### 3.2 AppSettings 扩展（存储键仍是 `settings`，向后兼容）

```dart
AppSettings({
  ...
  List<AiProfile>? aiProfiles,   // 新增
  String? activeAiProfileId,     // 新增；空串 = 未激活
  AiConfig? ai,                  // 保留：仅为旧版本备份/旧存储兼容
})
```

`toJson()` 同时写出 `ai`（= 当前激活 profile 的快照）与 `aiProfiles`/`activeAiProfileId`。`ai` 继续冗余写出有两个目的：

- 旧版本 App 读新备份时字段不缺（备份降级兼容）；
- 新代码里 `hasConfig`、各调用点（`today_page` / `stats_page` / `food_add_page` / `import_page` 直接引用 `settings.ai`）**零改动**——`ai` 的 getter 改为从激活 profile 实时映射。

### 3.3 迁移（`SettingsProvider._load` 与备份导入共用）

```
读入 settings JSON 后：
1. 若 aiProfiles 非空 → 直接使用；校验 activeAiProfileId 存在于列表，否则回退到第一条/清空
2. 若 aiProfiles 为空且旧 ai.apiKey 非空 →
     aiProfiles = [AiProfile(id: gen, ...旧 ai 四字段, createdAt: 挂载时刻的当前时间)]
     activeAiProfileId = 该条 id        // 一次性迁移，随后回写存储
3. 否则（从未配置）→ aiProfiles = []，activeAiProfileId = ''
```

- 迁移时间用「首次升级运行时刻」，旧数据没有记录过配置时间，这是能做到的最优近似；该条配置展示为「此前配置 · yyyy-MM-dd」可在 UI 上对 createdAt 为迁移标记的条目加「（迁移）」后缀，不做也可以（本期从简：直接显示迁移时刻）。
- `replaceSettings`（备份覆盖导入）走同一迁移函数：旧备份只有 `ai` 字段 → 自动转成一条 profile；新备份直接读 `aiProfiles`。导入后若激活 id 不在列表中，回退规则同上。

### 3.4 生效配置的取值（`AppSettings` getter）

```dart
AiConfig get ai => activeProfile == null
    ? AiConfig()                       // 未配置：保持现有默认值行为
    : AiConfig(provider: p.provider, endpoint: p.endpoint, apiKey: p.apiKey, model: p.model);
```

`hasConfig` 语义不变（激活 profile 存在且 key/endpoint 非空）。**所有 AI 调用点不需要感知 Profile 的存在。**

已核对的间接依赖（同样经 getter 兼容，零改动）：`backup_service.dart` 导出预览的 `hasAiKey: settings.ai.apiKey.isNotEmpty`（备份文件里标记是否含 AI Key）——未激活时 getter 返回空 `AiConfig`，标记自然为 false，语义正确。

---

## 4. 状态层（`providers/settings_provider.dart`）

删除 `switchProvider(String provider)` 与现 `updateAI` 的字段级 patch 语义，替换为三个原子操作：

| 方法 | 行为 |
|------|------|
| `addAiProfile(AiConfig cfg) → AiProfile` | 校验 endpoint/key 非空 → 生成 id/createdAt → 追加进列表 → **立即激活** → 持久化。列表上限 **5 条**，超限时拒绝并提示「请先删除旧配置」 |
| `activateAiProfile(String id)` | 仅改 `activeAiProfileId` → 持久化。不触碰任何 profile 内容（R2 的修复点） |
| `removeAiProfile(String id)` | 从列表移除；若删除的是激活项 → 自动激活剩余第一条（无剩余则清空激活指针）→ 持久化 |

- 旧 `updateAI` 仅保留给 `AiConfigSheet` 保存路径内部使用（实际改为调 `addAiProfile`），对外不再暴露「只改 provider 不改 endpoint」的可能。
- `kRetiredModelMap` 迁移逻辑保留，改为在**激活 profile 被解析时**应用（幂等，命中即回写该 profile 的 model）。

---

## 5. UI 设计

### 5.1 AI 服务页（`ai_config_page.dart` 重构）

```
┌ AI 服务 ────────────────────────────┐
│ 配置列表（≤5 条）                     │
│ ┌──────────────────────────────┐   │
│ │ ● DeepSeek        2026-09-04  │   │  ← 激活项：左侧主色圆点/勾
│ │   配置于 2026-09-04 14:32      │   │
│ ├──────────────────────────────┤   │
│ │ ○ Kimi（月之暗面）              │   │  ← 未激活：点击 → 确认弹窗 → 激活
│ │   配置于 2026-08-21 09:10      │   │
│ └──────────────────────────────┘   │
│                                    │
│ [ + 添加新配置 ]  ← 打开配置弹层(可编辑)│
│                                    │
│ ┌ 余额查询（仅 DeepSeek）/ 本App用量 ┐│  ← 原有卡片，针对当前激活配置
│ └────────────────────────────────┘ │
└────────────────────────────────────┘
```

交互细节：

- **列表行**：只显示 `kAiProviders` 的 label + 「配置于 yyyy-MM-dd HH:mm」（R3：不展示 endpoint/key/model，任何形式都不展示，包括遮码 `sk-****`）；
- **点击未激活行** → `AlertDialog` 确认「切换到 DeepSeek（配置于 09-04）？当前启用：Kimi」→ 确认后 `activateAiProfile`；
- **删除**：每行右侧滑动（`Dismissible`）或长按弹出「删除此配置」，确认文案提醒「删除后无法恢复，需重新填写 Key」；
- **添加新配置**：跳转/弹出复用后的 `AiConfigSheet`（见 5.2），保存成功 = 新 profile 创建并立即激活；
- **激活配置的功能操作**：「测试连接」「余额查询」按钮作用于**当前激活 profile**，直接用其配置发请求——不需要把 key 显示出来就能测试（原有 `_currentConfig()` 从 controller 读值的逻辑改为读激活 profile）；
- 配置列表为空时：整页只剩「添加新配置」+ 引导文案（首次配置路径与现在一致）。

### 5.2 配置弹层（`ai_config_sheet.dart` 调整）

- **仅保留「新建」一种模式**。服务商 chips + endpoint/key/model 三个输入框 + 测试连接，全部照旧（这是唯一能看到输入框的地方）；
- `onSelected` 切换 chip 时**只更新本地表单 controller**（endpoint/model 按预设预填，key 清空），**不再调用任何持久化方法**——半成品配置问题从源头消除；
- 「保存并使用」→ `addAiProfile` → pop(`configured`)；
- `ensureAiConfigured` 判定条件从 `settings.ai.hasConfig` 改为「存在激活 profile」（等价，经 3.4 的 getter 自动成立，无需改动）；
- 引导页（onboarding）走同一弹层，无感知变化。

### 5.3 设置页入口行（`settings_page.dart:74`）

`_Row('AI 服务', ...)` 副标题改为 `已启用 DeepSeek · deepseek-v4-flash`；未配置时 `未配置`。不展示配置时间（那是管理页的区分信息）。

---

## 6. 边界情况

| 场景 | 行为 |
|------|------|
| 同一服务商配置两条（如换了个 Key） | 允许，靠配置时间区分；新配置保存即激活，旧的保留可切回 |
| 删除全部配置 | 回到未配置态，AI 入口重新走 `ensureAiConfigured` 弹层 |
| 激活的 DeepSeek 配额用尽，想临时切 Kimi | 列表点 Kimi 确认即可，endpoint/key/model 整体切换（R2 场景） |
| 备份覆盖导入（旧格式备份） | `ai` 单配置 → 迁移为一条 profile 并激活（§3.3） |
| 备份覆盖导入（新格式备份） | `aiProfiles` 整组带入，激活 id 校验后生效 |
| 老版本 App 读新备份 | 冗余的 `ai` 字段保证可导入单配置（降级兼容） |
| 「自定义」服务商 | 照常作为一条 profile；endpoint 为空校验拦截 |
| UsageProvider 统计 | 维持全局口径不分 provider（本期不做按服务商分账，成本估算本来也只对 DeepSeek 精确） |

---

## 7. 不做的事（明确出范围）

1. **不提供已配置项的任何编辑能力**（含「只改模型名」）——改 = 删了重配；
2. **不做按服务商的用量/费用分账**——UsageProvider 仍是全局单值；
3. **不做 Key 加密存储**——与现状一致，仍明文存本机 `settings` 键（与「仅存本机」承诺一致，加密是独立议题）；
4. **不做配置去重/合并**——同服务商多条配置是特性不是脏数据。

---

## 8. 测试要点（`test/` 新增用例）

1. 迁移：旧 JSON（仅 `ai`，key 非空）load 后生成 1 条 profile 且激活；
2. 迁移：旧 JSON key 为空 → 无 profile、未激活；
3. `addAiProfile` 后 `settings.ai` getter 返回新 profile 内容（endpoint 跟随，R2 回归）；
4. `activateAiProfile` 只改指针，原两条 profile 内容均不变；
5. `removeAiProfile` 删除激活项 → 自动激活剩余第一条；删空 → `hasConfig == false`；
6. 备份 round-trip：新格式导出 → 导入后 profiles 数量/激活 id 一致；旧格式（仅 `ai`）导入 → 迁移成一条；
7. 超过 5 条上限被拒；
8. `kRetiredModelMap`：激活 profile 含 `deepseek-chat` → 解析时映射为 `deepseek-v4-flash`；
9. UI 层（手测清单）：配置页无任何明文 key/endpoint 展示；切换确认弹窗；添加→保存→自动激活→立即测试连接成功。
