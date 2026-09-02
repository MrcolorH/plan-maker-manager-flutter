# 历史数据导入导出设计（backup-design.md）

版本：v1.0 ｜ 编写日期：2026-09-01 ｜ 关联需求：spec.md F9
功能范围：设置页「数据与计划」分组新增 **导出历史数据备份** / **导入历史数据备份**，解决换机/重装后的数据迁移。

---

## 1. 目标与场景

| 场景 | 描述 | 期望结果 |
|------|------|----------|
| B1 换新手机 | 旧机导出备份（.txt）→ 发给新机（微信/QQ/网盘均可）→ 新机导入 | 计划 + 打卡 + 设置全部迁移，即导即用 |
| B2 卸载重装 | 重装前导出 → 重装后导入 | 数据不丢，无需重新生成计划 |
| B3 双设备并存 | 两台手机交替使用，偶尔互相补充数据 | 增量导入合并，不互相覆盖丢失 |
| B4 误删恢复 | 误清空数据后 | 覆盖导入回到导出时的状态 |

**核心原则**：导出文件是一个 `.txt` 纯文本文件（内容即 JSON 文本），文件名全 ASCII（zhiqing = 「知轻」拼音 + 时间戳），避免中文名在微信/网盘等传输链路截断或乱码；大小控制在几百 KB 内（符合非功能需求「单键数据量 ≤ 几百 KB」）。

## 2. 数据范围（导出 = 全量快照）

| 存储键 | store 模块 | 内容 | 导出 |
|--------|-----------|------|------|
| `planData` | store/plan.js | 计划版本、meta（含 startedAt）、meals、exercises、deletedIds | ✅ |
| `checkRecords` | store/record.js | 打卡：{ date: { "type:id": { checkedAt } } } | ✅ |
| `mealAdjust` | store/record.js | 当日每餐实际热量覆盖：{ date: { "type:id": { calories, note } } } | ✅ |
| `tempTasks` | store/record.js | 临时任务（加餐/临时运动）：{ date: [...] } | ✅ |
| `extraFoods` | store/record.js | 旧版加餐记录（已迁移，通常为空，兼容保留） | ✅ |
| `settings` | store/settings.js | TDEE/bmr/目标摄入/提醒设置/AI 配置（**含 API Key**） | ✅ |
| `onboardingState` | store/onboarding.js | 引导完成状态 + profile | ✅ |
| `apiUsage` | store/usage.js | AI 调用次数/tokens/估算费用 | ✅ |

**隐私说明**：备份包含 AI API Key。导出前与覆盖导入前均需向用户明示「备份含 AI 配置（API Key），请妥善保管」；增量导入**不触碰** settings/onboarding/apiUsage（不覆盖本机 Key 与统计）。

## 3. 备份文件格式

文件名：`zhiqing-backup-YYYYMMDD-HHmmss.txt`（写入系统 Download 目录，便于用户查找与分享）。

```json
{
  "app": "jianfeidazi",
  "type": "backup",
  "formatVersion": 1,
  "exportedAt": "2026-09-01T16:20:00+08:00",
  "appVersion": "1.0.0",
  "data": {
    "planData": { "version": "1.0", "meta": { "startedAt": "2026-09-01", ... }, "meals": [], "exercises": [], "deletedIds": [] },
    "checkRecords": { "2026-09-01": { "meal:m-xxx": { "checkedAt": 1788312000000 } } },
    "mealAdjust": { "2026-09-01": { "meal:m-xxx": { "calories": 440, "note": "只吃了包子" } } },
    "tempTasks": { "2026-09-01": [{ "id": "t-xxx", "type": "snack", "name": "水煮蛋", "time": "15:00", "calories": 100, "source": "food-db" }] },
    "extraFoods": {},
    "settings": { "tdee": 2000, "bmr": 1650, "dailyCalorieTarget": 1400, "reminderEnabled": true, "reminderAdvance": 0, "ai": { "provider": "deepseek", "endpoint": "...", "apiKey": "sk-...", "model": "deepseek-v4-flash" } },
    "onboardingState": { "done": true, "profile": { "gender": "male", "age": 30, "height": 175, "weight": 74, "activity": 1.2 } },
    "apiUsage": { "calls": 12, "promptTokens": 34000, "cacheHitTokens": 1000, "completionTokens": 8000 }
  }
}
```

