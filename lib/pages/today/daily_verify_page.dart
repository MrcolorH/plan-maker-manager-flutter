/// 今日校验页面（全屏页）：
/// 1. 今日总结（固定高度文本滚动）：仅汇总今日实际完成打卡或实质执行的条目
/// 2. 复制问 AI：将总结与提示词合并复制到剪切板
/// 3. 纠偏输入框（多行文本框）+ 自动纠偏解析按钮
/// 4. 纠偏结果结构化清晰展示（整体结论 + 差异明细）
/// 5. 用户自主勾选需要采纳的修正条目（默认智能预选偏差项，支持自由增减）
/// 6. 确认应用纠偏（仅更新勾选的条目，绝不修改用户原始输入）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/records.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_utils.dart';
import '../../utils/date_utils.dart';
import '../../utils/verify_utils.dart';

class DailyVerifyPage extends StatefulWidget {
  final String date;

  const DailyVerifyPage({
    super.key,
    required this.date,
  });

  @override
  State<DailyVerifyPage> createState() => _DailyVerifyPageState();
}

class _DailyVerifyPageState extends State<DailyVerifyPage> {
  final TextEditingController _correctionCtrl = TextEditingController();
  final ScrollController _summaryScrollCtrl = ScrollController();
  CorrectionResult? _correctionResult;
  final Set<int> _selectedIndices = {}; // 用户当前勾选需要采纳修正的条目索引
  bool _isApplying = false;

  String get _dayName {
    final t = todayStr();
    if (widget.date == t) return '今日';
    final pa = parseDate(widget.date);
    final pb = parseDate(t);
    final diff = DateTime(pa.y, pa.m, pa.d).difference(DateTime(pb.y, pb.m, pb.d)).inDays;
    if (diff == -1) return '昨日';
    return dateCn(widget.date);
  }

  @override
  void dispose() {
    _correctionCtrl.dispose();
    _summaryScrollCtrl.dispose();
    super.dispose();
  }

  void _copyForAI(String summaryText) {
    final prompt = VerifyUtils.buildVerifyPrompt(summaryText);
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('已复制$_dayName记录与校验提示词！可直接粘贴给第三方 AI 咨询。'),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _runAutoCorrection(List<DayEntry> entries) {
    final text = _correctionCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先粘贴第三方 AI 的校验结果')),
      );
      return;
    }

