# 知轻 · 云端账号与数据同步方案（学习与准备版）

> v0.1 草案 ｜ 状态：**待评审拍板** ｜ 前置阅读：[backup-design.md](backup-design.md)
> 本文回答两个问题：① 这套「服务器 + 账号 + 云同步」怎么做；② 主人需要**学习什么、准备什么**。

## 0. 一句话结论（TL;DR）

自建一台**免备案轻量云服务器**（香港/海外节点）跑一个**极简后端**（Fastify 或 FastAPI + SQLite + JWT），App 端**复用现有 BackupData 8 项快照格式**做「整包快照同步」，铁律不变——**单机离线优先，云同步失败绝不阻塞打卡主流程**。

需要学习的内容归为 6 块（详见第 7 节）：HTTP/REST 视角转换 → 后端框架 → SQL/SQLite → 认证与安全 → Linux/部署运维 → Flutter 网络配套。需要准备的东西很少（详见第 8 节）：一台服务器 + 一个域名 + 两三个调试工具。

---

## 1. 为什么做 & 边界

**痛点**：当前全部数据（8 个存储键）只存在于设备本机的 `shared_preferences`；本地自动备份（F9）也只是本机 Download 目录的单文件滚动覆盖。卸载重装、换机、丢手机 = 数据全丢。

**目标（第一版做到）**：
1. 账号体系：注册 / 登录 / 退出
2. 打卡数据上云：计划 + 打卡记录 + 热量调整 + 临时任务等 8 项快照存到云端
3. 新设备恢复：换机/重装后登录即可拉回全部数据

**非目标（第一版不做）**：
- ❌ 社交 / 搭子匹配 / 分享动态
- ❌ Web 管理后台、数据可视化大屏
- ❌ 多设备实时同步（冲突自动合并）
- ❌ 手机号短信验证码登录、微信登录

**铁律（延续 README 产品定义）**：
- App 保持**离线优先**——云端只是「异地备份 + 多设备」增强，所有读写仍走本地，同步在后台静默进行
- 同步失败 / 无网络 / 服务器挂了 → 只影响云端副本，**打卡主流程零感知**

---

## 2. 现状盘点（可复用资产）

| 现有资产 | 现状 | 对云同步的意义 |
|---|---|---|
| 8 个存储键 | `shared_preferences` 存 JSON 字符串（storage_service.dart），1:1 兼容旧版 uni storage | 云端只存「快照 JSON」，不需要为同步改本地存储结构 |
| BackupData 8 项快照 | `backup_service.dart` 的 `encodeBackup()` 已稳定（app/type/formatVersion=1/exportedAt/data） | **云端 payload 直接复用备份格式**，序列化/反序列化/容错归一逻辑已写好并测过，省一大截设计 |
| dio | AI 请求已在用（ai_service.dart） | 网络层零新增依赖，拦截器带 token、超时重试都有现成经验 |
| 备份页 UI | backup_page.dart 的「导出/导入/确认弹窗」交互骨架 | 账号与同步页可参考其确认弹窗、危险操作强确认的交互模式 |
| 增量合并逻辑 | 备份导入已有「增量合并 / 覆盖替换」两套语义 | S2 增量同步与「恢复冲突弹窗」可直接借鉴 |

**⚠️ 敏感点**：`settings.ai.apiKey` 是用户明文 DeepSeek Key。备份文件允许含它（本机文件），但**云端 payload 必须剔除**——App 端上传前置空 + 服务端过滤兜底，防止服务器被拖库后泄露用户 Key。

---

## 3. 技术选型

### 3.1 三条路线对比

| 维度 | A. 轻量云服务器自建 ⭐推荐 | B. BaaS（LeanCloud 国内 / Supabase） | C. Serverless 云开发（腾讯 CloudBase 等） |
|---|---|---|---|
| 学习价值 | **高**（HTTP/SQL/认证/运维全套通识，一次学完可复用到任何项目） | 低（学的是平台概念，技能被平台绑定） | 低 |
| 成本 | 服务器 + 域名 ≈ ¥150~450/年 | 免费额度内够用 | 免费额度内够用 |
| 运维负担 | 自己管（但个人 MVP 极简，几乎不用管） | 无 | 无 |
| 数据掌控 | 完全在自己手里（SQLite 文件即数据库，随便备份迁移） | 托管、导出受限 | 托管、lock-in 强 |
| Flutter 接入 | 自己用 dio 写（无新依赖，契约自己定） | 依赖官方/社区 SDK | 对 Flutter 支持弱 |
| 适合 | **想借项目学后端的主人** | 只想要结果、不想碰服务器 | 已深度用某云生态 |

