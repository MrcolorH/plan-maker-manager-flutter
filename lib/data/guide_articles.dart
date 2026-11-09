/// 使用指引内容源（与旧版 guide.js 一致）
library;

class GuideStep {
  final String img;
  final List<dynamic> marks;
  final String text;
  const GuideStep({this.img = '', this.marks = const [], required this.text});
}

class GuideArticle {
  final String id;
  final String icon;
  final String title;
  final String summary;
  final List<GuideStep> steps;
  const GuideArticle({
    required this.id,
    required this.icon,
    required this.title,
    required this.summary,
    required this.steps,
  });
}

const List<GuideArticle> kGuideArticles = [
  GuideArticle(
    id: 'onboarding',
    icon: '🚀',
    title: '首次引导：三步开始',
    summary: '填基础信息 → 录入计划 → AI 生成并确认',
    steps: [
      GuideStep(text: '首次打开 App 会自动进入引导。第一步填写性别、年龄、身高、体重和日常活动量，App 用 Mifflin-St Jeor 公式算出你的基础代谢（BMR）和每日基础消耗，并推荐一个每日目标摄入（可修改）。'),
      GuideStep(text: '第二步录入你的计划，两种方式任选：「逐条录入」一餐一餐加，可以选餐类、时间、星期几；「整日一句话」把今天想吃的全写在一句话里，交给 AI 拆分。想练的运动也可以一起加。'),
      GuideStep(text: '第三步 AI 生成计划：拆分餐次、配好时间、估算每个条目的热量/消耗。生成后、确认之前，每一条都能编辑、删除、重新估算，顶部实时显示预计摄入、消耗和缺口。'),
      GuideStep(text: '点「确认完成，开始用」就正式生效：今日页立即展示当日安排。跳过引导也没关系，这篇教程随时可以回看。'),
    ],
  ),
  GuideArticle(
    id: 'checkin',
    icon: '✅',
    title: '每日打卡与实际热量',
    summary: '一键打卡，吃多吃少随时调整',
    steps: [
      GuideStep(text: '「今日」页按时间列出当天的餐食和运动：点卡片右侧圆形按钮即可打卡，再点一次取消（仅当天可改）。顶部大数字是今天的热量缺口，下方四格是目标 / 已摄入 / 消耗 / 运动。'),
      GuideStep(text: '没按计划吃？点卡片上的「✎」调整「今日实际摄入」：可以直接改数字，也可以大白话描述（如"没买到豆浆只吃了两个包子"）让 AI 估算并给出拆解。只影响今天，明天自动恢复计划值。'),
      GuideStep(text: '点卡片空白处进入计划详情：餐食有食材清单和做法步骤，运动有训练环节和时长。详情页还可以从计划中删除该项。'),
    ],
  ),
  GuideArticle(
    id: 'import',
    icon: '📥',
    title: '导入与更换计划',
    summary: 'AI 文档转计划 / 手动 JSON，增量合并不丢记录',
    steps: [
      GuideStep(text: '「计划」页点「导入计划」进入导入页，默认是「✨ AI 生成」模式：把你的减脂餐单 / 运动计划文档（Markdown、纯文本、聊天记录都行）整段粘贴进来，点「AI 生成计划」，10~30 秒自动转成结构化计划。需要先在设置里配置 AI Key。'),
      GuideStep(text: '生成后会先进入预览：显示计划名、时间段、餐食 / 运动条数、目标热量和体重目标，确认无误再点「确认导入」。导入是增量合并：相同 id 更新、新 id 追加，历史打卡记录全部保留。'),
      GuideStep(text: '导入后在「计划」页总览全部条目（可按餐食 / 运动切换，显示星期徽标）。换计划时重新导入即可；单项删除在详情页操作，分模块清空在计划页或设置页。'),
    ],
  ),
  GuideArticle(
    id: 'add-snack',
    icon: '🍪',
    title: '加餐记录',
    summary: '常用方案快捷加餐 / 智能混合估算 / 手动录入，添加即计入今日缺口',
    steps: [
      GuideStep(text: '今日页点「＋ 今日加餐」进入加餐页。顶部展示常用方案，点击可自选份量（0.5/1/1.5/2份）快速记录，长按可删除管理。'),
      GuideStep(text: '智能估算集成了食物库与 AI：输入一句话描述（如「半个香辣鸡腿堡」「200g米饭」），优先端侧秒级匹配并自动折算热量，也支持以 AI 重新测算；未收录则自动调用 AI。采纳存为常用方案后会自动沉淀入本地食物库。'),
      GuideStep(text: '加餐的特点：添加即计入今日热量缺口（无需打卡），只记在今天、明天自动消失，不影响整体计划和完成度统计。今日页的加餐列表可以随时删除单条，缺口自动扣回。'),
    ],
  ),
  GuideArticle(
    id: 'add-exercise',
    icon: '🏃',
    title: '加练（计划外运动）',
    summary: '练了计划外的？AI 算消耗，立即计入今天',
    steps: [
      GuideStep(text: '今天多练了？在今日页运动区点「＋ 今日运动」：一句大白话描述项目（如"慢跑 40 分钟"），点「AI 算」自动估算消耗（按你在引导里填的体重计算，更准），也可以直接手填。'),
      GuideStep(text: '临时运动立即计入今日消耗（缺口 = 基础消耗 + 运动消耗 − 摄入），仅当天有效，不影响整体计划与完成度。列表里可随时删除。'),
      GuideStep(text: '小技巧：统计页的日历点开某一天，也能给那一天补录加餐和临时运动（近 3 天），忘记当天记录也不怕。'),
    ],
  ),
  GuideArticle(
    id: 'ai-config',
    icon: '🤖',
    title: '配置 AI 服务',
    summary: '服务商 / API Key / 测试连接，Key 仅存本机',
    steps: [
      GuideStep(text: '「设置 → AI 服务」：先选服务商（DeepSeek / Kimi / MiMo / MiniMax / 自定义，选好自动填接口地址和默认模型），再粘贴 API Key。选「自定义」可填任意 OpenAI 兼容接口地址。点「测试连接」会实际发一句测试问答，验证地址 / 模型 / Key 是否可用。'),
      GuideStep(text: '「查询余额」行（DeepSeek）可以看账户余额，同屏展示本 App 的累计用量：调用次数、输入 / 输出 tokens 和估算费用，支持清零统计。Key 只保存在本机，不会上传。'),
      GuideStep(text: 'AI 在 App 里的用途：导入页把计划文档转 JSON、引导页生成计划、查询食物热量、估算实际摄入和运动消耗。没配 AI 也不影响核心功能，手动录入永远可用。'),
    ],
  ),
  GuideArticle(
    id: 'stats',
    icon: '📊',
    title: '统计与复盘',
    summary: '周图 / 月历 / 日详情 / 月回顾怎么用',
    steps: [
      GuideStep(text: '「统计」页顶部是连续完成与累计完成天数；本周视图每天显示完成度（n/m）和热量缺口，中轴 0 线：缺口为正向上绿柱、超标向下橙柱。'),
      GuideStep(text: '月历按完成情况着色：深绿 = 全部完成、浅绿 = 部分完成、灰 = 无数据、空心绿圈「待开始」= 已排计划还没到。点任意一天弹出日详情：当天逐项清单、计划外加餐、运动消耗一目了然（近 3 天可补打卡 / 补录）。'),
      GuideStep(text: '月历标题旁的「月回顾」：显示本月计划完成天数、总缺口、日均缺口，以及「消耗最多的一天」和「摄入最多的一天」（可点「查看详情」下钻当天）。开始计划之前的日期不参与统计。'),
    ],
  ),
];
