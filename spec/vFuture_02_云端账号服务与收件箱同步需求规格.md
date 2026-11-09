# 知轻 · 云端账号服务、多用户安全隔离与收件箱 (Inbox) 同步需求规格说明书

- **文档版本**：v1.0.0
- **所属版本**：vFuture_02
- **归档路径**：`spec/vFuture_02_云端账号服务与收件箱同步需求规格.md`
- **前置文档**：`spec/vFuture_01_云端账号与数据同步方案草案.md`、`spec/v1.0.0_06_数据备份与恢复设计.md`
- **状态**：**已定稿（待开发实施）**

---

## 1. 核心定位与设计原则

1. **单机离线优先（铁律不变）**：
   - App 本地 `shared_preferences` 仍然是打卡记录的唯一事实源；
   - 离线、断网或服务端异常，**绝不阻塞任何打卡与日常查看流程**。
2. **多用户严格行级隔离（零越权 IDOR）**：
   - 服务端同时服务少数几个用户（如家庭、情侣、朋友）；
   - 所有数据读写**绝不信任客户端入参的 `user_id`**，完全基于 JWT 密文解析，物理杜绝串号或越权篡改。
3. **“云端收件箱（Inbox）”增量事件流**：
   - 外部系统（如本地 QQMatrix 机器人）产生的食物识别打卡，不直接暴力修改全量快照，而是作为独立的“待入库事件”落入收件箱；
   - 手机 App 联网时拉取待入库条目，调用原生的 `RecordProvider.addDayEntry()` 消化入库，**从根本上规避全量版本合并冲突**。

---

## 2. 系统架构全景

```
┌────────────────────────────────────────────────────────┐
│                   本地宿主机 (Mac / PC)                 │
│                                                        │
│  ┌───────────────────┐        内网 127.0.0.1 HTTP        │
│  │   QQMatrix 机器人 │ ──────────────────────┐         │
│  │ (/food 技能识别)  │                       │         │
│  └───────────────────┘                       ▼         │
│                              ┌───────────────────────┐ │
│                              │   知轻本地同步服务端   │ │
│                              │  (Node Fastify/SQLite)│ │
│                              │   - users 表          │ │
│                              │   - user_qq_bindings  │ │
│                              │   - pending_entries   │ │
│                              │   - sync_snapshots    │ │
│                              └───────────────────────┘ │
│                                          ▲             │
│                                          │             │
│  ┌──────────────────────┐                │ 本地反向代理 │
│  │  cloudflared tunnel  │ ───────────────┘             │
│  └──────────────────────┘                              │
└─────────────────────▲──────────────────────────────────┘
                      │ Cloudflare 边缘节点 (HTTPS 443)
                      │ 域名: https://api.yourdomain.top
                      │
           ┌──────────┴──────────┐
           │   知轻 Flutter App   │
           │      (手机移动端)    │
           └─────────────────────┘
```

---

## 3. 服务端数据模型设计 (SQLite)

### 3.1 核心表结构

```sql
-- 1. 用户基础表
CREATE TABLE users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT NOT NULL UNIQUE,             -- 登录账号
  password_hash TEXT NOT NULL,                    -- argon2id / bcrypt 密文
  created_at    INTEGER NOT NULL                  -- Unix 时间戳 (秒)
);

-- 2. 邀请码表 (封闭式私有部署防恶意注册)
CREATE TABLE invite_codes (
  code          TEXT PRIMARY KEY,
  is_used       INTEGER DEFAULT 0,
  used_by       INTEGER REFERENCES users(id),
  created_at    INTEGER NOT NULL
);

-- 3. QQ 账号绑定表 (安全防串号核心)
CREATE TABLE user_qq_bindings (
  qq_id         TEXT PRIMARY KEY,                 -- QQ 号 (来自 OneBot 真实签名)
  user_id       INTEGER NOT NULL UNIQUE REFERENCES users(id),
  bound_at      INTEGER NOT NULL
);

-- 4. QQ 绑定临时配对码表 (5分钟时效)
CREATE TABLE qq_bind_tokens (
  token         TEXT PRIMARY KEY,                 -- 6 位纯数字 (如 "839102")
  user_id       INTEGER NOT NULL REFERENCES users(id),
  expires_at    INTEGER NOT NULL
);

-- 5. 待录入收件箱表 (Pending Inbox)
CREATE TABLE pending_entries (
  id            TEXT PRIMARY KEY,                 -- UUIDv4
  user_id       INTEGER NOT NULL REFERENCES users(id),
  date          TEXT NOT NULL,                    -- "YYYY-MM-DD"
  slot          TEXT NOT NULL,                    -- "breakfast" | "lunch" | "dinner" | "snack"
  content       TEXT NOT NULL,                    -- "米饭 + 煎鸡胸肉"
  calories      INTEGER NOT NULL,                 -- 525
  protein       INTEGER,                          -- 35 (g)
  carbs         INTEGER,                          -- 60 (g)
  fat           INTEGER,                          -- 12 (g)
  detail        TEXT,                             -- AI 分析原句
  items_json    TEXT,                             -- 食材拆解 JSON 字符串
  source        TEXT DEFAULT 'qq_bot',            -- 数据来源标识
  created_at    INTEGER NOT NULL,
  is_consumed   INTEGER DEFAULT 0                 -- 0: 待手机拉取, 1: 手机已处理
);

-- 6. 全量数据冷备份快照表 (延续 F9 / vFuture_01 规范)
CREATE TABLE sync_snapshots (
  user_id           INTEGER PRIMARY KEY REFERENCES users(id),
  payload           TEXT NOT NULL,                -- 8项快照 JSON (已剔除 aiApiKey)
  device_name       TEXT,
  client_updated_at INTEGER,
  server_updated_at INTEGER NOT NULL
);
```

