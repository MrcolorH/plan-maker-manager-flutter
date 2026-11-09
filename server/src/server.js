import 'dotenv/config';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { initDatabase } from './db.js';
import authRoutes from './routes/auth.js';
import bindingRoutes from './routes/binding.js';
import inboxRoutes from './routes/inbox.js';
import syncRoutes from './routes/sync.js';
import updateRoutes from './routes/update.js';

const fastify = Fastify({
  logger: {
    level: process.env.LOG_LEVEL || 'info',
  },
});

// 初始化 SQLite 数据库
initDatabase();

// 注册跨域插件
await fastify.register(cors, {
  origin: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
});

// 内部接口安全校验中间件 (严防 /internal/* 内部接口通过公网/Cloudflare 隧道被直接访问)
fastify.addHook('onRequest', async (request, reply) => {
  if (request.url.startsWith('/internal/')) {
    // 1. 凡是经由 Cloudflare 代理进来的请求，均携带 CF 专有头，或 Host 为公网域名，坚决拦截
    const isCloudflare = Boolean(request.headers['cf-connecting-ip'] || request.headers['cf-ray'] || request.headers['cf-visitor']);
    const host = (request.headers['host'] || '').toLowerCase();
    const isExternalHost = host.includes('zhiqing.fun') || (!host.includes('127.0.0.1') && !host.includes('localhost'));

    if (isCloudflare || isExternalHost) {
      return reply.status(403).send({
        error: { code: 'FORBIDDEN', message: '内部敏感接口严禁通过公网访问' },
      });
    }

    // 2. 仅允许本地回环地址发起调用 (127.0.0.1 或 ::1)
    const ip = request.ip;
    const isLocal = ip === '127.0.0.1' || ip === '::1' || ip === 'localhost';
    if (!isLocal) {
      return reply.status(403).send({
        error: { code: 'FORBIDDEN', message: '内部接口仅限本机回环访问' },
      });
    }
  }
});

// 健康检查
fastify.get('/health', async () => {
  return { status: 'ok', service: 'zhiqing-sync-server', timestamp: Math.floor(Date.now() / 1000) };
});

// 注册路由
await fastify.register(authRoutes);
await fastify.register(bindingRoutes);
await fastify.register(inboxRoutes);
await fastify.register(syncRoutes);
await fastify.register(updateRoutes);

const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';

try {
  await fastify.listen({ port: PORT, host: HOST });
  console.log(`\n=================================================`);
  console.log(`🚀 知轻同步微服务已启动: http://${HOST}:${PORT}`);
  console.log(`📡 健康检查: http://${HOST}:${PORT}/health`);
  console.log(`🔒 内部推送: http://127.0.0.1:${PORT}/internal/inbox/push`);
  console.log(`=================================================\n`);
} catch (err) {
  fastify.log.error(err);
  process.exit(1);
}
