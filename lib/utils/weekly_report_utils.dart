/// 周度减脂数据聚合与复盘 Prompt 组装工具
/// 100% 本地运算，保证数学绝对精确、零等待秒开
library;

import 'dart:math' as math;

import '../models/onboarding.dart';
import '../models/plan_data.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../models/weight.dart';
import 'calorie_utils.dart';
import 'date_utils.dart';

/// 单日聚合快照（专供周报统计使用）
class WeeklyDaySnapshot {
  final String date;
  final String weekdayName; // "周一" ... "周日"
  final DailySummary summary;
  final double? weight;
  final double? bodyFat;
  final bool hasData;
  final bool isFuture;

  const WeeklyDaySnapshot({
    required this.date,
    required this.weekdayName,
    required this.summary,
    this.weight,
    this.bodyFat,
    required this.hasData,
    required this.isFuture,
  });
}

/// 7 天周期统计数据模型（本地完全计算）
class WeeklyReportStats {
  final String startDate; // YYYY-MM-DD (周一)
  final String endDate;   // YYYY-MM-DD (周日)
  final String weekLabel; // 如 "2026年第41周" 或 "10月12日 - 10月18日"
  final bool isCurrentWeek;

  // 逐日快照（固定 7 天）
  final List<WeeklyDaySnapshot> days;

  // 体重与体脂
  final double? startWeight; // 周期起点生效体重
  final double? endWeight;   // 周期末尾生效体重
  final double? weightDelta; // 末 - 初（负数表示减轻）
  final double? minWeight;   // 周期内记录的最低体重
  final double? maxWeight;   // 周期内记录的最高体重
  final int weightRecordCount; // 7天内称重录入天数
  final double? startBodyFat;
  final double? endBodyFat;
  final double? bodyFatDelta;

  // 热量与缺口
  final int totalIntake;      // 7天总摄入 kcal
  final int avgIntake;        // 日均摄入 kcal
  final int totalBurn;        // 7天总消耗 kcal
  final int avgBurn;          // 日均消耗 kcal
  final int totalDeficit;     // 7天累计缺口 kcal（消耗 - 摄入，正数代表缺口，负数超标）
  final int avgDeficit;       // 日均缺口 kcal
  final double estimatedFatLossKg; // 理论减脂公斤数 (totalDeficit / 7700)

  // 三大宏量营养素（实际摄入）
  final int totalProtein;     // 克
  final int avgProtein;
  final int totalCarbs;       // 克
  final int avgCarbs;
  final int totalFat;         // 克
  final int avgFat;
  final int proteinPercent;   // 蛋白质供能比 (P*4 / 总宏量大卡) %
  final int carbsPercent;     // 碳水供能比 (C*4 / 总宏量大卡) %
  final int fatPercent;       // 脂肪供能比 (F*9 / 总宏量大卡) %

  // 目标对比
  final int targetDailyCalories; // 设定的每日目标热量
  final int? targetProtein;      // 目标每日蛋白质
  final int? targetCarbs;        // 目标每日碳水
  final int? targetFat;          // 目标每日脂肪

  // 打卡与执行度
  final int totalPlannedTasks; // 计划任务总数
  final int totalDoneTasks;    // 已完成打卡数
  final int taskComplianceRate;// 打卡完成率 (0~100)%
  final int recordedDays;      // 有任意打卡/记录的天数 (0~7)

  // 运动情况
  final int exerciseDays;      // 有运动的天数
  final int totalExerciseBurn; // 运动总消耗 kcal
  final List<String> exerciseNames; // 主要运动项目名

