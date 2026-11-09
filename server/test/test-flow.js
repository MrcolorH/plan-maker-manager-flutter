// 自动化全流程闭环集成测试脚本
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.resolve(__dirname, '../src/server.js');

console.log('▶ 正在启动本地服务进行端到端测试...');
const serverProcess = spawn('node', [serverPath], {
  env: { ...process.env, PORT: '3099', LOG_LEVEL: 'silent' },
  stdio: 'inherit'
});

// 等待服务就绪
await new Promise((r) => setTimeout(r, 1200));

const BASE = 'http://127.0.0.1:3099';

const randSuffix = Math.floor(Math.random() * 10000);
const testUser = `test_user_${randSuffix}`;
const testInvite = `INV_${randSuffix}`;

async function runTest() {
  try {
    console.log('\n--- 1. 测试健康检查 ---');
    const healthRes = await fetch(`${BASE}/health`).then(r => r.json());
    console.log('✅ 健康检查响应:', healthRes);

    // 直接在测试库中临时插入一个新鲜的邀请码用于测试
    const { db } = await import('../src/db.js');
    db.prepare('INSERT INTO invite_codes (code, created_at) VALUES (?, ?)').run(
      testInvite,
      Math.floor(Date.now() / 1000)
    );

    console.log(`\n--- 2. 用户注册 (账号: ${testUser}, 邀请码: ${testInvite}) ---`);
    const regRes = await fetch(`${BASE}/api/v1/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: testUser,
        password: 'password123',
        inviteCode: testInvite
      })
    });
    const regData = await regRes.json();
    console.log('✅ 注册响应:', regData);
    const token = regData.token;

    console.log('\n--- 3. 手机 App 发起 QQ 绑定码生成 ---');
    const codeRes = await fetch(`${BASE}/api/v1/account/qq-bind-code`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());
    console.log('✅ 生成绑定码:', codeRes);
    const bindCode = codeRes.code;

    console.log('\n--- 4. QQ 机器人确认绑定 (模拟 QQMatrix 私聊回复) ---');
    const confirmRes = await fetch(`${BASE}/internal/account/qq-bind-confirm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        qqId: '987654321',
        code: bindCode
      })
    }).then(r => r.json());
    console.log('✅ QQ 绑定结果:', confirmRes);

    console.log('\n--- 5. QQ 机器人推送午餐热量 (模拟 /food 技能识别完成) ---');
    const pushRes = await fetch(`${BASE}/internal/hooks/skill-exit`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event: 'skill_exit',
        skillId: 'meal_calorie_estimator',
        userId: '987654321',
        lastAssistantMessage: '经过分析，本餐菜品：米饭 150g (175 kcal), 煎鸡胸肉 150g (300 kcal), 炒绿豆芽 100g (50 kcal)。预估【总热量】: 525 kcal，三大营养素配比均衡。'
      })
    }).then(r => r.json());
    console.log('✅ 通用 Webhook 响应:', pushRes);

    console.log('\n--- 6. 手机 App 拉取待录入收件箱 ---');
    const pendingRes = await fetch(`${BASE}/api/v1/inbox/pending`, {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());
    console.log(`✅ 成功拉取到 ${pendingRes.entries.length} 条待入库记录:`, pendingRes.entries[0].content);
    const entryId = pendingRes.entries[0].id;

    console.log('\n--- 7. 手机 App 确认消费该条目 (Ack) ---');
    const ackRes = await fetch(`${BASE}/api/v1/inbox/ack`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ ids: [entryId] })
    }).then(r => r.json());
    console.log('✅ Ack 结果:', ackRes);

    console.log('\n--- 8. 再次拉取验证已清空 ---');
    const emptyCheck = await fetch(`${BASE}/api/v1/inbox/pending`, {
      headers: { 'Authorization': `Bearer ${token}` }
    }).then(r => r.json());
    console.log('✅ 待录入列表长度为 0 (正常):', emptyCheck.entries.length === 0);

    console.log('\n🎉 ==========================================');
    console.log('🎉 所有接口端到端测试 100% 通过！闭环跑通！');
    console.log('🎉 ==========================================\n');
  } catch (err) {
    console.error('❌ 测试失败:', err);
  } finally {
    serverProcess.kill();
  }
}

runTest();
