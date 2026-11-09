import { db, initDatabase } from './db.js';

initDatabase();

const customCode = process.argv[2];

if (customCode) {
  // 添加指定邀请码
  try {
    db.prepare('INSERT INTO invite_codes (code, is_used, created_at) VALUES (?, 0, ?)').run(
      customCode.trim(),
      Math.floor(Date.now() / 1000)
    );
    console.log(`✅ 成功创建指定邀请码: ${customCode.trim()}`);
  } catch (err) {
    if (err.message.includes('UNIQUE constraint failed')) {
      console.log(`⚠️ 邀请码 [${customCode.trim()}] 已存在！`);
    } else {
      console.error('❌ 创建失败:', err.message);
    }
  }
} else {
  // 随机生成一个
  const randomSuffix = Math.floor(1000 + Math.random() * 9000);
  const newCode = `ZQ${randomSuffix}`;
  db.prepare('INSERT INTO invite_codes (code, is_used, created_at) VALUES (?, 0, ?)').run(
    newCode,
    Math.floor(Date.now() / 1000)
  );
  console.log(`✅ 成功生成新的邀请码: ${newCode}`);
}

// 打印当前所有可用邀请码
const available = db.prepare("SELECT code, datetime(created_at, 'unixepoch', 'localtime') as created_time FROM invite_codes WHERE is_used = 0").all();
console.log('\n📋 当前所有【有效/未被使用】的邀请码:');
if (available.length === 0) {
  console.log('  (暂无可用邀请码)');
} else {
  available.forEach((item, index) => {
    console.log(`  ${index + 1}. ${item.code} (创建时间: ${item.created_time})`);
  });
}