  const WeeklyReportStats({
    required this.startDate,
    required this.endDate,
    required this.weekLabel,
    required this.isCurrentWeek,
    required this.days,
    this.startWeight,
    this.endWeight,
    this.weightDelta,
    this.minWeight,
    this.maxWeight,
    required this.weightRecordCount,
    this.startBodyFat,
    this.endBodyFat,
    this.bodyFatDelta,
    required this.totalIntake,
    required this.avgIntake,
    required this.totalBurn,
    required this.avgBurn,
    required this.totalDeficit,
    required this.avgDeficit,
    required this.estimatedFatLossKg,
    required this.totalProtein,
    required this.avgProtein,
    required this.totalCarbs,
    required this.avgCarbs,
    required this.totalFat,
    required this.avgFat,
    required this.proteinPercent,
    required this.carbsPercent,
    required this.fatPercent,
    required this.targetDailyCalories,
    this.targetProtein,
    this.targetCarbs,
    this.targetFat,
    required this.totalPlannedTasks,
    required this.totalDoneTasks,
    required this.taskComplianceRate,
    required this.recordedDays,
    required this.exerciseDays,
    required this.totalExerciseBurn,
    required this.exerciseNames,
  });

  /// 是否有足够的数据生成复盘
  bool get hasSufficientData => recordedDays > 0 || weightRecordCount > 0;
}

