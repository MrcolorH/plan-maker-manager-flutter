export default async function updateRoutes(fastify, options) {
  // 提供最新版本信息查询 (作为私有仓库或国内网络不佳时的更新中继)
  fastify.get('/api/v1/app/latest', async (request, reply) => {
    return {
      version: '1.5.3',
      title: '知轻 v1.5.3 - QQ 机器人多餐次导入与计划自动核销打卡',
      notes: '1. QQ 机器人多餐次识别与透传：支持显式早/中/晚/加餐指令、AI 语义判定与本地时间兜底三级决策\n2. 计划正餐自动核销打卡：导入正餐自动替换同餐次计划卡片，保留原计划名称参照并自动标记完成\n3. 同餐次二次追加合并：多段录入同一餐次时智能累加热量与宏量营养素、拼接明细食材，不重复生成卡片\n4. 日历完成度与连续打卡保障：核销条目完整参与打卡任务统计，连续打卡天数（Streak）正常递增\n5. 服务端与客户端幂等去重加固：修复接口 slot 覆盖问题，兼容核销后状态判定，杜绝弱网重入',
      publishedAt: '2026-11-19',
      apkUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/download/v1.5.3/zhiqing-v1.5.3-release.apk',
      apkName: 'zhiqing-v1.5.3-release.apk',
      apkSize: 23797307,
      htmlUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/tag/v1.5.3'
    };
  });
}
