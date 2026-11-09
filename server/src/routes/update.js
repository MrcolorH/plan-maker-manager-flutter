export default async function updateRoutes(fastify, options) {
  // 提供最新版本信息查询 (作为私有仓库或国内网络不佳时的更新中继)
  fastify.get('/api/v1/app/latest', async (request, reply) => {
    return {
      version: '1.5.0',
      title: '知轻 v1.5.0 - 云端同步与灾备、QQ 机器人协同与营养成分识别',
      notes: '1. 云端同步与灾备：支持私有微服务无感收件箱同步、全量快照云备份与多版本回滚保护\n2. QQ 机器人多端协同：支持 QQ 拍照识别饮食热量并一键自动打卡入库\n3. 预包装食品营养识别：拍照识别食品配料表与营养成分表，Telegram 风格轻交互与营养指标换算\n4. 周边健康餐饮推荐：基于真实地理位置智能推荐减脂餐食与热量预估\n5. 离线优先与生命周期：启动及切回前台时静默自动同步待录入信箱',
      publishedAt: '2026-11-09',
      apkUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/download/v1.5.0/zhiqing-v1.5.0-release.apk',
      apkName: 'zhiqing-v1.5.0-release.apk',
      apkSize: 25042456,
      htmlUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/tag/v1.5.0'
    };
  });
}