/// 计算指定周（weekOffset: 0 = 本周，-1 = 上周）的完整本地统计
WeeklyReportStats calculateWeeklyReportStats({
  required PlanData plan,
  required AppSettings settings,
  required RecordStore records,
  UserProfile? profile,
  int weekOffset = 0, // 0 = 本周，-1 = 上周
}) {
  final today = todayStr();
  final currentWd = parseDate(today).weekday; // 1=周一 ... 7=周日
  final currentMonday = addDays(today, -(currentWd - 1));

  // 目标周的周一和周日
  final targetMonday = addDays(currentMonday, weekOffset * 7);
  final targetSunday = addDays(targetMonday, 6);
  final isCurrentWeek = (weekOffset == 0);

  final monParts = parseDate(targetMonday);
  final sunParts = parseDate(targetSunday);
  final weekLabel = '${monParts.m}月${monParts.d}日 - ${sunParts.m}月${sunParts.d}日';

  final days = <WeeklyDaySnapshot>[];
  var totalIntake = 0;
  var totalBurn = 0;
  var totalProtein = 0;
  var totalCarbs = 0;
  var totalFat = 0;
  var totalPlannedTasks = 0;
  var totalDoneTasks = 0;
  var recordedDays = 0;
  var exerciseDays = 0;
  var totalExerciseBurn = 0;
  final exerciseNames = <String>{};

  // 体重收集：收集该周实际录入的体重条目
  final weekWeightEntries = <String, WeightEntry>{};
  for (var i = 0; i < 7; i++) {
    final dStr = addDays(targetMonday, i);
    final entry = records.weightRecords.records[dStr];
    if (entry != null && entry.weight > 0) {
      weekWeightEntries[dStr] = entry;
    }
  }

  // 逐日统计
  var validStatDays = 0;
  for (var i = 0; i < 7; i++) {
    final dStr = addDays(targetMonday, i);
    final isFuture = dStr.compareTo(today) > 0;
    final summary = dailySummary(plan, settings, records, dStr, profile: profile);
    final w = weightForDate(records, dStr);
    final bf = bodyFatForDate(records, dStr);
    final wd = parseDate(dStr).weekday;

    final hasData = summary.hasData || weekWeightEntries.containsKey(dStr);
    if (hasData) recordedDays++;

    if (!isFuture) {
      validStatDays++;
      totalIntake += summary.intake.round();
      totalBurn += summary.burn.round();
      totalProtein += summary.intakeProtein;
      totalCarbs += summary.intakeCarbs;
      totalFat += summary.intakeFat;

      totalPlannedTasks += summary.taskCount;
      totalDoneTasks += summary.doneCount;

      if (summary.exerciseBurn > 0) {
        exerciseDays++;
        totalExerciseBurn += summary.exerciseBurn.round();
      }

      // 提取当日运动名称
      final entries = records.dayEntries[dStr];
      if (entries != null) {
        for (final e in entries.where((e) => e.kind == 'exercise')) {
          if (e.items != null && e.items!.isNotEmpty) {
            for (final it in e.items!) {
              if (it.name.isNotEmpty) exerciseNames.add(it.name);
            }
          } else if (e.content.isNotEmpty) {
            exerciseNames.add(e.content);
          }
        }
      }
    }

    days.add(WeeklyDaySnapshot(
      date: dStr,
      weekdayName: '周${weekCn(wd)}',
      summary: summary,
      weight: w,
      bodyFat: bf,
      hasData: hasData,
      isFuture: isFuture,
    ));
  }

  // 计算体重变化：优先周内实际录入的起点和终点
  double? startWeight;
  double? endWeight;
  double? minWeight;
  double? maxWeight;
  double? startBodyFat;
  double? endBodyFat;

  if (weekWeightEntries.isNotEmpty) {
    final sortedDates = weekWeightEntries.keys.toList()..sort();
    startWeight = weekWeightEntries[sortedDates.first]?.weight;
    endWeight = weekWeightEntries[sortedDates.last]?.weight;
    startBodyFat = weekWeightEntries[sortedDates.first]?.bodyFat;
    endBodyFat = weekWeightEntries[sortedDates.last]?.bodyFat;

    for (final e in weekWeightEntries.values) {
      minWeight = (minWeight == null) ? e.weight : math.min(minWeight, e.weight);
      maxWeight = (maxWeight == null) ? e.weight : math.max(maxWeight, e.weight);
    }
  } else {
    // 若本周未称重，向前沿用生效体重
    startWeight = weightForDate(records, targetMonday);
    endWeight = weightForDate(records, targetSunday);
    startBodyFat = bodyFatForDate(records, targetMonday);
    endBodyFat = bodyFatForDate(records, targetSunday);
  }

  final weightDelta = (startWeight != null && endWeight != null)
      ? (endWeight - startWeight)
      : null;
  final bodyFatDelta = (startBodyFat != null && endBodyFat != null)
      ? (endBodyFat - startBodyFat)
      : null;

  final totalDeficit = totalBurn - totalIntake;
  final divDays = math.max(1, validStatDays);
  final avgIntake = (totalIntake / divDays).round();
  final avgBurn = (totalBurn / divDays).round();
  final avgDeficit = (totalDeficit / divDays).round();
  final estimatedFatLossKg = totalDeficit / 7700.0;

  final avgProtein = (totalProtein / divDays).round();
  final avgCarbs = (totalCarbs / divDays).round();
  final avgFat = (totalFat / divDays).round();

  // 供能比计算
  final pCal = totalProtein * 4;
  final cCal = totalCarbs * 4;
  final fCal = totalFat * 9;
  final macroTotalCal = pCal + cCal + fCal;
  final proteinPercent = macroTotalCal > 0 ? (pCal * 100 / macroTotalCal).round() : 0;
  final carbsPercent = macroTotalCal > 0 ? (cCal * 100 / macroTotalCal).round() : 0;
  final fatPercent = macroTotalCal > 0 ? (fCal * 100 / macroTotalCal).round() : 0;

  // 目标
  final targetDailyCalories = (plan.meta.dailyCalorieTarget != null && plan.meta.dailyCalorieTarget! > 0)
      ? plan.meta.dailyCalorieTarget!.round()
      : (settings.dailyCalorieTarget > 0 ? settings.dailyCalorieTarget : settings.tdee);

  final taskComplianceRate = totalPlannedTasks > 0
      ? (totalDoneTasks * 100 / totalPlannedTasks).round()
      : (totalDoneTasks > 0 ? 100 : 0);

  return WeeklyReportStats(
    startDate: targetMonday,
    endDate: targetSunday,
    weekLabel: weekLabel,
    isCurrentWeek: isCurrentWeek,
    days: days,
    startWeight: startWeight,
    endWeight: endWeight,
    weightDelta: weightDelta,
    minWeight: minWeight,
    maxWeight: maxWeight,
    weightRecordCount: weekWeightEntries.length,
    startBodyFat: startBodyFat,
    endBodyFat: endBodyFat,
    bodyFatDelta: bodyFatDelta,
    totalIntake: totalIntake,
    avgIntake: avgIntake,
    totalBurn: totalBurn,
    avgBurn: avgBurn,
    totalDeficit: totalDeficit,
    avgDeficit: avgDeficit,
    estimatedFatLossKg: estimatedFatLossKg,
    totalProtein: totalProtein,
    avgProtein: avgProtein,
    totalCarbs: totalCarbs,
    avgCarbs: avgCarbs,
    totalFat: totalFat,
    avgFat: avgFat,
    proteinPercent: proteinPercent,
    carbsPercent: carbsPercent,
    fatPercent: fatPercent,
    targetDailyCalories: targetDailyCalories,
    targetProtein: plan.meta.targetProtein,
    targetCarbs: plan.meta.targetCarbs,
    targetFat: plan.meta.targetFat,
    totalPlannedTasks: totalPlannedTasks,
    totalDoneTasks: totalDoneTasks,
    taskComplianceRate: taskComplianceRate,
    recordedDays: recordedDays,
    exerciseDays: exerciseDays,
    totalExerciseBurn: totalExerciseBurn,
    exerciseNames: exerciseNames.toList(),
  );
}

