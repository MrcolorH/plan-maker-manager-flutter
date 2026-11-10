import { db, cleanseSnapshotPayloadString } from '../db.js';
import { authenticate, comparePassword } from '../auth.js';

export default async function syncRoutes(fastify, options) {
  // 1. 上传全量快照备份 (覆盖前自动归档旧快照至历史库，防误删)
  fastify.put('/api/v1/sync/snapshot', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;
    const { payload, clientUpdatedAt, deviceName, reason } = request.body || {};

    if (!payload) {
      return reply.status(400).send({ error: { code: 'BAD_REQUEST', message: 'payload 不能为空' } });
    }

    // 服务端强制安全脱敏清洗：杜绝任何 API Key 敏感信息落库
    const rawPayloadStr = typeof payload === 'string' ? payload : JSON.stringify(payload);
    const payloadStr = cleanseSnapshotPayloadString(rawPayloadStr);
    // 限制单次快照大小不超过 3MB
    if (Buffer.byteLength(payloadStr, 'utf8') > 3 * 1024 * 1024) {
      return reply.status(413).send({ error: { code: 'PAYLOAD_TOO_LARGE', message: '数据包大小超过 3MB 上限' } });
    }

    const now = Math.floor(Date.now() / 1000);

    db.transaction(() => {
      // 检查是否有现有快照，如果有，归档至历史回滚库
      const current = db.prepare('SELECT * FROM sync_snapshots WHERE user_id = ?').get(userId);
      if (current) {
        db.prepare(`
          INSERT INTO sync_snapshot_history (user_id, payload, device_name, server_updated_at, snapshot_reason)
          VALUES (?, ?, ?, ?, ?)
        `).run(userId, current.payload, current.device_name, current.server_updated_at, reason || 'auto_archive');

        // 每个用户最多保留最近 10 次历史记录，自动清理过早的历史
        db.prepare(`
          DELETE FROM sync_snapshot_history 
          WHERE user_id = ? AND id NOT IN (
            SELECT id FROM sync_snapshot_history WHERE user_id = ? ORDER BY id DESC LIMIT 10
          )
        `).run(userId, userId);
      }

      // 覆盖写入当前最新快照
      db.prepare(`
        INSERT INTO sync_snapshots (user_id, payload, device_name, client_updated_at, server_updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
          payload = excluded.payload,
          device_name = excluded.device_name,
          client_updated_at = excluded.client_updated_at,
          server_updated_at = excluded.server_updated_at
      `).run(userId, payloadStr, deviceName || 'Unknown Device', clientUpdatedAt || now, now);
    })();

    return {
      serverUpdatedAt: now,
      message: '快照已成功同步备份至云端 (旧版本已自动归档入历史回滚池)'
    };
  });

  // 2. 拉取云端全量快照
  fastify.get('/api/v1/sync/snapshot', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;

    const snapshot = db.prepare('SELECT * FROM sync_snapshots WHERE user_id = ?').get(userId);
    if (!snapshot) {
      return reply.status(404).send({ error: { code: 'NOT_FOUND', message: '云端暂无备份快照' } });
    }

    let parsedPayload;
    try {
      parsedPayload = JSON.parse(snapshot.payload);
    } catch {
      parsedPayload = snapshot.payload;
    }

    return {
      payload: parsedPayload,
      deviceName: snapshot.device_name,
      clientUpdatedAt: snapshot.client_updated_at,
      serverUpdatedAt: snapshot.server_updated_at
    };
  });

  // 3. 查询云端历史版本列表 (用于误删时查看可回滚的快照)
  fastify.get('/api/v1/sync/history', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;

    const rows = db.prepare(`
      SELECT id, device_name, server_updated_at, snapshot_reason, length(payload) as bytes
      FROM sync_snapshot_history
      WHERE user_id = ?
      ORDER BY id DESC
      LIMIT 10
    `).all(userId);

    return { history: rows };
  });

  // 4. 从历史版本一键回滚 (防误删终极解法)
  fastify.post('/api/v1/sync/rollback', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;
    const { historyId } = request.body || {};

    if (!historyId) {
      return reply.status(400).send({ error: { code: 'BAD_REQUEST', message: '请指定历史版本 ID' } });
    }

    const historyRecord = db.prepare('SELECT * FROM sync_snapshot_history WHERE id = ? AND user_id = ?').get(historyId, userId);
    if (!historyRecord) {
      return reply.status(404).send({ error: { code: 'NOT_FOUND', message: '指定的历史版本不存在' } });
    }

    const now = Math.floor(Date.now() / 1000);

    db.transaction(() => {
      // 当前快照先备份
      const current = db.prepare('SELECT * FROM sync_snapshots WHERE user_id = ?').get(userId);
      if (current) {
        db.prepare(`
          INSERT INTO sync_snapshot_history (user_id, payload, device_name, server_updated_at, snapshot_reason)
          VALUES (?, ?, ?, ?, 'before_rollback')
        `).run(userId, current.payload, current.device_name, current.server_updated_at);
      }

      // 将历史快照还原为活跃快照
      db.prepare(`
        INSERT INTO sync_snapshots (user_id, payload, device_name, client_updated_at, server_updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
          payload = excluded.payload,
          device_name = excluded.device_name,
          client_updated_at = excluded.client_updated_at,
          server_updated_at = excluded.server_updated_at
      `).run(userId, historyRecord.payload, historyRecord.device_name, now, now);
    })();

    let restoredPayload;
    try {
      restoredPayload = JSON.parse(historyRecord.payload);
    } catch {
      restoredPayload = historyRecord.payload;
    }

    return {
      success: true,
      serverUpdatedAt: now,
      payload: restoredPayload,
      message: '已成功将云端数据回滚至该历史版本！'
    };
  });

  // 5. 抹除云端全部数据 (高危破坏性操作：强制二次密码鉴权)
  fastify.delete('/api/v1/sync/snapshot', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;
    const { password } = request.body || {};

    if (!password) {
      return reply.status(400).send({ error: { code: 'PASSWORD_REQUIRED', message: '清空云端数据属于高危操作，必须验证登录密码' } });
    }

    // 校验密码
    const user = db.prepare('SELECT password_hash FROM users WHERE id = ?').get(userId);
    const isMatch = await comparePassword(password, user.password_hash);
    if (!isMatch) {
      return reply.status(401).send({ error: { code: 'AUTH_FAILED', message: '密码错误，操作已被拒绝' } });
    }

    db.transaction(() => {
      // 抹除前仍自动归档一份，标记为 before_destroy (给后悔药留底，同时严格脱敏)
      const current = db.prepare('SELECT * FROM sync_snapshots WHERE user_id = ?').get(userId);
      if (current) {
        db.prepare(`
          INSERT INTO sync_snapshot_history (user_id, payload, device_name, server_updated_at, snapshot_reason)
          VALUES (?, ?, ?, ?, 'before_destroy')
        `).run(userId, cleanseSnapshotPayloadString(current.payload), current.device_name, current.server_updated_at);
      }

      // 清空当前快照与收件箱
      db.prepare('DELETE FROM sync_snapshots WHERE user_id = ?').run(userId);
      db.prepare('DELETE FROM pending_entries WHERE user_id = ?').run(userId);
      if (request.body?.clearHistory === true) {
        db.prepare('DELETE FROM sync_snapshot_history WHERE user_id = ?').run(userId);
      }
    })();

    return {
      success: true,
      message: '云端活跃数据已清空（服务端已保留防误删归档快照）'
    };
  });
}
