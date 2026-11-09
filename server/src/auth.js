import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';

const JWT_SECRET = process.env.JWT_SECRET || 'zhiqing-super-secret-key-change-in-production-2026';

export async function hashPassword(plainPassword) {
  return await bcrypt.hash(plainPassword, 10);
}

export async function comparePassword(plainPassword, hash) {
  return await bcrypt.compare(plainPassword, hash);
}

export function generateToken(user) {
  return jwt.sign(
    {
      userId: user.id,
      username: user.username,
    },
    JWT_SECRET,
    { expiresIn: '30d' }
  );
}

export function verifyToken(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch (err) {
    return null;
  }
}

/**
 * Fastify 认证中间件钩子 (强制检查 JWT)
 */
export async function authenticate(request, reply) {
  const authHeader = request.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: '缺少登录令牌' } });
  }

  const token = authHeader.substring(7).trim();
  const decoded = verifyToken(token);

  if (!decoded || !decoded.userId) {
    return reply.status(401).send({ error: { code: 'INVALID_TOKEN', message: '登录令牌无效或已过期' } });
  }

  request.user = {
    id: decoded.userId,
    username: decoded.username,
  };
}
