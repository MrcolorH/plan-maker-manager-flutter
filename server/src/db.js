import Database from 'better-sqlite3';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.resolve(__dirname, '../data');

if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, 'zhiqing.db');
export const db = new Database(dbPath);

// 启用 WAL 模式提高并发读写性能
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

export function initDatabase() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      username      TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at    INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS invite_codes (
      code          TEXT PRIMARY KEY,
      is_used       INTEGER DEFAULT 0,
      used_by       INTEGER REFERENCES users(id),
      created_at    INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS user_qq_bindings (
      qq_id         TEXT PRIMARY KEY,
      user_id       INTEGER NOT NULL UNIQUE REFERENCES users(id),
      bound_at      INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS qq_bind_tokens (
      token         TEXT PRIMARY KEY,
      user_id       INTEGER NOT NULL REFERENCES users(id),
      expires_at    INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS pending_entries (
      id            TEXT PRIMARY KEY,
      user_id       INTEGER NOT NULL REFERENCES users(id),
      date          TEXT NOT NULL,
      slot          TEXT NOT NULL,
      content       TEXT NOT NULL,
      calories      INTEGER NOT NULL,
      protein       INTEGER,
      carbs         INTEGER,
      fat           INTEGER,
      detail        TEXT,
      items_json    TEXT,
      source        TEXT DEFAULT 'qq_bot',
      created_at    INTEGER NOT NULL,
      is_consumed   INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS sync_snapshots (
      user_id           INTEGER PRIMARY KEY REFERENCES users(id),
      payload           TEXT NOT NULL,
      device_name       TEXT,
      client_updated_at INTEGER,
      server_updated_at INTEGER NOT NULL
    );

    -- 云端历史快照回滚版本库 (最多保留每个用户最近 10 次快照，提供防误删安全网)
    CREATE TABLE IF NOT EXISTS sync_snapshot_history (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id           INTEGER NOT NULL REFERENCES users(id),
      payload           TEXT NOT NULL,
      device_name       TEXT,
      server_updated_at INTEGER NOT NULL,
      snapshot_reason   TEXT DEFAULT 'auto_backup'
    );
  `);

  // 如果没有邀请码，自动生成一个初始管理员邀请码方便首次注册
  const count = db.prepare('SELECT count(*) as count FROM invite_codes WHERE is_used = 0').get().count;
  if (count === 0) {
    const defaultInvite = 'ZQ8888';
    db.prepare('INSERT OR IGNORE INTO invite_codes (code, created_at) VALUES (?, ?)').run(
      defaultInvite,
      Math.floor(Date.now() / 1000)
    );
    console.log(`[Database] 初始可用邀请码已创建: ${defaultInvite}`);
  }

  // 历史快照安全清洗：确保数据库中存留的任何历史版本快照中的 API Key 均脱敏为空
  cleanseHistoricalSnapshotApiKeys();
}

/// 快照 payload 安全脱敏清洗（递归剔除所有 API Key、Secret 等凭据敏感信息）
export function cleanseSnapshotPayloadString(payloadStr) {
  try {
    const obj = JSON.parse(payloadStr);
    let dirty = false;

    // 递归深度脱敏
    function sanitize(node) {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node)) {
        for (const item of node) sanitize(item);
        return;
      }
      for (const [key, val] of Object.entries(node)) {
        const lowerKey = key.toLowerCase();
        // 匹配 apiKey, api_key, accesskey, token, secret 等凭据字段
        if (
          (lowerKey === 'apikey' ||
            lowerKey === 'api_key' ||
            lowerKey === 'key' ||
            lowerKey.endsWith('key') ||
            lowerKey.endsWith('secret') ||
            lowerKey.endsWith('token')) &&
          typeof val === 'string' &&
          val.trim().length > 0
        ) {
          // 例外：如果是常规非敏感字段（如 id, planKey 等不是密钥的排除）
          if (lowerKey !== 'id' && lowerKey !== 'plankey' && lowerKey !== 'category' && lowerKey !== 'type') {
            node[key] = '';
            dirty = true;
          }
        } else if (typeof val === 'object') {
          sanitize(val);
        }
      }
    }

    if (obj?.data?.settings) {
      sanitize(obj.data.settings);
    }
    return dirty ? JSON.stringify(obj) : payloadStr;
  } catch {
    return payloadStr;
  }
}

/// 批量清洗现有数据库中历史留存的快照数据
function cleanseHistoricalSnapshotApiKeys() {
  try {
    const snapshots = db.prepare('SELECT user_id, payload FROM sync_snapshots').all();
    const updateSnapshot = db.prepare('UPDATE sync_snapshots SET payload = ? WHERE user_id = ?');
    for (const row of snapshots) {
      const cleaned = cleanseSnapshotPayloadString(row.payload);
      if (cleaned !== row.payload) {
        updateSnapshot.run(cleaned, row.user_id);
      }
    }

    const histories = db.prepare('SELECT id, payload FROM sync_snapshot_history').all();
    const updateHistory = db.prepare('UPDATE sync_snapshot_history SET payload = ? WHERE id = ?');
    for (const row of histories) {
      const cleaned = cleanseSnapshotPayloadString(row.payload);
      if (cleaned !== row.payload) {
        updateHistory.run(cleaned, row.id);
      }
    }
  } catch (err) {
    console.error('[Database] 快照脱敏清洗异常:', err);
  }
}