**推荐理由**：主人明确说「想搞个服务器」——学习本身就是目标之一。自建路线学到的东西（接口、SQL、JWT、Nginx、Linux）是通用能力，且数据 100% 自己掌控，BaaS 随时可以作为「懒得运维了」的降级备选。

### 3.2 路线 A 内部选型

**后端语言/框架**（二选一，接口契约与语言无关，换语言零影响）：

| | Node.js + Fastify ⭐推荐 | Python + FastAPI |
|---|---|---|
| 复用已有技能 | 主人 Vue3/JS 底子厚，JWT、中间件、async 概念在 JS 生态学起来最顺，顺手打通全栈 | 主人有 Python 后端经验（auto-marker），上手更快 |
| SQLite 驱动 | better-sqlite3（同步 API，极简） | 内置 sqlite3 或 SQLAlchemy |
| 类型与校验 | JSON Schema / zod | Pydantic（很舒服） |
| 学习增量 | 复用 JS，增量最小 | 第二门后端语言，学习面更宽 |

> 倾向 Fastify：用最熟悉的语言把**新概念**（SQL、认证、部署）集中消化，避免「新语言 + 新领域」双重负重。FastAPI 完全等价可替换。

**数据库：SQLite**（不选 MySQL/PostgreSQL）
- 个人规模（几个用户、每天几十 KB 快照）SQLite 性能余量是千倍级的
- 零运维：没有独立数据库进程，整个数据库就是一个文件 → `cp` 一下就是完整备份
- 学习路径对：先把 SQL 本身学扎实，以后上 MySQL/PG 只是换驱动

**认证：用户名 + 密码 + JWT**
- 手机验证码：短信按条计费 + 签名/模板审核，个人项目不划算 → 不做
- 微信登录：需开放平台认证（¥300/年）+ App 备案，流程过重 → 不做
- 邮箱验证：需要邮件服务，可作 v1.1 增强 → 第一版不做
- 密码绝不存明文：服务端 **argon2 或 bcrypt 哈希**（带盐、慢哈希）

### 3.3 服务器位置（关键决策）

| | 香港/海外轻量 ⭐推荐 MVP | 国内轻量 |
|---|---|---|
| 备案 | **免备案**，开通即用，域名解析后当天可上 HTTPS | 域名必须 ICP 备案（免费但流程 1~2 周，需身份证/人脸/服务器购买≥3个月） |
| 延迟 | 30~60ms | 5~20ms |
| 对本 App 影响 | 无感——打卡同步是低频小流量（单次快照几百 KB） | 更快但 MVP 阶段感知不到 |
| 迁移成本 | 以后想迁国内：备份数据库文件 + 重部署，半天搞定 | — |

> 推荐：先香港免备案快速跑通闭环；产品真要面向公众分发时再考虑迁国内 + 备案。

---

## 4. 目标架构

```
┌─────────────────────────┐         HTTPS (443)          ┌──────────────────────────┐
│  知轻 App (Flutter)      │  ──────────────────────────► │  轻量云服务器 (Linux)      │
│                          │   dio + JWT Bearer Token     │                           │
│  本地存储 (8键, 唯一写入点) │   ① POST /auth/register      │  Nginx                    │
│  SyncService 后台静默同步  │   ② POST /auth/login         │   ├─ TLS 证书 (Let's Encrypt)
│   ├─ 打卡后 debounce 上传  │   ③ PUT  /sync/snapshot      │   └─ 反向代理 ──► Fastify  │
│   ├─ 登录后拉取比对        │   ④ GET  /sync/snapshot      │                      :3000│
│   └─ 冲突时弹窗二选一       │                              │                           │
│  Token 存 flutter_secure_ │                              │  SQLite  (app.db)         │
│  storage（不进 prefs 明文） │                              │   ├─ users                │
└─────────────────────────┘                              │   └─ sync_snapshots       │
                                                          │  cron: 每日 4 点 备份 db   │
                                                          │   └─ app.db.bak.YYYYMMDD  │
                                                          └──────────────────────────┘
```

**一次打卡数据上云的生命周期**：
1. 用户打卡 → RecordProvider 更新本地（唯一事实源，不变）
2. SyncService 监听数据变更，debounce 30s + 有网络 + 已登录 → 组装快照（复用 BackupData，剔除 apiKey，附加 deviceName/appVersion/clientUpdatedAt）
3. `PUT /sync/snapshot`（带 JWT）→ 服务端校验 payload → 整包覆盖写 sync_snapshots，记录 serverUpdatedAt
4. 响应回 serverUpdatedAt，本地记下「已同步水位」；失败静默重试（退避），主流程无感

