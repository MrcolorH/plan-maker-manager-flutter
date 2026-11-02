/// 当日实际运动详情页（对标 DayMealDetailPage）
/// 核心主体：运动项目与消耗拆解表格（做了啥、时长/运动量、消耗热量）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../models/records.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_utils.dart';
import '../../widgets/ai_config_sheet.dart';
import '../../widgets/convert_to_plan_sheet.dart';
import '../../widgets/exercise_breakdown_table.dart';
import '../item/item_detail_page.dart';

class DayExerciseDetailPage extends StatefulWidget {
  final String date;
  final DayEntry entry;
  final VoidCallback? onOpenEdit; // 外部可传入打开编辑弹窗的回调

  const DayExerciseDetailPage({
    super.key,
    required this.date,
    required this.entry,
    this.onOpenEdit,
  });

  @override
  State<DayExerciseDetailPage> createState() => _DayExerciseDetailPageState();
}

class _DayExerciseDetailPageState extends State<DayExerciseDetailPage> {
  bool _aiLoading = false;

  ExerciseItem? _findPlanExercise(PlanData plan, String planItemId) {
    if (planItemId.isEmpty) return null;
    for (final e in plan.exercises) {
      if (e.id == planItemId) return e;
    }
    return null;
  }

  /// AI 拆解与估算（仅在缺乏拆解数据时提供按需触发）
  Future<void> _triggerAiEstimate(DayEntry curEntry) async {
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 拆解运动与测算消耗需要你自己的 API Key，配置后立即继续。',
    );
    if (!ok || !mounted) return;

    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    final records = context.read<RecordProvider>();
    final ob = context.read<OnboardingProvider>();
    final p = ob.state.profile;
    final wd = weightForDate(records.store, widget.date);

