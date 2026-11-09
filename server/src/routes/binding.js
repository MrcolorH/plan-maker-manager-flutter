import { db } from '../db.js';
import { authenticate } from '../auth.js';

export default async function bindingRoutes(fastify, options) {
  // 生成 6 位 QQ 绑定配对码 (由手机 App 发起)
  fastify.post('/api/v1/account/qq-bind-code', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;
    // 生成 6 位随机验证码
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = now + 300; // 5 分钟有效

    // 清理该用户旧的绑定码
    db.prepare('DELETE FROM qq_bind_tokens WHERE user_id = ?').run(userId);
    db.prepare('INSERT INTO qq_bind_tokens (token, user_id, expires_at) VALUES (?, ?, ?)').run(
      code,
      userId,
      expiresAt
    );

    return {
      code,
      expiresIn: 300,
      tip: `请在 QQ 私聊你的机器人回复：绑定 ${code}`
    };
  });

  // QQ 机器人确认绑定接口 (仅内网回环调用)
  fastify.post('/internal/account/qq-bind-confirm', async (request, reply) => {
    const { qqId, code } = request.body || {};

    if (!qqId || !code) {
      return reply.status(400).send({ error: { code: 'BAD_REQUEST', message: 'QQ号和配对码均不能为空' } });
    }

    const now = Math.floor(Date.now() / 1000);
    const record = db.prepare('SELECT * FROM qq_bind_tokens WHERE token = ? AND expires_at > ?').get(code, now);

    if (!record) {
      return reply.status(400).send({ error: { code: 'INVALID_CODE', message: '配对码无效或已过期，请在知轻App重新生成' } });
    }

    const targetUserId = record.user_id;

    db.transaction(() => {
      // 插入或更新绑定关系
      db.prepare(`
        INSERT INTO user_qq_bindings (qq_id, user_id, bound_at) 
        VALUES (?, ?, ?)
        ON CONFLICT(qq_id) DO UPDATE SET user_id = excluded.user_id, bound_at = excluded.bound_at
      `).run(qqId.toString(), targetUserId, now);

      // 删除已消费的 token
      db.prepare('DELETE FROM qq_bind_tokens WHERE token = ?').run(code);
    })();

    const user = db.prepare('SELECT username FROM users WHERE id = ?').get(targetUserId);

    return {
      success: true,
      userId: targetUserId,
      username: user ? user.username : '',
      message: `恭喜！您的 QQ (${qqId}) 已成功绑定知轻账号【${user ? user.username : ''}】！`
    };
  });
}
