import { db } from '../db.js';
import { authenticate } from '../auth.js';
import crypto from 'node:crypto';
import { parseMealText } from '../utils/textParser.js';

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
    let finalItems = items;
    if ((!finalItems || finalItems.length === 0) && detail) {
      const parsed = parseMealText(detail);
      if (parsed.items && parsed.items.length > 0) {
        finalItems = parsed.items;
      }
    }
    const itemsJson = finalItems ? JSON.stringify(finalItems) : null;


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

    // 从 AI 助手的完整回复长文本中解析或直接使用插件已结构化的餐品数据
    const text = lastAssistantMessage || '';
    
    // 优先采用调用方 (如 QQ 插件已通过知轻提示词转换好) 的结构化数据
    const bodyContent = request.body.content;
    const bodyCalories = request.body.calories;
    const bodyProtein = request.body.protein;
    const bodyCarbs = request.body.carbs;
    const bodyFat = request.body.fat;
    const bodyItems = request.body.items;
    const bodySlot = request.body.slot;

    let finalContent = bodyContent;
    let finalCalories = bodyCalories;
    let finalProtein = bodyProtein !== undefined ? bodyProtein : null;
    let finalCarbs = bodyCarbs !== undefined ? bodyCarbs : null;
    let finalFat = bodyFat !== undefined ? bodyFat : null;
    let finalItems = bodyItems;
    let finalSlot = bodySlot;

    // 若未完全预先结构化，回退使用本地高精度文本解析器补全缺失字段
    if (!finalContent || finalCalories === undefined || !finalItems || finalItems.length === 0) {
      const parsed = parseMealText(text);
      if (!finalContent) {
        finalContent = parsed.content;
      }
      if (finalCalories === undefined) {
        finalCalories = parsed.calories;
      }
      if (finalProtein === null || finalProtein === undefined) {
        finalProtein = parsed.protein;
      }
      if (finalCarbs === null || finalCarbs === undefined) {
        finalCarbs = parsed.carbs;
      }
      if (finalFat === null || finalFat === undefined) {
        finalFat = parsed.fat;
      }
      if (!finalItems || finalItems.length === 0) {
        finalItems = parsed.items;
      }
      if (!finalSlot) {
        finalSlot = parsed.slot;
      }
    }

    if (!finalSlot) finalSlot = 'lunch';

    // 如果 content 中尚未包含食材明细，且具备食材项列表，智能追加食材明细行，确保输入框内容详尽完备
    if (finalItems && finalItems.length > 0 && finalContent && !finalContent.includes('食材明细')) {
      const itemStrings = finalItems.map(it => {
        const p = it.portion ? ` (${it.portion})` : '';
        return `${it.name}${p}`;
      });
      // 避免重复追加
      if (!finalContent.includes(finalItems[0].name)) {
        finalContent = `${finalContent}\n食材明细：${itemStrings.join('、')}`;
      }
    }

    // 本地日期 (避免 UTC 导致的东八区早 8 点前跨天问题)
    const d = new Date();
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const today = `${year}-${month}-${day}`;

    const entryId = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const itemsJson = (finalItems && finalItems.length > 0) ? JSON.stringify(finalItems) : null;

    db.prepare(`
      INSERT INTO pending_entries (
        id, user_id, date, slot, content, calories, protein, carbs, fat, detail, items_json, source, created_at, is_consumed
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'qq_bot', ?, 0)
    `).run(
      entryId,
      binding.user_id,
      today,
      finalSlot,
      finalContent,
      finalCalories,
      finalProtein || 0,
      finalCarbs || 0,
      finalFat || 0,
      text,
      itemsJson,
      now
    );

    let summaryNote = `已自动存入知轻待录入信箱：【${finalContent}】`;
    if (finalItems && finalItems.length > 0) {
      summaryNote += `包含 ${finalItems.length} 项，总热量 ${finalCalories} kcal ✨`;
    } else {
      summaryNote += `${finalCalories} kcal ✨`;
    }

    return {
      success: true,
      note: summaryNote,
      entry: {
        id: entryId,
        content: finalContent,
        calories: finalCalories,
        protein: finalProtein || 0,
        carbs: finalCarbs || 0,
        fat: finalFat || 0,
        items: finalItems || []
      }
    };
  });

}