/// 组装发给 AI 的事实数据摘要（精简、清晰、免去 AI 算术运算）
String buildWeeklyStatsSummaryForAi(WeeklyReportStats stats, {UserProfile? profile}) {
  final sb = StringBuffer();
  sb.writeln('【周期范围】${stats.startDate} 至 ${stats.endDate}（${stats.weekLabel}）');

  if (profile != null && profile.complete) {
    sb.writeln('【用户画像】性别：${profile.gender == 'male' ? '男' : '女'}，年龄：${profile.age}岁，身高：${profile.height}cm');
  }

  sb.writeln('【体重体脂数据】');
  if (stats.startWeight != null && stats.endWeight != null) {
    final d = stats.weightDelta!;
    final sign = d > 0 ? '+' : '';
    sb.writeln('- 起始体重：${stats.startWeight!.toStringAsFixed(2)} kg ➔ 期末体重：${stats.endWeight!.toStringAsFixed(2)} kg（净变化：$sign${d.toStringAsFixed(2)} kg）');
    if (stats.minWeight != null && stats.maxWeight != null) {
      sb.writeln('- 本周最高：${stats.maxWeight!.toStringAsFixed(2)} kg，最低：${stats.minWeight!.toStringAsFixed(2)} kg，录入天数：${stats.weightRecordCount}/7 天');
    }
  } else {
    sb.writeln('- 本周暂无完整体重对比数据');
  }

  if (stats.startBodyFat != null && stats.endBodyFat != null) {
    final d = stats.bodyFatDelta!;
    final sign = d > 0 ? '+' : '';
    sb.writeln('- 体脂率变化：${stats.startBodyFat!.toStringAsFixed(1)}% ➔ ${stats.endBodyFat!.toStringAsFixed(1)}%（$sign${d.toStringAsFixed(1)}%）');
  }

  sb.writeln('【热量收支与缺口】');
  sb.writeln('- 每日目标摄入：${stats.targetDailyCalories} kcal');
  sb.writeln('- 实际日均摄入：${stats.avgIntake} kcal（7天总摄入：${stats.totalIntake} kcal）');
  sb.writeln('- 实际日均消耗：${stats.avgBurn} kcal（7天总消耗：${stats.totalBurn} kcal，含基础消耗与运动）');
  sb.writeln('- 7天累计热量缺口：${stats.totalDeficit} kcal（日均缺口：${stats.avgDeficit} kcal）');
  sb.writeln('- 理论消耗纯脂肪估算：约 ${stats.estimatedFatLossKg.toStringAsFixed(2)} kg');

  sb.writeln('【三大宏量营养素日均摄入】');
  sb.writeln('- 蛋白质：日均 ${stats.avgProtein}g（供能占比约 ${stats.proteinPercent}%）${stats.targetProtein != null ? '，目标 ${stats.targetProtein}g' : ''}');
  sb.writeln('- 碳水化合物：日均 ${stats.avgCarbs}g（供能占比约 ${stats.carbsPercent}%）${stats.targetCarbs != null ? '，目标 ${stats.targetCarbs}g' : ''}');
  sb.writeln('- 脂肪：日均 ${stats.avgFat}g（供能占比约 ${stats.fatPercent}%）${stats.targetFat != null ? '，目标 ${stats.targetFat}g' : ''}');

  sb.writeln('【执行与运动】');
  sb.writeln('- 计划打卡完成率：${stats.taskComplianceRate}%（共记录打卡 ${stats.totalDoneTasks}/${stats.totalPlannedTasks} 项）');
  sb.writeln('- 有记录天数：${stats.recordedDays}/7 天');
  sb.writeln('- 运动记录：共运动 ${stats.exerciseDays} 天，总计额外消耗 ${stats.totalExerciseBurn} kcal');
  if (stats.exerciseNames.isNotEmpty) {
    sb.writeln('- 主要运动项目：${stats.exerciseNames.join('、')}');
  }

  return sb.toString();
}