字段约定：
- `app` / `type` / `formatVersion`：识别标识，导入校验必检（防误选其他文件）。
- `exportedAt` / `appVersion`：展示与溯源信息，不参与逻辑。
- `data`：各存储键原样快照（`JSON.parse(JSON.stringify(...))`），保证结构零损。

## 4. 导入校验与容错

1. 选择文件（App 端 `pickBackupFile(['txt','dat','json'])` 走 SAF 系统文件选择器，见 6.2；H5/小程序端降级提示）→ 按**纯文本**读取（当前导出格式为 .txt，旧版 .dat 备份内容同为 JSON 文本，`FileReader.readAsText` 与扩展名无关，按纯文本读取即可兼容旧文件）。
2. `JSON.parse` 失败 → 中文报错「备份文件格式错误，请确认选择了正确的备份文件」。
3. 结构校验：根对象 + `app==='jianfeidazi'` + `type==='backup'` + `formatVersion===1` + `data` 为对象；任一不满足 → 报错并中止。
4. 容错归一（防御老版本/手工编辑）：`data.planData.meals/exercises` 非数组视为空数组；`meta` 缺失补 `{}`；`settings` 用 DEFAULTS 深度合并补缺字段；`onboardingState` 补默认；`checkRecords/mealAdjust/tempTasks/extraFoods` 非对象视为 `{}`。
5. 校验通过后展示**备份概要**（导出时间、计划餐食/运动条数、打卡天数、打卡条数、临时任务条数、是否含 AI Key），再让用户选导入方式。

## 5. 导入方式

### 5.1 增量导入（B3 双设备场景；默认推荐？—— 否，两方式平级，由用户判断）

合并规则（**导入文件优先**，同 key 覆盖、新 key 追加；唯一例外是打卡时间戳）：

| 数据 | 合并规则 |
|------|----------|
| planData | 走现有 `importPlan(backup.planData)`：含 meals 合并餐食、含 exercises 合并运动（同 id 更新、新 id 追加、另一模块不受影响）；meta 部分字段（planName/startDate/endDate/体重目标/tdee/目标摄入）有值即覆盖；`meta.startedAt` 保留本机现值，本机为空时回填备份值 |
| checkRecords | 逐 date 逐 key：两方都有 → 保留 `checkedAt` **较大**的一方（最新打卡状态优先）；仅备份有 → 补入。防止把新设备已打卡的项倒回未打卡 |
| mealAdjust | 备份覆盖同 key（调整有明确来源，以备份为准），新 key 追加 |
| tempTasks | 按 date 列表按 id 合并：同 id 取备份（覆盖），新 id 追加 |
| extraFoods | 同上（通常为空，兼容保留） |
| settings / onboardingState / apiUsage | **不合并**（保持本机现值，避免覆盖本机 AI Key / 引导状态 / 用量统计） |

**热量计算异常风险（必须提示）**：打卡/调整/临时任务都通过 `type:id` 引用计划项。增量导入若更新了某计划项的 `calories`，会导致**历史日期**按新热量重算——之前某天的已摄入/缺口数值与导出时不同（不是数据损坏，是口径变化）。因此：
- 增量导入确认弹窗必须提示：「增量合并可能导致历史日期热量统计变化（如计划项热量被备份覆盖）；建议先将不同版本数据分别导出备份，以便追溯」。
- 完成后沿用现有 `importPlan` 的提醒重调度（`fullReschedule`），当日/次日提醒立即生效。

### 5.2 覆盖导入（B1/B2/B4 换机/重装/误删恢复场景）

全量替换 = 恢复到导出时刻的状态：

| 数据 | 动作 |
|------|------|
| planData | `replacePlan`：整体替换 + persist + `fullReschedule` |
| checkRecords / mealAdjust / tempTasks / extraFoods | `replaceRecords`：清空现有四类记录后写入备份数据 |
| settings | `replaceSettings`：DEFAULTS 深度合并补缺后整体替换（**含 AI Key**）+ persist + `fullReschedule` |
| onboardingState | `replaceOnboarding`：整体替换（含 done 与 profile） |
| apiUsage | `replaceUsage`：整体替换 |