---

## 5. 接口与数据设计（语言无关契约）

### 5.1 数据库（2 张表足够）

```sql
CREATE TABLE users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT    NOT NULL UNIQUE,          -- 4~24 位，字母数字下划线
  password_hash TEXT    NOT NULL,                 -- argon2id/bcrypt，绝不存明文
  created_at    INTEGER NOT NULL,                 -- Unix 秒
  last_login_at INTEGER
);

CREATE TABLE sync_snapshots (
  user_id           INTEGER PRIMARY KEY REFERENCES users(id),  -- 一人一份快照（S1）
  payload           TEXT    NOT NULL,             -- 8 项快照 JSON（已剔除 apiKey）
  payload_bytes     INTEGER NOT NULL,             -- 大小监控用
  device_name       TEXT,
  app_version       TEXT,
  client_updated_at INTEGER,
  server_updated_at INTEGER NOT NULL              -- 冲突比对依据
);
```

### 5.2 接口契约（MVP 共 6 个）

| # | 方法/路径 | 入参 | 出参 | 错误 |
|---|---|---|---|---|
| 1 | POST /api/v1/auth/register | {username, password} | {token, username} | 400 格式非法 ｜ 409 用户名已存在 |
| 2 | POST /api/v1/auth/login | {username, password} | {token, username, serverUpdatedAt?} | 401 账号或密码错误 |
| 3 | GET /api/v1/me | —（JWT） | {username, createdAt, serverUpdatedAt?} | 401 |
| 4 | PUT /api/v1/sync/snapshot | {payload, clientUpdatedAt, deviceName, appVersion}（JWT） | {serverUpdatedAt} | 400 payload 非法/超限 ｜ 413 超大小 |
| 5 | GET /api/v1/sync/snapshot | —（JWT） | {payload, serverUpdatedAt, deviceName} ｜ 404 无云端数据 | 401 |
| 6 | DELETE /api/v1/account | {password}（JWT，二次确认） | 204，级联删快照 | 401 |

通用约定：JWT 放 `Authorization: Bearer <token>`，有效期 30 天；统一错误体 `{error: {code, message}}`；登录/注册接口按 IP 限速（如 5 次/分钟）防爆破。

### 5.3 快照 payload 规范

- 结构 = 现有 `encodeBackup()` 的 `data` 段（planData / checkRecords / mealAdjust / tempTasks / extraFoods / settings / onboardingState / apiUsage 8 项）
- **差异 1**：`settings.ai.apiKey` 置空（App 端置空 + 服务端收到后强制置空双保险）
- **差异 2**：外层包 `cloudSync` 元信息：`{formatVersion: 1, clientUpdatedAt, deviceName, appVersion}`
- 大小上限：**2MB**（按每天 50 条打卡 × 10 年估算也远够），超限 413

### 5.4 安全设计清单（做后端的第一课）

- [x] 密码 argon2id/bcrypt 哈希（慢哈希是特性不是缺陷）
- [x] 全站 HTTPS（Let's Encrypt + certbot 自动续期），HTTP 301 跳 HTTPS
- [x] JWT secret 走环境变量，不进代码库；token 30 天过期
- [x] 登录/注册限速防爆破；payload 大小限制
- [x] 服务器：ufw 只开 22/80/443；SSH 密钥登录禁密码；服务用非 root 用户跑；fail2ban（可选）
- [x] 服务端参数校验（zod/Pydantic），不信任任何客户端输入

---

## 6. 同步策略（S1 MVP → S2 增量）

### 6.1 S1：整包快照同步（第一版，语义 = 「云端的自动备份」）

| 场景 | 行为 |
|---|---|
| 登录成功 | `GET snapshot`：404 → 本地数据仍在，仅标记可上传；有云端数据且本地为**空/全新** → 直接恢复云端快照（走现有覆盖导入流程）；两边都有数据 → 弹窗二选一（用云端 / 用本地上传覆盖） |
| 日常打卡 | 数据变更后 debounce 30s 自动上传整包（last-write-wins，上传前比对 serverUpdatedAt，云端更新则先弹窗） |
| 手动同步 | 设置-账号页提供「立即同步」+ 最近同步时间显示 |
| 退出登录 | 仅清 token，本地数据不动（防误删） |
| 断网/失败 | 静默，记「待同步」标记，下次联网重试；**绝不弹窗打扰打卡主流程** |