/// 组装“一键复制向外部 AI 提问”的完整 Prompt
String buildExternalAiPrompt(WeeklyReportStats stats, {UserProfile? profile}) {
  final summary = buildWeeklyStatsSummaryForAi(stats, profile: profile);
  return '''你是资深临床营养师与国家级运动减脂教练。
以下是我在减脂记录 App 中统计出的真实 7 天周期减脂数据：

$summary

请根据以上客观数据，为我出具一份高质量的【减脂周度复盘与下周指导】：

1. 🌟【本周整体点评】（150~250字）：
   - 客观评价我本周的减脂节奏与掉秤成效；
   - 深入分析我的饮食结构优缺点（如：蛋白质是否达标、脂肪是否偏高、热量缺口是否过大或偏小）；
   - 评价运动与生活作息配合情况。

2. 🎯【未来一周减脂建议】（务必具体、可落地，2~3条清晰行动指令）：
   - 摄入目标微调建议（是否需要调整热量预算或三大营养素比例）；
   - 三餐具体微习惯改进（如：“早餐增加一个水煮蛋提升饱腹感”、“午餐少放两勺汤汁减少隐藏油脂”等）；
   - 下周运动与活动量微调建议。

3. 💡【教练寄语与心态锦囊】（50~100字）：
   - 针对平台期或心态给一句真诚暖心的支持与提醒。

要求：
- 语气专业温和、像有温度的私人专属教练；
- 拒绝假大空的套话，建议必须能立刻落实到下一周的每一餐中；
- 针对上面提供的数据说话，不要凭空猜测数据。''';
}