    setState(() => _aiLoading = true);
    try {
      final desc = curEntry.note.isNotEmpty
          ? '${curEntry.content}（备注：${curEntry.note}）'
          : curEntry.content;
      final r = await AiService.instance.estimateBurn(
        settings.ai,
        desc,
        weight: wd ?? p.weight,
        gender: p.complete ? p.gender : null,
        age: p.complete ? p.age : null,
        height: p.complete ? p.height : null,
        onUsage: usage.addUsage,
      );
      if (!mounted) return;

      final cal = r['calories'] as int?;
      final detail = r['detail'] as String?;
      final items = r['items'] as List<FoodBreakdownItem>?;

      final updated = DayEntry(
        id: curEntry.id,
        kind: curEntry.kind,
        slot: curEntry.slot,
        time: curEntry.time,
        content: curEntry.content,
        calories: cal ?? curEntry.calories,
        protein: curEntry.protein,
        carbs: curEntry.carbs,
        fat: curEntry.fat,
        note: curEntry.note,
        source: curEntry.source,
        planItemId: curEntry.planItemId,
        detached: curEntry.detached,
        caloriesDirty: curEntry.caloriesDirty,
        detail: detail,
        items: items,
      );

      await records.updateDayEntry(widget.date, updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已完成运动拆解与消耗测算')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  /// 恢复为原计划模板
  Future<void> _restoreToPlan(ExerciseItem planEx, DayEntry curEntry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复计划运动？'),
        content: Text('将放弃今日修改，恢复为原计划的「${planEx.name}」及消耗。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认恢复', style: TextStyle(color: AppColors.orange)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final updated = DayEntry(
      id: curEntry.id,
      kind: curEntry.kind,
      slot: curEntry.slot,
      time: planEx.time.isNotEmpty ? planEx.time : curEntry.time,
      content: planEx.name,
      calories: planEx.caloriesBurned,
      protein: null,
      carbs: null,
      fat: null,
      note: '',
      source: 'plan',
      planItemId: planEx.id,
      detached: false,
      caloriesDirty: false,
      detail: null,
      items: null,
    );

    await context.read<RecordProvider>().updateDayEntry(widget.date, updated);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已恢复为计划内容：「${planEx.name}」')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = context.watch<RecordProvider>();
    final plan = context.watch<PlanProvider>().plan;

    // 从 Provider 中获取最新的快照条目
    final entries = records.store.dayEntries[widget.date] ?? const [];
    final curEntryList = entries.where((e) => e.id == widget.entry.id).toList();
    final curEntry = curEntryList.isNotEmpty ? curEntryList.first : widget.entry;

    final isChecked = records.isEntryChecked(widget.date, curEntry);
    final isTemp = !curEntry.isPlan;
    final planEx = _findPlanExercise(plan, curEntry.planItemId);

    // 解析明细表格列表
    List<FoodBreakdownItem> tableItems = curEntry.items ?? [];
    if (tableItems.isEmpty && curEntry.detail != null && curEntry.detail!.isNotEmpty) {
      tableItems = AiService.parseBreakdownFromText(curEntry.detail);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('运动详情'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.onOpenEdit != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenEdit!();
              },
              icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.orange),
              label: const Text(
                '修改记录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.orange,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 1. 顶部基础概览卡片
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Tag(
                      isTemp ? '临时练' : '运动',
                      color: isTemp ? 'orange' : 'green',
                    ),
                    const SizedBox(width: 6),
                    Text(
                      curEntry.time,
                      style: const TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w500),
                    ),
                    if (curEntry.detached && curEntry.isPlan) ...[
                      const SizedBox(width: 6),
                      const Tag('实际运动记录', color: 'orange'),
                    ],
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isChecked ? AppColors.primaryBg : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 14,
                            color: isChecked ? AppColors.primary : AppColors.textSub,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isChecked ? '已练完' : '未打卡',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isChecked ? AppColors.primary : AppColors.textSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  curEntry.content.isNotEmpty ? curEntry.content : '未命名运动',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                // 消耗总值
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      curEntry.calories != null ? '-${curEntry.calories}' : '--',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('kcal', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. 核心主体：运动项目与消耗拆解表格
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded, size: 18, color: AppColors.orange),
              const SizedBox(width: 6),
              const Text(
                '运动项目与消耗拆解',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
              const Spacer(),
              if (tableItems.isEmpty)
                TextButton.icon(
                  onPressed: _aiLoading ? null : () => _triggerAiEstimate(curEntry),
                  icon: _aiLoading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('✨', style: TextStyle(fontSize: 12)),
                  label: const Text('AI 拆解测算', style: TextStyle(fontSize: 12, color: AppColors.orange)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (tableItems.isNotEmpty) ...[
            ExerciseBreakdownTable(
              items: tableItems,
              totalCalories: curEntry.calories,
            ),
          ] else ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          curEntry.content,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        curEntry.calories != null ? '-${curEntry.calories} kcal' : '未估算',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '该记录暂无拆解分项明细。你可以点击右上角「AI 拆解测算」智能拆分运动项目、时长与分项消耗。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.4),
                  ),
                ],
              ),
            ),
          ],

          // 3. 备注卡片
          if (curEntry.note.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionTitle('运动备注'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 16, color: AppColors.textSub),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      curEntry.note,
                      style: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 4. 原计划对比与恢复（仅当来源于计划且已脱钩时显示）
          if (curEntry.isPlan && curEntry.detached && planEx != null) ...[
            const SizedBox(height: 16),
            const SectionTitle('原定计划参照'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '原计划：${planEx.name}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        planEx.caloriesBurned > 0 ? '-${planEx.caloriesBurned} kcal' : '自由练',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(AppRoutes.fade<void>(
                            ItemDetailPage(type: 'exercise', itemId: planEx.id),
                          ));
                        },
                        child: const Text('查看原计划运动详情', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _restoreToPlan(planEx, curEntry),
                        icon: const Icon(Icons.restore, size: 14),
                        label: const Text('恢复计划', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.orange,
                          side: const BorderSide(color: AppColors.orange),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // 5. 底部快捷操作
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await records.toggleEntryCheck(widget.date, curEntry);
                  },
                  icon: Icon(isChecked ? Icons.close : Icons.check, size: 18),
                  label: Text(isChecked ? '取消打卡' : '标记已练完'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isChecked ? Colors.white : AppColors.orange,
                    foregroundColor: isChecked ? AppColors.text : Colors.white,
                    side: isChecked ? const BorderSide(color: AppColors.chartGray) : null,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              if (isTemp && curEntry.content.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        builder: (ctx) => ConvertToPlanSheet(
                          date: widget.date,
                          entry: curEntry,
                        ),
                      );
                    },
                    icon: const Icon(Icons.event_repeat_rounded, size: 18),
                    label: const Text('设为日常计划'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