冲突模型刻意选**整包 last-write-wins + 明确弹窗**：与现有备份「覆盖导入需强确认」的语义一致，用户心智已建立；第一版不做字段级合并（投入产出比低，S2 再说）。

### 6.2 S2 增量同步（演进方向，暂不实现）

checkRecords / mealAdjust / tempTasks 天然按 `date` 分片 → 按「天」做变更水位线（`sync_cursor`），只上传变更日期的分片；planData 整体版本号比对。云端表从「一人一快照」演进为「一人多分片」。现有备份的增量合并逻辑可平移过来。

### 6.3 服务端备份（防「云也丢了」）

- cron 每日 4 点：`sqlite3 app.db ".backup app.db.bak.日期"`，保留最近 14 份
- （可选进阶）每周把备份文件推到对象存储（如 Cloudflare R2 免费额度）实现异地备份

---

## 7. 学习清单 ⭐（核心交付）

> 按依赖顺序排列，全部围绕「做出这个 MVP」目标学，不贪多。每块给出**达标自测**——能答上来 = 可以进入下一块。

| # | 主题 | 学什么 | 达标自测 | 推荐资源 |
|---|---|---|---|---|
| 1 | HTTP / REST（视角转换） | 从「用 axios/dio 调接口」转为「实现接口」：方法语义、状态码（200/400/401/404/409/413）、请求头、JSON body、错误响应设计；用 curl 直接手写请求 | 能用 curl 完成一次带 JSON body 的 POST，并说清 401 与 403 的区别 | MDN《HTTP 概述》（中文） |
| 2 | 后端框架 | Fastify（或 FastAPI）：路由、路径/请求体校验（zod/Pydantic）、中间件/钩子、统一错误处理、环境变量配置 | 写出一个带参数校验的 `/echo` 接口，非法入参自动返回 400 | Fastify 官方 Getting Started（或 FastAPI 官方中文文档） |
| 3 | SQL / SQLite | 建表、主键/外键/UNIQUE、CRUD、WHERE/ORDER BY、事务概念；better-sqlite3（或 Python sqlite3）驱动用法 | 在命令行用 SQL 手工建出第 5.1 节两张表并插入查询；SQLBolt 全部关卡通过 | SQLBolt（交互式，半天）＋ better-sqlite3 README |
| 4 | 认证与安全 | 哈希 vs 加密的区别、盐、为什么用慢哈希；JWT 三段结构（header.payload.signature）、签发/校验/过期、Bearer 用法；限速思路 | 能解释「数据库被拖走，为什么用户密码仍是安全的」；能用 curl 走通「注册→登录→带 token 请求受保护接口」 | JWT.io 官网 Debugger 亲手玩一遍 ＋ OWASP Authentication Cheat Sheet |
| 5 | Linux / 部署运维 | SSH 免密登录、文件权限、systemd 服务常驻（写一个 unit 文件）、Nginx 反向代理概念、certbot 签发 HTTPS、ufw 防火墙、cron 定时任务 | 服务器上部署一个 hello-world 服务，手机浏览器能 https:// 访问，重启服务器后服务自动拉起 | DigitalOcean Nginx 教程系列（经典）；B 站搜「Nginx 入门」配着看更快 |
| 6 | Flutter 网络配套（增量小） | dio 拦截器统一加 token 与错误分支、flutter_secure_storage 存 token（不进 prefs 明文）、生命周期感知（App 回前台触发同步） | 能在 dio 复现「无 token → 401 → 跳登录页」的拦截器流程 | dio 官方文档 Interceptor 章节（已有 AI 请求经验，很快） |

**学习节奏建议**：1→4 是一条线（约 1~2 周业余时间，边学边在**本机**把后端 MVP 写出来，先不上服务器）；5 可以与 P2 部署阶段边做边学；6 是已有技能的小增量。

---

## 8. 准备清单 ⭐（买什么、装什么、注册什么）

### 8.1 采购（总成本量级 ≈ ¥150~450/年，以官网实时价为准）

| 项 | 建议 | 参考量级 | 备注 |
|---|---|---|---|
| 云服务器 | 腾讯云/阿里云**轻量应用服务器** 2C2G，**香港或海外节点**（免备案） | 新用户活动价 ¥100~400/年 | 够用天花板：2C2G 跑 Nginx+Fastify+SQLite 只占零头；新用户价次年恢复原价，续费前留意 |
| 域名 | 一个 `.top`/`.xyz`（便宜）或 `.com`（稳） | ¥10~80/年 | 国内注册商（阿里/腾讯）实名即可；香港服务器**不需要备案** |
| HTTPS 证书 | Let's Encrypt + certbot 自动续期 | 免费 | 不要买证书 |
| 短信/对象存储 | 第一版都不需要 | ¥0 | 对象存储（异地备份）属可选进阶 |