    final result = VerifyUtils.parseCorrectionResult(text, entries);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未能从内容中解析出有效的校验 JSON，请确认是否完整复制了第三方 AI 的回复。'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _correctionResult = result;
      _selectedIndices.clear();
      // 智能默认预选：自动勾选所有成功匹配且存在数值差异/偏差的条目
      for (var i = 0; i < result.items.length; i++) {
        final it = result.items[i];
        if (it.matchedEntry != null && it.isDifferent) {
          _selectedIndices.add(i);
        }
      }
    });

    final matchedCount = result.items.where((e) => e.matchedEntry != null).length;
    final diffCount = result.items.where((e) => e.isDifferent).length;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '解析成功！已识别 $matchedCount 项（其中 $diffCount 项存在偏差，已默认勾选，您可自主调整）。',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _selectAll() {
    if (_correctionResult == null) return;
    setState(() {
      _selectedIndices.clear();
      for (var i = 0; i < _correctionResult!.items.length; i++) {
        if (_correctionResult!.items[i].matchedEntry != null) {
          _selectedIndices.add(i);
        }
      }
    });
  }

  void _selectOnlyDiff() {
    if (_correctionResult == null) return;
    setState(() {
      _selectedIndices.clear();
      for (var i = 0; i < _correctionResult!.items.length; i++) {
        final it = _correctionResult!.items[i];
        if (it.matchedEntry != null && it.isDifferent) {
          _selectedIndices.add(i);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIndices.clear();
    });
  }

  Future<void> _applyCorrection() async {
    if (_correctionResult == null) return;

    // 严格只采纳用户当前选中的条目
    final itemsToApply = <CorrectionItem>[];
    for (final idx in _selectedIndices) {
      if (idx >= 0 && idx < _correctionResult!.items.length) {
        final item = _correctionResult!.items[idx];
        if (item.matchedEntry != null) {
          itemsToApply.add(item);
        }
      }
    }

    if (itemsToApply.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未勾选任何条目，请在下方列表中勾选您想采纳修正的条目')),
      );
      return;
    }

    setState(() => _isApplying = true);
    try {
      final updatedCount = await context.read<RecordProvider>().batchUpdateEntryCalories(
            widget.date,
            itemsToApply,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✨ 已成功采纳并纠偏选中的 $updatedCount 条记录！打卡数据已更新。'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('纠偏保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    final records = context.watch<RecordProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final profile = context.watch<OnboardingProvider>().state.profile;

    final allEntries = records.store.dayEntries[widget.date] ?? const <DayEntry>[];
    // 核心口径：仅统计今日完成打卡/已实际执行的项目（预设计划项未打卡坚决不计入）
    final entries = allEntries
        .where((e) => VerifyUtils.isEffectiveEntry(e, records.isEntryChecked(widget.date, e)))
        .toList();
    final summary = dailySummary(plan, settings, records.store, widget.date, profile: profile);

    final summaryText = VerifyUtils.generateSummaryText(
      date: widget.date,
      entries: entries,
      dailySummary: summary,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('${_dayName == '今日' ? '今日' : (_dayName == '昨日' ? '昨日' : '热量')}校验 · ${widget.date}'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.text,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            // 1. 条目总结区（固定高度，文本可滚动）
            _buildSectionHeader(
              icon: Icons.article_outlined,
              title: '$_dayName条目总结',
              trailing: '仅包含已打卡/实际执行项目',
            ),
            const SizedBox(height: 8),
            _buildSummaryBox(summaryText, isEmpty: entries.isEmpty),
            const SizedBox(height: 10),

            // 2. 复制问 AI 按钮
            ElevatedButton.icon(
              onPressed: entries.isEmpty ? null : () => _copyForAI(summaryText),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('复制问 AI（带专业校验提示词）'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                '复制后直接发送给 ChatGPT、Claude 或 DeepSeek 等第三方 AI',
                style: TextStyle(fontSize: 11, color: AppColors.textSub),
              ),
            ),
            const SizedBox(height: 20),

            // 3. 纠偏输入框
            _buildSectionHeader(
              icon: Icons.edit_note_rounded,
              title: '纠偏结果回填',
              trailing: '粘贴 AI 返回的答案',
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              padding: const EdgeInsets.all(10),
              child: TextField(
                controller: _correctionCtrl,
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(fontSize: 13, height: 1.4, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: '将第三方 AI 评估后返回的答案全文粘贴在这里...\nApp 会自动解析结构，提取出哪些有偏差并让您自主勾选。',
                  hintStyle: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.4),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 4. 自动解析按钮
            OutlinedButton.icon(
              onPressed: entries.isEmpty ? null : () => _runAutoCorrection(entries),
              icon: const Text('✨', style: TextStyle(fontSize: 16)),
              label: const Text('智能解析评估结果'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.2),
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            // 5. 结构化纠偏与自主勾选列表
            if (_correctionResult != null) ...[
              const SizedBox(height: 20),
              _buildCorrectionResultView(_correctionResult!),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: (_isApplying || _selectedIndices.isEmpty) ? null : _applyCorrection,
                icon: _isApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _selectedIndices.isEmpty
                      ? '请在上方勾选需要修正的条目'
                      : '确认采纳选中的 ${_selectedIndices.length} 项纠偏（更新打卡数据）',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  '注：仅修正被勾选条目的热量与营养素估算值，严格保留您的原始输入文本不变',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub),
          ),
      ],
    );
  }

  /// 固定高度的文本滚动框
  Widget _buildSummaryBox(String content, {required bool isEmpty}) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_note_outlined, size: 36, color: AppColors.textSub),
                  const SizedBox(height: 8),
                  Text(
                    '$_dayName暂无已完成打卡的记录',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.date == todayStr()
                        ? '预设计划项未打卡执行前不计入今日统计。\n请先在「今日」主页打卡后，再来此处进行校验。'
                        : '预设计划项未打卡执行前不计入统计。\n请先在日历补录或打卡后，再来此处进行校验。',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.4),
                  ),
                ],
              ),
            )
          : Scrollbar(
              controller: _summaryScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _summaryScrollCtrl,
                child: SelectableText(
                  content,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.text,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
    );
  }

  /// 纠偏结果卡片（清晰结构化：整体结论 + 快捷勾选操作 + 条目自选对比）
  Widget _buildCorrectionResultView(CorrectionResult res) {
    final isOverallAccurate = res.overall.contains('准确') && !res.overall.contains('偏差') && !res.overall.contains('不');
    final overallColor = isOverallAccurate ? AppColors.primary : AppColors.orange;
    final diffCount = res.items.where((e) => e.isDifferent).length;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 整体结论横幅
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: overallColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: overallColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isOverallAccurate ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 20,
                  color: overallColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'AI 整体结论：',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text),
                          ),
                          Text(
                            res.overall,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: overallColor),
                          ),
                        ],
                      ),
                      if (res.summary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          res.summary,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. 自主选择提示与快捷工具栏
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '勾选需要采纳修正的条目：',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '已选 ${_selectedIndices.length}/${res.items.length} 项（其中 $diffCount 项建议修正）',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),
              // 快捷操作按钮
              Wrap(
                spacing: 6,
                children: [
                  _buildQuickAction('全选', _selectAll),
                  if (diffCount > 0) _buildQuickAction('仅选偏差', _selectOnlyDiff),
                  _buildQuickAction('清空', _clearSelection),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. 逐条对比卡片（带 Checkbox）
          ...List.generate(res.items.length, (index) {
            final item = res.items[index];
            final isSelected = _selectedIndices.contains(index);
            return _buildCorrectionItemTile(index, item, isSelected);
          }),
        ],
      ),
    );
  }

  Widget _buildQuickAction(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tagBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSub, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildCorrectionItemTile(int index, CorrectionItem item, bool isSelected) {
    final matched = item.matchedEntry;
    final isDiff = item.isDifferent;

    return InkWell(
      onTap: matched != null ? () => _toggleSelect(index) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.orange.withValues(alpha: 0.05) : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.orange.withValues(alpha: 0.6)
                : Colors.black.withValues(alpha: 0.05),
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 复选框
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: isSelected,
                  activeColor: AppColors.orange,
                  onChanged: matched != null ? (_) => _toggleSelect(index) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isDiff ? AppColors.orange : AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isDiff ? '有偏差/建议调整' : '估算准确',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.content,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (matched == null)
                        const Text(
                          '未匹配条目',
                          style: TextStyle(fontSize: 11, color: AppColors.danger),
                        ),
                    ],
                  ),
                  if (item.issue.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'AI诊断：${item.issue}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // 数值对比行
                  if (matched != null)
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _buildValDiff('热量', matched.calories, item.calories, 'kcal'),
                        if (matched.kind == 'meal') ...[
                          _buildValDiff('蛋白', matched.protein, item.protein, 'g'),
                          _buildValDiff('碳水', matched.carbs, item.carbs, 'g'),
                          _buildValDiff('脂肪', matched.fat, item.fat, 'g'),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValDiff(String label, int? oldVal, int? newVal, String unit) {
    final changed = newVal != null && newVal != oldVal;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
          TextSpan(
            text: oldVal != null ? '$oldVal' : '-',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSub,
              decoration: changed ? TextDecoration.lineThrough : null,
            ),
          ),
          if (changed) ...[
            const TextSpan(text: ' → ', style: TextStyle(fontSize: 11, color: AppColors.orange, fontWeight: FontWeight.bold)),
            TextSpan(
              text: '$newVal$unit',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.orange,
              ),
            ),
          ] else
            TextSpan(text: unit, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
        ],
      ),
    );
  }
}
