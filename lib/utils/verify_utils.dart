/// 今日校验工具库：总结生成、提示词拼装、第三方 AI 返回结果解析与多级匹配
library;

import '../models/records.dart';
import '../services/ai_service.dart';
import '../utils/calorie_utils.dart';
import '../utils/date_utils.dart';

/// 纠偏项（单条修正数据）
class CorrectionItem {
  final String content; // 对应的原始输入内容
  final String status; // "准确" | "偏差"
  final String issue; // 问题描述或分析
  final int? calories; // 修正后热量 (kcal)
  final int? protein; // 修正后蛋白质 (g)
  final int? carbs; // 修正后碳水 (g)
  final int? fat; // 修正后脂肪 (g)

  // 匹配成功的条目引用（若匹配成功）
  final DayEntry? matchedEntry;

  CorrectionItem({
    required this.content,
    this.status = '准确',
    this.issue = '',
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.matchedEntry,
  });

  bool get isDifferent {
    if (matchedEntry == null) return false;
    // 核心准则：若判定为「准确」，则该条目属于合格记录，绝非偏差项，避免大模型数值微漂被误判为偏差
    if (status == '准确') return false;
    final calDiff = calories != null && calories != matchedEntry!.calories;
    final pDiff = protein != null && protein != matchedEntry!.protein;
    final cDiff = carbs != null && carbs != matchedEntry!.carbs;
    final fDiff = fat != null && fat != matchedEntry!.fat;
    return calDiff || pDiff || cDiff || fDiff;
  }

  CorrectionItem copyWithMatched(DayEntry entry) {
    return CorrectionItem(
      content: content,
      status: status,
      issue: issue,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      matchedEntry: entry,
    );
  }
}

/// 纠偏结果集合
class CorrectionResult {
  final String overall; // "准确" | "存在偏差"
  final String summary; // 整体结论总结
  final List<CorrectionItem> items; // 逐项明细

  CorrectionResult({
    required this.overall,
    required this.summary,
    required this.items,
  });
}

class VerifyUtils {
  VerifyUtils._();

  /// 判定某条目是否属于今日已实际执行并计入统计的事实条目：
  /// - 预设计划项（isPlan）：用户可能未执行或换别的内容，未打卡坚决不计入今日统计；
  /// - 计划外正餐（早中晚）：必须有内容且已完成打卡；
  /// - 临时加餐与临时运动：吃了/练了才录入，天然恒为已打卡事实，有实质内容即计入。
  static bool isEffectiveEntry(DayEntry e, bool isChecked) {
    if (e.isPlan) {
      return isChecked;
    }
    if (e.kind == 'meal' && e.slot != 'snack') {
      return isChecked && e.content.trim().isNotEmpty;
    }
    // 加餐与临时运动：吃了才录入，不存在未打卡加餐
    return e.content.trim().isNotEmpty;
  }