---

## 4. 服务端接口设计

### 4.1 内网受限接口（仅监听 `127.0.0.1`，公网不可访问）

* **`POST /internal/inbox/push`**
  * **调用方**：QQMatrix 后置动作 Hook
  * **入参**：
    ```json
    {
      "qqId": "10001",
      "date": "2026-11-09",
      "slot": "lunch",
      "content": "米饭 + 煎鸡胸肉",
      "calories": 525,
      "protein": 35,
      "carbs": 60,
      "fat": 12,
      "items": [
        {"name": "米饭", "portion": "150g", "calories": 175},
        {"name": "煎鸡胸肉", "portion": "150g", "calories": 350}
      ]
    }
    ```
  * **处理逻辑**：
    1. 查 `user_qq_bindings`，找到 `qqId` 绑定的 `user_id`；
    2. 若未绑定，返回 `404 {error: "UNBOUND_QQ"}`；
    3. 若绑定成功，生成 UUID 插入 `pending_entries`（`is_consumed = 0`），返回 `200 {id: "..."}`。

### 4.2 公网业务接口（通过 Cloudflare Tunnel 暴露，需 JWT 鉴权）

| 路径 | 方法 | 鉴权 | 核心说明 |
|---|---|---|---|
| `/api/v1/auth/register` | POST | 否 | 用户名 + 密码 + 邀请码注册 |
| `/api/v1/auth/login` | POST | 否 | 登录换取 JWT (30 天有效) |
| `/api/v1/account/qq-bind-code` | POST | 是 | 生成 6 位有效期 5 分钟的绑定码 |
| `/api/v1/inbox/pending` | GET | 是 | 拉取当前登录用户 `is_consumed=0` 的所有新记录 |
| `/api/v1/inbox/ack` | POST | 是 | 传入 `ids: [UUID]`，将记录更新为 `is_consumed=1` |
| `/api/v1/sync/snapshot` | PUT | 是 | 周期性全量快照备份（带 serverUpdatedAt 比对） |
| `/api/v1/sync/snapshot` | GET | 是 | 恢复/拉取最新全量快照 |

---

## 5. 知轻 Flutter 客户端改造规范

### 5.1 依赖项
* 网络库：已具备 `dio: ^5.7.0`；
* 安全存储：建议引入 `flutter_secure_storage` 存储 JWT Token（避免明文进 `shared_preferences`）。

### 5.2 新增 `SyncService`（单例）
1. **自动轮询/前台唤醒拉取**：
   * 监听 App 生命周期 `AppLifecycleState.resumed`；
   * 调用 `GET /api/v1/inbox/pending`；
   * 遍历条目，依次调用 `RecordProvider.addDayEntry()` 注入本地；
   * 调用 `POST /api/v1/inbox/ack` 确认消费；
   * 弹出友好提示：“*已自动同步来自 QQ 机器人的 1 条午餐记录（525 kcal）*”。
2. **快照备份与冲突处理**：
   * 上传快照时比对 `serverUpdatedAt`。如果两端都发生改动，弹出已设计的“二选一”对比弹窗（保留本地 / 采用云端）。

### 5.3 设置页面扩展
* 新增【云端账号与同步】模块：
  * 服务器地址输入框（默认填自己的 `https://api.yourdomain.top`）；
  * 登录/注册入口；
  * 【绑定 QQ】弹窗：显示 6 位配对码及引导提示（*“请在 QQ 私聊机器人发送：绑定 839102”*）；
  * 【立即检查同步】手动按钮与最后同步时间。
