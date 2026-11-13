export default async function updateRoutes(fastify, options) {
  // 提供最新版本信息查询 (作为私有仓库或国内网络不佳时的更新中继)
  fastify.get('/api/v1/app/latest', async (request, reply) => {
    return {
      version: '1.5.2',
      title: '知轻 v1.5.2 - 云端同步幂等防重与脏数据自愈清洗',
      notes: '1. 云端同步幂等防重：新增本地信箱已消费状态持久化记录，彻底杜绝弱网与重试时的重复录入\n2. 并发互斥与流畅体验：合并高频下拉同步请求，确认消费改为后台异步静默发送，界面收起更极速\n3. 存量脏数据智能清洗：下拉刷新时自动检测并剔除多端协同产生的重复项，并同步修正打卡状态\n4. QQ 机器人协同增强：增加连接测试功能与专属自检脚本',
      publishedAt: '2026-11-13',
      apkUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/download/v1.5.2/zhiqing-v1.5.2-release.apk',
      apkName: 'zhiqing-v1.5.2-release.apk',
      apkSize: 25500000,
      htmlUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/tag/v1.5.2'
    };
  });
}