  /// 生成人类可读的今日全量摄入与消耗总结文本（仅包含已实际打卡或执行的项目）
  static String generateSummaryText({
    required String date,
    required List<DayEntry> entries,
    bool Function(DayEntry)? isChecked,
    DailySummary? dailySummary,
  }) {
    final sb = StringBuffer();
    sb.writeln('📋 今日饮食与运动记录（$date，${dateCn(date)}）');
    sb.writeln('【系统提示：所有条目的估算热量、拆解明细分项累加与全天汇总，均由程序代码精确求和，数据严格一致且不存在数学累加错误】');
    sb.writeln();

    final targetEntries = isChecked != null
        ? entries.where((e) => isEffectiveEntry(e, isChecked(e))).toList()
        : entries;

    final meals = targetEntries.where((e) => e.kind == 'meal').toList();
    final exercises = targetEntries.where((e) => e.kind == 'exercise').toList();

    sb.writeln('═══ 🍽️ 摄入条目 ═══');
    if (meals.isEmpty) {
      sb.writeln('（今日暂无餐食摄入记录）');
    } else {
      for (final m in meals) {
        final slotLabel = _slotCn(m.slot);
        final timeLabel = m.time.isNotEmpty ? ' ${m.time}' : '';
        sb.writeln('[$slotLabel$timeLabel] 原始输入：「${m.content.isEmpty ? '空白' : m.content}」');

        final calStr = m.calories != null ? '${m.calories} kcal' : '待补录';
        final p = m.protein != null ? '${m.protein}g' : '-';
        final c = m.carbs != null ? '${m.carbs}g' : '-';
        final f = m.fat != null ? '${m.fat}g' : '-';
        sb.writeln('  → 估算数据：$calStr | 蛋白 $p | 碳水 $c | 脂肪 $f');

        if (m.items != null && m.items!.isNotEmpty) {
          final itemsDesc = m.items!
              .map((it) => '${it.name}${it.portion.isNotEmpty ? "(${it.portion})" : ""}≈${it.calories}kcal')
              .join(', ');
          final sumItems = m.items!.fold<int>(0, (acc, it) => acc + it.calories);
          final sumNote = (m.calories != null && sumItems == m.calories)
              ? '（分项合计 $sumItems kcal，与条目估算一致）'
              : '';
          sb.writeln('  → 拆解明细：$itemsDesc$sumNote');
        } else if (m.detail != null && m.detail!.trim().isNotEmpty) {
          sb.writeln('  → 拆解描述：${m.detail!.trim()}');
        }
        if (m.note.trim().isNotEmpty) {
          sb.writeln('  → 用户备注：${m.note.trim()}');
        }
        sb.writeln();
      }
    }

    sb.writeln('═══ 🏃 运动消耗 ═══');
    if (exercises.isEmpty) {
      sb.writeln('（今日暂无运动记录）');
    } else {
      for (final ex in exercises) {
        final timeLabel = ex.time.isNotEmpty ? ' ${ex.time}' : '';
        sb.writeln('[运动$timeLabel] 原始输入：「${ex.content.isEmpty ? '空白' : ex.content}」');
        final calStr = ex.calories != null ? '${ex.calories} kcal' : '待补录';
        sb.writeln('  → 估算消耗：$calStr');
        if (ex.detail != null && ex.detail!.trim().isNotEmpty) {
          sb.writeln('  → 估算说明：${ex.detail!.trim()}');
        }
        if (ex.note.trim().isNotEmpty) {
          sb.writeln('  → 用户备注：${ex.note.trim()}');
        }
        sb.writeln();
      }
    }

    if (dailySummary != null) {
      sb.writeln('═══ 📊 今日全天汇总 ═══');
      sb.writeln('已摄入热量：${dailySummary.intake.round()} kcal '
          '(蛋白质 ${dailySummary.intakeProtein}g | 碳水 ${dailySummary.intakeCarbs}g | 脂肪 ${dailySummary.intakeFat}g)');
      sb.writeln('运动总消耗：+${dailySummary.exerciseBurn.round()} kcal');
      sb.writeln('基础消耗(TDEE)：${dailySummary.baseBurn} kcal');
      final sign = dailySummary.deficit > 0 ? '+' : '';
      sb.writeln('今日热量缺口：$sign${dailySummary.deficit.round()} kcal');
    }

    return sb.toString().trim();
  }

  static String _slotCn(String slot) {
    switch (slot) {
      case 'breakfast':
        return '早餐';
      case 'lunch':
        return '午餐';
      case 'dinner':
        return '晚餐';
      case 'snack':
        return '加餐';
      default:
        return '餐食';
    }
  }

  /// 拼装发送给第三方 AI 的完整校验提示词（供手动复制到外部大模型时使用）
  static String buildVerifyPrompt(String summaryText) {
    return '''
以下是我今日在减脂App中记录的饮食摄入与运动消耗清单（包含我的原始输入和系统估算/拆解结果）：

$summaryText

---
$kDailyVerifySys
'''.trim();
  }

