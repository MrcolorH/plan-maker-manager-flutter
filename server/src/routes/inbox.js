import { db } from '../db.js';
import { authenticate } from '../auth.js';
import crypto from 'node:crypto';

export default async function inboxRoutes(fastify, options) {
  // 1. QQ 机器人写入待录入信箱 (仅限 127.0.0.1 访问)
  fastify.post('/internal/inbox/push', async (request, reply) => {
    const { qqId, date, slot, content, calories, protein, carbs, fat, items, detail } = request.body || {};

    if (!qqId || !date || !content || calories === undefined) {
      return reply.status(400).send({
        error: { code: 'BAD_REQUEST', message: '缺少必要字段 (qqId, date, content, calories)' }
      });
    }

    // 根据 QQ 号查找绑定的知轻用户
    const binding = db.prepare('SELECT user_id FROM user_qq_bindings WHERE qq_id = ?').get(qqId.toString());
    if (!binding) {
      return reply.status(404).send({
        error: {
          code: 'UNBOUND_QQ',
          message: `QQ (${qqId}) 尚未绑定知轻账号，无法同步。请在 App 生成绑定码进行绑定。`
        }
      });
    }

    const entryId = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const itemsJson = items ? JSON.stringify(items) : null;

    db.prepare(`
      INSERT INTO pending_entries (
        id, user_id, date, slot, content, calories, protein, carbs, fat, detail, items_json, source, created_at, is_consumed
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'qq_bot', ?, 0)
    `).run(
      entryId,
      binding.user_id,
      date,
      slot || 'lunch',
      content,
      calories,
      protein || 0,
      carbs || 0,
      fat || 0,
      detail || null,
      itemsJson,
      now
    );

    return {
      success: true,
      id: entryId,
      userId: binding.user_id,
      message: '已成功存入知轻待录入信箱'
    };
  });

  // 2. 手机端拉取待录入条目 (受 JWT 保护，仅能拉取自己的)
  fastify.get('/api/v1/inbox/pending', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;

    const rows = db.prepare(`
      SELECT * FROM pending_entries 
      WHERE user_id = ? AND is_consumed = 0 
      ORDER BY created_at ASC
    `).all(userId);

    const entries = rows.map((row) => ({
      id: row.id,
      date: row.date,
      slot: row.slot,
      content: row.content,
      calories: row.calories,
      protein: row.protein,
      carbs: row.carbs,
      fat: row.fat,
      detail: row.detail,
      items: row.items_json ? JSON.parse(row.items_json) : null,
      source: row.source,
      createdAt: row.created_at,
    }));

    return { entries };
  });

  // 3. 手机端确认条目已入库消费 (受 JWT 保护，仅能确认属于自己的条目)
  fastify.post('/api/v1/inbox/ack', { preHandler: authenticate }, async (request, reply) => {
    const userId = request.user.id;
    const { ids } = request.body || {};

    if (!Array.isArray(ids) || ids.length === 0) {
      return { success: true, count: 0 };
    }

    const placeholders = ids.map(() => '?').join(',');
    const stmt = db.prepare(`
      UPDATE pending_entries 
      SET is_consumed = 1 
      WHERE user_id = ? AND id IN (${placeholders})
    `);

    const result = stmt.run(userId, ...ids);

    return {
      success: true,
      consumedCount: result.changes
    };
  });

  // 4. 接收来自 QQMatrix 的通用技能后置动作 Webhook (Generic Skill Exit Hook)
  fastify.post('/internal/hooks/skill-exit', async (request, reply) => {
    const { event, skillId, userId, lastAssistantMessage } = request.body || {};

    if (event !== 'skill_exit' || !userId) {
      return reply.status(400).send({ error: { code: 'BAD_REQUEST', message: '非法事件负载' } });
    }

    // 针对饮食热量估算技能进行自动提取 (支持 meal_calorie_estimator, zhiqing_import_cloud 与 food)
    const validSkills = ['meal_calorie_estimator', 'food', 'meal_estimator', 'calorie', 'zhiqing_import_cloud', 'import', 'sync'];
    if (skillId && !validSkills.includes(skillId.toLowerCase())) {
      return { success: true, ignored: true, note: null };
    }

    // 检查 QQ 是否已与知轻绑定
    const binding = db.prepare('SELECT user_id FROM user_qq_bindings WHERE qq_id = ?').get(userId.toString());
    if (!binding) {
      return reply.status(200).send({
        success: false,
        note: `（⚠️ 您的 QQ 尚未绑定知轻账号，已跳过云端录入）`
      });
    }

    // 从 AI 助手的结构化回复文本中解析总卡路里
    const text = lastAssistantMessage || '';
    let calories = 500;
    const match = text.match(/(\d{2,4})\s*(?:kcal|大卡|卡路里|千卡)/i);
    if (match && match[1]) {
      calories = parseInt(match[1], 10);
    }

    // 本地日期 (避免 UTC 导致的东八区早 8 点前跨天问题)
    const d = new Date();
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const today = `${year}-${month}-${day}`;

    // 智能识别餐次 (早/中/晚/加餐)
    let slot = 'lunch';
    let content = '午餐打卡';
    const hour = d.getHours();
    if (text.includes('早餐') || text.includes('早饭') || (!text.includes('午') && !text.includes('晚') && hour >= 4 && hour < 10)) {
      slot = 'breakfast';
      content = '早餐打卡';
    } else if (text.includes('晚餐') || text.includes('晚饭') || (!text.includes('午') && hour >= 16 && hour < 22)) {
      slot = 'dinner';
      content = '晚餐打卡';
    } else if (text.includes('加餐') || text.includes('下午茶') || text.includes('零食') || hour >= 22 || hour < 4) {
      slot = 'snack';
      content = '加餐打卡';
    }

    const entryId = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);

    db.prepare(`
      INSERT INTO pending_entries (
        id, user_id, date, slot, content, calories, protein, carbs, fat, detail, items_json, source, created_at, is_consumed
      ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, ?, null, 'qq_bot', ?, 0)
    `).run(
      entryId,
      binding.user_id,
      today,
      slot,
      content,
      calories,
      text,
      now
    );

    return {
      success: true,
      note: `已自动存入知轻待录入信箱 (${content} ${calories} kcal) ✨`
    };
  });
}
