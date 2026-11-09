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
}
