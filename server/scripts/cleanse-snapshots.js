import Database from 'better-sqlite3';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import { cleanseSnapshotPayloadString } from '../src/db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dbPath = path.resolve(__dirname, '../data/zhiqing.db');

if (!fs.existsSync(dbPath)) {
  console.error(`[Error] 数据库文件不存在: ${dbPath}`);
  process.exit(1);
}

const db = new Database(dbPath);
const isDryRun = process.argv.includes('--dry-run');

console.log(`=============================================`);
console.log(`[安全运维] 云端快照 API 密钥脱敏清洗工具`);
console.log(`数据库路径: ${dbPath}`);
console.log(`模式: ${isDryRun ? '🔍 仅检查预览 (Dry-Run)' : '⚡ 执行清洗落库 (Write Mode)'}`);
console.log(`=============================================`);

let totalSnapshotsCleaned = 0;
let totalHistoryCleaned = 0;

// 1. 扫描与清洗 sync_snapshots 表
const snapshots = db.prepare('SELECT user_id, device_name, payload FROM sync_snapshots').all();
const updateSnapshot = db.prepare('UPDATE sync_snapshots SET payload = ? WHERE user_id = ?');

for (const row of snapshots) {
  const cleaned = cleanseSnapshotPayloadString(row.payload);
  if (cleaned !== row.payload) {
    totalSnapshotsCleaned++;
    console.log(`[Snapshot] 发现未脱敏数据 -> 用户 ID: ${row.user_id}, 设备: ${row.device_name}`);
    if (!isDryRun) {
      updateSnapshot.run(cleaned, row.user_id);
    }
  }
}

// 2. 扫描与清洗 sync_snapshot_history 表
const histories = db.prepare('SELECT id, user_id, device_name, payload FROM sync_snapshot_history').all();
const updateHistory = db.prepare('UPDATE sync_snapshot_history SET payload = ? WHERE id = ?');

for (const row of histories) {
  const cleaned = cleanseSnapshotPayloadString(row.payload);
  if (cleaned !== row.payload) {
    totalHistoryCleaned++;
    console.log(`[History] 发现未脱敏历史版本 -> 记录 ID: ${row.id}, 用户 ID: ${row.user_id}, 设备: ${row.device_name}`);
    if (!isDryRun) {
      updateHistory.run(cleaned, row.id);
    }
  }
}

console.log(`---------------------------------------------`);
console.log(`扫描完成:`);
console.log(`• 活跃快照 (sync_snapshots): 共 ${snapshots.length} 条，${totalSnapshotsCleaned} 条已脱敏处理`);
console.log(`• 历史版本 (sync_snapshot_history): 共 ${histories.length} 条，${totalHistoryCleaned} 条已脱敏处理`);

if (totalSnapshotsCleaned === 0 && totalHistoryCleaned === 0) {
  console.log(`🎉 状态安全：当前数据库中所有快照均已完全脱敏，未发现任何明文 API Key！`);
} else if (isDryRun) {
  console.log(`⚠️ 以上发现的敏感数据尚未写入变更。若要正式清洗，请去掉 --dry-run 参数重新执行。`);
} else {
  console.log(`✅ 成功清洗完成！所有敏感 API Key 已永久抹除置空。`);
}
console.log(`=============================================\n`);