### 8.2 工具与软件

| 工具 | 用途 | 备注 |
|---|---|---|
| 终端 + ssh（macOS 自带） | 连服务器 | 可选 Termius 更舒服 |
| Apifox（或 Postman） | 接口调试、契约管理、自动化测试 | Apifox 对中文/团队友好 |
| DB Browser for SQLite | 本地开发时直观看数据库文件 | 学 SQL 阶段就有用 |
| Node 22 / Python 3.13（本机已有） | 本地开发后端 | 先本机跑通，再上服务器 |

### 8.3 需要注册的账号

- 云厂商账号（腾讯云/阿里云，需实名认证）
- 域名注册商（通常与云厂商同一家）
- （可选）GitHub 私有仓库：后端代码托管 + 免费的 GitHub Actions 以后可玩 CI

---

## 9. 实施路线图（P0 → P4）

| 阶段 | 内容 | 验收标准 | 预估（业余时间） |
|---|---|---|---|
| **P0 学习 & 采购**（并行） | 学第 7 节主题 1~4；下单服务器 + 域名 | curl 手写请求无障碍；SQLBolt 通关；服务器到手能 SSH 登录 | 1~2 周 |
| **P1 后端 MVP（本机）** | 6 个接口 + SQLite + argon2 + JWT + 限速 + 参数校验；Apifox 全流程测试 | register→login→PUT snapshot→GET snapshot 闭环全绿；payload 超限/无 token/密码错误等分支符合契约 | 1 周 |
| **P2 上线部署** | 域名解析 → Nginx + HTTPS → systemd 常驻 → ufw/SSH 加固 → cron 每日备份 | 手机浏览器 https 访问 `/api/v1/me` 返回 401 JSON；重启服务器服务自恢复；备份文件按日生成 | 2~3 天 |
| **P3 App 接入** | 设置页新增「账号」区（注册/登录/退出/最近同步时间）；SyncService（debounce 上传/登录拉取/冲突弹窗）；token 存 secure storage；**spec 同步更新**（本文档升版 + checklist 加用例） | 真机验证：打卡 → 30s 内云端快照更新；**卸载重装 → 登录 → 数据完整拉回**；断网打卡不受任何影响 | 1 周 |
| **P4 打磨（可选）** | S2 增量同步、自动同步时机细化、服务器简单监控（uptime 监控/异常日志）、异地备份 | 按需 | 按需 |

---

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| 服务器挂/被删 → 云端数据丢失 | 每日 cron 备份（留 14 份）+ 可选异地备份；本地始终是唯一事实源，最坏情况回到现状 |
| 被拖库 → 用户密码/Key 泄露 | 密码慢哈希带盐；apiKey 根本不上云；JWT secret 环境变量 |
| 接口被滥用/恶意注册 | 登录注册限速；payload 2MB 上限；（可选）注册邀请码 |
| 合规 | 免备案节点规避 ICP；健康数据属敏感个人信息——自用/小范围侧载影响小，**若未来上架应用商店需补隐私政策**；保留 DELETE /api/v1/account 体现数据可删 |
| 成本 | 轻量服务器活动价次年恢复，续费前比价；SQLite 单文件随时可迁任何新服务器 |
| 学习曲线劝退 | 按 P0~P2 顺序，先本机后上云；卡住的标准答案路径：报错原文 → 搜报错 → 让 AI 一起看日志 |
| 范围膨胀 | 第一版死守「快照同步」，字段级合并/实时同步/社交全部进 S2/不做清单 |

---

## 11. 待主人拍板的决策点

1. **技术路线**：自建（推荐，学习价值高）还是 BaaS 省事？（本文按自建展开）
2. **后端语言**：Node/Fastify（推荐）还是 Python/FastAPI？（接口契约语言无关，随时可换）
3. **服务器位置**：香港免备案（推荐 MVP）还是国内 + 备案？
4. **登录方式**：用户名 + 密码（推荐）够不够？要不要 v1.1 加邮箱找回密码？
5. **S1 冲突语义**：整包 last-write-wins + 弹窗二选一（与现有覆盖导入心智一致）是否接受？

> 拍板后：本文档升 v1.0 定稿 → tasks.md 增补云端 Phase → checklist.md 增补同步用例 → 再动代码。

---

**文档元信息**
- 所属版本：远期规划草案
- 创建时间：2026年09月03日
