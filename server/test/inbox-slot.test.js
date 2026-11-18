import Fastify from 'fastify';
import assert from 'node:assert';
import { db, initDatabase } from '../src/db.js';
import inboxRoutes from '../src/routes/inbox.js';

initDatabase();

// 插入一个测试用户与绑定
const rand = Math.floor(Math.random() * 100000);
const testUsername = `test_slot_user_${rand}`;
const testQqId = `999${rand}`;

const userRes = db.prepare('INSERT INTO users (username, password_hash, created_at) VALUES (?, ?, ?)').run(
  testUsername, 'hash', Math.floor(Date.now() / 1000)
);
const testUserId = userRes.lastInsertRowid;

db.prepare('INSERT INTO user_qq_bindings (qq_id, user_id, bound_at) VALUES (?, ?, ?)').run(
  testQqId, testUserId, Math.floor(Date.now() / 1000)
);

const app = Fastify();
await app.register(inboxRoutes);

console.log('--- 测试 1: 显式传入 slot="breakfast" ---');
const res1 = await app.inject({
  method: 'POST',
  url: '/internal/hooks/skill-exit',
  payload: {
    event: 'skill_exit',
    skillId: 'zhiqing_import_cloud',
    userId: testQqId,
    slot: 'breakfast',
    content: '煎蛋2个',
    calories: 180,
    items: [{ name: '煎蛋', portion: '2个', calories: 180 }]
  }
});
const body1 = JSON.parse(res1.body);
assert.strictEqual(body1.success, true);
assert.strictEqual(body1.entry.slot, 'breakfast');
const row1 = db.prepare('SELECT slot FROM pending_entries WHERE id = ?').get(body1.entry.id);
assert.strictEqual(row1.slot, 'breakfast');
console.log('✅ 测试 1 通过！');

console.log('--- 测试 2: 显式传入 slot="dinner" ---');
const res2 = await app.inject({
  method: 'POST',
  url: '/internal/hooks/skill-exit',
  payload: {
    event: 'skill_exit',
    skillId: 'zhiqing_import_cloud',
    userId: testQqId,
    slot: 'dinner',
    content: '清蒸鱼',
    calories: 300,
    items: [{ name: '清蒸鱼', portion: '1份', calories: 300 }]
  }
});
const body2 = JSON.parse(res2.body);
assert.strictEqual(body2.success, true);
assert.strictEqual(body2.entry.slot, 'dinner');
const row2 = db.prepare('SELECT slot FROM pending_entries WHERE id = ?').get(body2.entry.id);
assert.strictEqual(row2.slot, 'dinner');
console.log('✅ 测试 2 通过！');

console.log('--- 测试 3: 未传 slot，但 lastAssistantMessage 文本推断为晚餐 ---');
const res3 = await app.inject({
  method: 'POST',
  url: '/internal/hooks/skill-exit',
  payload: {
    event: 'skill_exit',
    skillId: 'zhiqing_import_cloud',
    userId: testQqId,
    content: '晚餐：牛肉面',
    calories: 600,
    items: [{ name: '牛肉面', portion: '1碗', calories: 600 }],
    lastAssistantMessage: '这顿晚餐包含：牛肉面 1碗 600 kcal'
  }
});
const body3 = JSON.parse(res3.body);
assert.strictEqual(body3.success, true);
assert.strictEqual(body3.entry.slot, 'dinner');
const row3 = db.prepare('SELECT slot FROM pending_entries WHERE id = ?').get(body3.entry.id);
assert.strictEqual(row3.slot, 'dinner');
console.log('✅ 测试 3 通过！');

// 清理测试数据
db.prepare('DELETE FROM pending_entries WHERE user_id = ?').run(testUserId);
db.prepare('DELETE FROM user_qq_bindings WHERE user_id = ?').run(testUserId);
db.prepare('DELETE FROM users WHERE id = ?').run(testUserId);

console.log('🎉 所有服务端 slot 测试全部通过！');