**确认要求（强确认）**：覆盖导入会删除本机当前全部数据，且备份含 API Key，弹窗文案必须同时说明两点：
1. 「将清空并替换本机全部数据（计划/打卡/设置/AI 配置），当前数据不可恢复，建议先导出备份」；
2. 「备份含 AI API Key，将一并恢复；请确认文件来源可信」。

### 5.3 共性

- 导入成功 → toast「导入成功」；增量导入成功后当日/次日提醒重新调度。
- 导入失败（解析/校验/合并异常）→ `showModal` 中文错误，当前数据不变（先解析后写入，任何一步失败不落库）。

## 6. 文件读写技术方案（APP-PLUS / 安卓）

### 6.1 导出写入

```
plus.io.requestFileSystem(plus.io.PUBLIC_DOWNLOADS, fs => {
  fs.root.getFile(fileName, { create: true }, entry => {
    entry.createWriter(writer => {
      writer.onwrite = ok
      writer.onerror = fail
      writer.write(jsonText)     // 直接写字符串
    }, fail)
  }, fail)
})
```

- `PUBLIC_DOWNLOADS` 在安卓映射系统 Download 目录，用户可在文件管理器/微信中直接找到并发送。
- 写入成功后弹窗展示完整路径 + 「分享文件」按钮（`plus.share.sendWithSystem({ type:'file', files:[path] })` 调系统分享），实现一键发到新设备。
- 失败兜底：提示「导出失败，请检查存储空间后重试」。
- 同名文件覆盖：文件名含秒级时间戳，天然避免冲突。

### 6.2 导入读取

- **选文件**：`uni.chooseFile` 在 **App 端不支持**（仅 H5 / 微信小程序），改用 `pickBackupFile(extensions)`（`utils/backup.js`）：
  - Android 走 `plus.android` + `Intent.ACTION_OPEN_DOCUMENT`（SAF 系统文件选择器）
  - `CATEGORY_OPENABLE` 必加（EMUI 等 ROM 否则不显示文件）
  - `setType('*/*')` 不做 MIME 过滤（`.dat/.txt/.json` 无标准 MIME，过滤会选不到）
  - 接管 `main.onActivityResult`（请求码 10086；非本码透传原回调、用完还原，避免泄漏）；返回路径 = `plus.android.resolveNativeUri(uri)` 转本地路径 —— ⚠️ **该 API 非所有 HBuilderX 版本/设备实现，必须 `typeof` 探测存在才调用**，否则直接传 `uri.toString()`（content://）交给 `readBackupFile`
  - 顺带 `takePersistableUriPermission` 申请持久读取权限（部分 ROM 重启后仍可读，失败忽略）
  - iOS / 非 App 环境 reject，由调用方 toast 降级
- **读取**：`readBackupFile(path)` 兼容三种入参 —— 本地路径 / `file://` / `content://`：
  - 本地路径与 `file://`：`plus.io.resolveLocalFileSystemURL` → `FileReader.readAsText(utf-8)`
  - `content://`：`plus.io` 按规范不认 content 协议，**直接**走 `ContentResolver.openInputStream(Uri.parse(...))` + `BufferedReader` 按行读取（finally 关闭流），适配 SAF 返回的 URI
- 调用点：`settings.vue` 的 `importBackupAction()`、`import.vue` 的 `pickFile()` 均改调 `pickBackupFile()`；`import.vue` 的 `readFileText()` 委托 `readBackupFile()`（消除两处重复读取实现）

## 7. 页面与交互设计（设置页）

「数据与计划」分组，位于「清空打卡与加餐记录」**上方**：

```
数据与计划
├── 导出历史数据备份        (.txt 文件)     ›
├── 导入历史数据备份        (增量 / 覆盖)   ›
├── 清空打卡与加餐记录      ›
├── 清空餐食计划（N 项）    ›
├── 清空运动计划（N 项）    ›
└── 清空全部数据            (红色)          ›
```

交互流程：