/// 组装完整文本报告（将本地数据看板 + AI 点评合并为清晰的 Markdown 文本）
String buildFullMarkdownReport({
  required WeeklyReportStats stats,
  required String headline,
  required String review,
  required List<String> suggestions,
  required String encouragement,
  UserProfile? profile,
}) {
  final sb = StringBuffer();
  sb.writeln('# 🌿 知轻 · 减脂周度复盘报告');
  sb.writeln('> 周期：${stats.startDate} 至 ${stats.endDate}（${stats.weekLabel}）\n');

  sb.writeln('## 📊 本周硬核数据看板');
  if (stats.startWeight != null && stats.endWeight != null) {
    final d = stats.weightDelta!;
    final sign = d > 0 ? '+' : '';
    sb.writeln('- **体重变化**：${stats.startWeight!.toStringAsFixed(1)} kg ➔ ${stats.endWeight!.toStringAsFixed(1)} kg（**$sign${d.toStringAsFixed(1)} kg**）');
  }
  sb.writeln('- **热量收支**：日均摄入 ${stats.avgIntake} kcal / 日均消耗 ${stats.avgBurn} kcal');
  sb.writeln('- **累计缺口**：${stats.totalDeficit} kcal（日均 ${stats.avgDeficit} kcal，理论减脂约 ${stats.estimatedFatLossKg.toStringAsFixed(2)} kg）');
  sb.writeln('- **营养宏量**：蛋白质 ${stats.avgProtein}g (${stats.proteinPercent}%) · 碳水 ${stats.avgCarbs}g (${stats.carbsPercent}%) · 脂肪 ${stats.avgFat}g (${stats.fatPercent}%)');
  sb.writeln('- **执行完成**：打卡率 ${stats.taskComplianceRate}% · 运动 ${stats.exerciseDays} 天（消耗 ${stats.totalExerciseBurn} kcal）\n');

  sb.writeln('---');
  sb.writeln('## 🤖 AI 营养师复盘与指导');
  if (headline.isNotEmpty) {
    sb.writeln('### 🌟 $headline\n');
  }
  if (review.isNotEmpty) {
    sb.writeln('### 📋 本周点评\n$review\n');
  }
  if (suggestions.isNotEmpty) {
    sb.writeln('### 🎯 未来一周减脂建议');
    for (var i = 0; i < suggestions.length; i++) {
      sb.writeln('${i + 1}. ${suggestions[i]}');
    }
    sb.writeln();
  }
  if (encouragement.isNotEmpty) {
    sb.writeln('### 💡 教练寄语\n> $encouragement\n');
  }

  sb.writeln('---\n*由「知轻」减脂助手生成 · 把日子过轻一点*');
  return sb.toString();
}

/// 减脂科普贴士列表（在途异步等待时轮播展示，增添等待价值）
const List<String> kFatLossTips = [
  '减脂期每周减重 0.5%~1%（约 0.3~0.8kg）是最不容易反弹且保护肌肉的理想速度。',
  '每天吃够体重的 1.2~1.6 倍克数蛋白质（如 60kg 人群吃 75~95g），能大幅提升饱腹感并减少掉肌肉。',
  '短时间体重波动 1~2 斤通常是水分、钠盐滞留或肠道残留，并不等于长了脂肪，不要焦虑。',
  '家常小炒通常会有 20%~30% 的油脂留在盘底，不喝菜汤、不泡饭就能轻松省下 100~200 大卡。',
  '睡眠不足会导致饥饿素上升、瘦素下降，睡够 7~8 小时是减脂天然的加速器。',
  '高碳水大餐后的体重暴涨多半是糖原与水分绑定（1g 糖原带 3~4g 水），正常饮食 2~3 天即可回落。',
  '用空气炸锅或吸油纸逼出 5g 油脂，就能直接扣减约 45 kcal 热量与 5g 脂肪。',
  '细嚼慢咽能给大脑饱腹中枢 15~20 分钟反应时间，自然减少 10%~15% 的过量进食。',
  '平台期并不代表减脂停滞，身体在重新适应新的体重平衡点，坚持 1~2 周往往会迎来突破。',
  '日常多走动、爬楼梯等非运动活动（NEAT）占总消耗的比例，往往远超你刻意跑步的那 30 分钟。',
  '偶尔一次聚餐放纵并不会摧毁你的减脂成果，7700 kcal 缺口才对应 1kg 纯脂肪，放平心态最重要。',
  '多喝水能促进代谢废物的排出，餐前喝 300ml 水还能有效平抑正餐的暴食冲动。',
];