  /// 从用户粘贴的第三方 AI 回复文本中提取并解析 CorrectionResult
  /// 包含多级匹配逻辑：1. 精确匹配 -> 2. 归一化匹配 -> 3. 包含匹配 -> 4. 顺序兜底匹配
  static CorrectionResult? parseCorrectionResult(
    String rawText,
    List<DayEntry> entries,
  ) {
    if (rawText.trim().isEmpty) return null;

    final obj = extractJsonObj(rawText);
    if (obj == null) return null;

    final rawOverall = obj['overall'] is String ? (obj['overall'] as String).trim() : '准确';
    final isOverallAccurate = rawOverall == '准确' ||
        (rawOverall.contains('准确') && !rawOverall.contains('偏差') && !rawOverall.contains('不'));
    final overall = isOverallAccurate ? '准确' : '存在偏差';
    final summary = obj['summary'] is String ? (obj['summary'] as String) : '';
    final rawItems = obj['items'];

    if (rawItems is! List) {
      return CorrectionResult(
        overall: overall,
        summary: summary,
        items: const [],
      );
    }

    final parsedItems = <CorrectionItem>[];
    for (final it in rawItems) {
      if (it is! Map) continue;
      final content = it['content']?.toString() ?? '';
      final rawStatus = it['status']?.toString().trim() ?? '准确';
      final isItemAccurate = rawStatus == '准确' ||
          (rawStatus.contains('准确') && !rawStatus.contains('偏差') && !rawStatus.contains('不'));
      final status = isItemAccurate ? '准确' : '偏差';
      final issue = it['issue']?.toString() ?? '';
      final cal = num.tryParse('${it['corrected_calories']}')?.round();
      final p = num.tryParse('${it['corrected_protein']}')?.round();
      final c = num.tryParse('${it['corrected_carbs']}')?.round();
      final f = num.tryParse('${it['corrected_fat']}')?.round();

      parsedItems.add(CorrectionItem(
        content: content,
        status: status,
        issue: issue,
        calories: cal,
        protein: p,
        carbs: c,
        fat: f,
      ));
    }

    // 绑定匹配对应的 DayEntry
    final matchedItems = _bindEntries(parsedItems, entries);

    return CorrectionResult(
      overall: overall,
      summary: summary,
      items: matchedItems,
    );
  }

  /// 多级匹配算法
  static List<CorrectionItem> _bindEntries(
    List<CorrectionItem> items,
    List<DayEntry> entries,
  ) {
    final usedEntryIds = <String>{};
    final result = <CorrectionItem>[];

    // 1. 第一轮：精确匹配 content
    for (final it in items) {
      final targetContent = it.content.trim();
      DayEntry? matched;
      for (final e in entries) {
        if (!usedEntryIds.contains(e.id) && e.content.trim() == targetContent) {
          matched = e;
          break;
        }
      }
      if (matched != null) {
        usedEntryIds.add(matched.id);
        result.add(it.copyWithMatched(matched));
      } else {
        result.add(it);
      }
    }

    // 2. 第二轮：归一化匹配（去标点、空格、大小写）
    for (var i = 0; i < result.length; i++) {
      if (result[i].matchedEntry != null) continue;
      final normTarget = _normalize(result[i].content);
      if (normTarget.isEmpty) continue;

      DayEntry? matched;
      for (final e in entries) {
        if (!usedEntryIds.contains(e.id) && _normalize(e.content) == normTarget) {
          matched = e;
          break;
        }
      }
      if (matched != null) {
        usedEntryIds.add(matched.id);
        result[i] = result[i].copyWithMatched(matched);
      }
    }

    // 3. 第三轮：包含匹配
    for (var i = 0; i < result.length; i++) {
      if (result[i].matchedEntry != null) continue;
      final normTarget = _normalize(result[i].content);
      if (normTarget.isEmpty) continue;

      DayEntry? matched;
      for (final e in entries) {
        if (usedEntryIds.contains(e.id)) continue;
        final normEntry = _normalize(e.content);
        if (normEntry.isNotEmpty && (normTarget.contains(normEntry) || normEntry.contains(normTarget))) {
          matched = e;
          break;
        }
      }
      if (matched != null) {
        usedEntryIds.add(matched.id);
        result[i] = result[i].copyWithMatched(matched);
      }
    }

    // 4. 第四轮：顺序兜底匹配（若条目数量完全相等且未匹配上）
    if (result.length == entries.length) {
      for (var i = 0; i < result.length; i++) {
        if (result[i].matchedEntry == null) {
          final candidate = entries[i];
          if (!usedEntryIds.contains(candidate.id)) {
            usedEntryIds.add(candidate.id);
            result[i] = result[i].copyWithMatched(candidate);
          }
        }
      }
    }

    return result;
  }

  static String _normalize(String s) {
    return s.replaceAll(RegExp(r'[\s，,。\.！!？\?、：:;；\(\)（）"“”\x27]+'), '').toLowerCase();
  }
}