```
导出：点「导出历史数据备份」→ showModal 确认（内容说明 + 隐私提示含 API Key）
      → 写入 Download → 成功弹窗：文件路径 + 「分享文件」+「完成」
导入：点「导入历史数据备份」→ 选择 .txt/.dat/.json → 读取+校验
      → 失败：showModal 报错
      → 成功：模式选择弹层（备份概要 + 三按钮：增量导入 / 覆盖导入 / 取消）
        ├── 增量导入 → showModal 风险提示（热量统计变化 + 建议分版本导出备份）→ 确认 → 合并 → toast 成功
        └── 覆盖导入 → showModal 强确认（清空替换全部 + API Key 恢复 + 建议先导出）→ 确认 → 替换 → toast 成功
```

## 8. 代码改动清单（只增不改约束）

| 文件 | 改动 | 性质 |
|------|------|------|
| `app/utils/backup.js` | **新增**：导出/解析/合并/替换/概要统计 | 新增 |
| `app/store/plan.js` | 追加 `replacePlan(data)` | 小函数 |
| `app/store/record.js` | 追加 `mergeRecords(bundle)` / `replaceRecords(bundle)` | 小函数 |
| `app/store/settings.js` | 追加 `replaceSettings(data)` | 小函数 |
| `app/store/onboarding.js` | 追加 `replaceOnboarding(data)` | 小函数 |
| `app/store/usage.js` | 追加 `replaceUsage(data)` | 小函数 |
| `app/components/tabs/settings.vue` | 「数据与计划」分组新增两行入口 + 导出/导入流程弹窗 | 增补 |
| `app/utils/backup.js` | **追加** `pickBackupFile`（SAF 选文件）+ `readBackupFile` 兼容 content:// | 增补 |
| `app/pages/import/import.vue` | `pickFile()` 改调 `pickBackupFile`；`readFileText()` 委托 `readBackupFile` | 修改 |

## 9. 风险与限制

| 风险 | 等级 | 说明与缓解 |
|------|------|-----------|
| 增量导入改变历史热量口径 | 中 | 属预期行为：弹窗明示 + 建议分版本备份；数据本身不损坏 |
| 备份含 API Key 泄露 | 中 | 导出/覆盖导入均提示保管与来源可信；增量导入不覆盖本机 Key |
| Download 目录不可写（极少 ROM） | 低 | 失败 toast 引导重试；不引入权限申请（写入公共目录通常无需额外权限，如失败用 `_doc` 私有目录兜底） |
| 备份文件被手工编辑损坏 | 低 | 结构校验 + 容错归一，失败即中止且不落库 |
| 大文件（打卡近 400 天 × 多项） | 低 | 全量 JSON 预估 < 1MB（checkRecords 每个 key 仅 {checkedAt}），导出/解析为同步操作可接受；不做分页 |
| iOS 端无法用 SAF 选文件 | 中 | `pickBackupFile` 在非 Android 平台 reject，toast 降级提示「请在系统文件 App 中手动选择」；iOS 完整支持需原生插件（UIDocumentPicker），本期不做 |
| 部分 ROM 文件选择器差异 | 低 | CATEGORY_OPENABLE 必加、setType('*/*') 全量展示、content:// 读取双路径兜底，覆盖主流 ROM |
| onActivityResult 接管泄漏 | 低 | 请求码 10086 唯一 + 非本码透传原回调 + 回调后还原，不影响页面其他 intent 结果 |
| `plus.android.resolveNativeUri` 不存在 | 中 | 部分 HBuilderX 版本/设备未实现该方法（真机实测报 `is not a function`）；已改 `typeof` 探测防御式调用，缺失时直传 content:// 走 ContentResolver 读取 |

## 10. 验收要点（速览）

1. 导出生成 `zhiqing-backup-*.txt`，内容为合法 JSON，`app/type/formatVersion` 正确，data 含全部 8 项。
2. 文件可通过微信发送并在另一设备导入（覆盖）→ 计划/打卡/设置/用量与导出时一致；提醒正常调度。
3. 增量导入：同 id 计划更新不重复；打卡按 checkedAt 取新；tempTasks 按 id 合并；settings 不被覆盖。
4. 导入前必见备份概要；增量前必见热量风险提示；覆盖前必见强确认。
5. 选错文件/坏 JSON → 中文报错，本机数据不变。
