import { db } from '../db.js';
import { hashPassword, comparePassword, generateToken, authenticate } from '../auth.js';

export default async function authRoutes(fastify, options) {
  // 注册接口 (需有效邀请码)
  fastify.post('/api/v1/auth/register', async (request, reply) => {
    const { username, password, inviteCode } = request.body || {};

    if (!username || !password || !inviteCode) {
      return reply.status(400).send({ error: { code: 'BAD_REQUEST', message: '账号、密码和邀请码均不能为空' } });
    }

    if (username.length < 3 || username.length > 20) {
      return reply.status(400).send({ error: { code: 'INVALID_USERNAME', message: '用户名长度需在 3~20 个字符' } });
    }

    if (password.length < 6) {
      return reply.status(400).send({ error: { code: 'WEAK_PASSWORD', message: '密码长度至少需 6 位' } });
    }

    // 校验邀请码
    const invite = db.prepare('SELECT * FROM invite_codes WHERE code = ? AND is_used = 0').get(inviteCode);
    if (!invite) {
      return reply.status(400).send({ error: { code: 'INVALID_INVITE_CODE', message: '邀请码无效或已被使用' } });
    }

    // 检查用户名冲突
    const existing = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
    if (existing) {
      return reply.status(409).send({ error: { code: 'USER_EXISTS', message: '该用户名已存在' } });
    }

    const passwordHash = await hashPassword(password);
    const now = Math.floor(Date.now() / 1000);

    const transaction = db.transaction(() => {
      const userRes = db.prepare(
        'INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)'
      ).run(username, passwordHash, now);

      const userId = userRes.lastInsertRowid;
      db.prepare('UPDATE invite_codes SET is_used = 1, used_by = ? WHERE code = ?').run(userId, inviteCode);
      return userId;
    });

    const userId = transaction();
    const token = generateToken({ id: userId, username });

    return {
      token,
      user: { id: userId, username }
    };
  });

  // 登录接口
  fastify.post('/api/v1/auth/login', async (request, reply) => {
    const { username, password } = request.body || {};

    if (!username || !password) {
      return reply.status(400).send({ error: { code: 'BAD_REQUEST', message: '用户名和密码不能为空' } });
    }

    const user = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
    if (!user) {
      return reply.status(401).send({ error: { code: 'AUTH_FAILED', message: '用户名或密码错误' } });
    }

    const isMatch = await comparePassword(password, user.password_hash);
    if (!isMatch) {
      return reply.status(401).send({ error: { code: 'AUTH_FAILED', message: '用户名或密码错误' } });
    }

    const token = generateToken(user);
    return {
      token,
      user: { id: user.id, username: user.username }
    };
  });

  // 当前用户信息接口
  fastify.get('/api/v1/auth/me', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;
    const user = db.prepare('SELECT id, username, created_at FROM users WHERE id = ?').get(userId);
    const qqBinding = db.prepare('SELECT qq_id, bound_at FROM user_qq_bindings WHERE user_id = ?').get(userId);

    return {
      user: {
        ...user,
        boundQq: qqBinding ? qqBinding.qq_id : null,
        boundAt: qqBinding ? qqBinding.bound_at : null
      }
    };
  });

  // 内部接口：创建邀请码 (仅限内网回环调用)
  fastify.post('/internal/invite/create', async (request, reply) => {
    let { code } = request.body || {};
    const now = Math.floor(Date.now() / 1000);

    if (code && typeof code === 'string') {
      code = code.trim().toUpperCase();
      if (code.length < 3 || code.length > 32) {
        return reply.status(400).send({ error: { code: 'INVALID_FORMAT', message: '邀请码长度需在 3~32 个字符之间' } });
      }
    } else {
      const randomSuffix = Math.floor(1000 + Math.random() * 9000);
      code = `ZQ${randomSuffix}`;
    }

    try {
      db.prepare('INSERT INTO invite_codes (code, is_used, created_at) VALUES (?, 0, ?)').run(code, now);
      return {
        success: true,
        code,
        createdAt: now
      };
    } catch (err) {
      if (err.message.includes('UNIQUE constraint failed')) {
        return reply.status(409).send({ error: { code: 'CODE_EXISTS', message: `邀请码 [${code}] 已存在` } });
      }
      return reply.status(500).send({ error: { code: 'SERVER_ERROR', message: err.message } });
    }
  });

  // 内部接口：获取未使用的有效邀请码列表 (仅限内网回环调用)
  fastify.get('/internal/invite/list', async (request, reply) => {
    const available = db.prepare("SELECT code, datetime(created_at, 'unixepoch', 'localtime') as created_time FROM invite_codes WHERE is_used = 0 ORDER BY created_at DESC").all();
    return {
      success: true,
      count: available.length,
      invites: available
    };
  });
}
