/// 计划项详情页（对应 item/detail.vue）
/// 餐食：食材清单 / 做法步骤；运动：训练环节；提醒开关；删除该项
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../providers/plan_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/plan_utils.dart';
import '../../widgets/plan_item_edit.dart';

class ItemDetailPage extends StatelessWidget {
  final String type; // meal | exercise
  final String itemId;
  const ItemDetailPage({super.key, required this.type, required this.itemId});

  /// 「编辑」：弹完整编辑器（餐食含食材/做法，运动含训练内容），保存后整项落盘
  Future<void> _edit(BuildContext context) async {
    final planP = context.read<PlanProvider>();
    if (type == 'meal') {
      final list = planP.plan.meals.where((m) => m.id == itemId).toList();
      if (list.isEmpty) return;
      final r = await showPlanItemEditor(context: context, meal: list.first);
      if (r is MealItem) await planP.replaceItem('meal', r);
    } else {
      final list = planP.plan.exercises.where((e) => e.id == itemId).toList();
      if (list.isEmpty) return;
      final r = await showPlanItemEditor(context: context, exercise: list.first);
      if (r is ExerciseItem) await planP.replaceItem('exercise', r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    MealItem? meal;
    ExerciseItem? exercise;
    if (type == 'meal') {
      final list = plan.meals.where((m) => m.id == itemId).toList();
      if (list.isNotEmpty) meal = list.first;
    } else {
      final list = plan.exercises.where((e) => e.id == itemId).toList();
      if (list.isNotEmpty) exercise = list.first;
    }
    if (meal == null && exercise == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('详情')),
        backgroundColor: AppColors.bg,
        body: const Center(
          child: Text('该项不存在或已被删除', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(meal?.name ?? exercise!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => _edit(context),
            child: const Text('编辑',
                style: TextStyle(fontSize: 14, color: AppColors.primary, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: meal != null
            ? _mealSections(context, meal)
            : _exerciseSections(context, exercise!),
      ),
    );
  }

  // ---------- 餐食 ----------

  List<Widget> _mealSections(BuildContext context, MealItem m) {
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Tag(kTypeCn[m.type] ?? m.type, color: 'green'),
                Text(m.time, style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                const Spacer(),
                if (m.calories != null)
                  Text('${m.calories} kcal',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.orange))
                else
                  const Text('自由餐（热量不固定）',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              ],
            ),
            const SizedBox(height: 8),
            if (m.dates.isNotEmpty)
              _infoRow('执行日期', datesCn(m.dates, 3))
            else
              _infoRow(
                '执行星期',
                daysCn(m.days) == '每天' ? '每天' : '每周${daysCn(m.days)}',
                onTap: () => _edit(context),
              ),
            if (m.startDate.isNotEmpty || m.endDate.isNotEmpty)
              _infoRow('阶段范围', '${m.startDate} ~ ${m.endDate}'),
            if (m.note.isNotEmpty) _infoRow('备注', m.note),
          ],
        ),
      ),
      _reminderRow(context, 'meal', m.id, m.reminder),
      if (m.details.isNotEmpty) ...[
        const SectionTitle('食材清单'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: m.details
                .map((d) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(d.item, style: const TextStyle(fontSize: 13))),
                          Text(d.amount, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
      if (m.steps.isNotEmpty) ...[
        const SectionTitle('做法步骤'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: m.steps.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(top: 1, right: 8),
                      decoration: const BoxDecoration(color: AppColors.primaryBg, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('${e.key + 1}',
                          style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13, height: 1.5))),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _deleteBtn(context, 'meal', m.id),
    ];
  }

  // ---------- 运动 ----------

  List<Widget> _exerciseSections(BuildContext context, ExerciseItem e) {
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Tag('运动', color: 'green'),
                Text(e.time, style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                const Spacer(),
                Text('${e.duration} 分钟',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('≈-${e.caloriesBurned} kcal',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
              ],
            ),
            const SizedBox(height: 8),
            if (e.dates.isNotEmpty)
              _infoRow('执行日期', datesCn(e.dates, 3))
            else
              _infoRow(
                '执行星期',
                daysCn(e.days) == '每天' ? '每天' : '每周${daysCn(e.days)}',
                onTap: () => _edit(context),
              ),
            if (e.startDate.isNotEmpty || e.endDate.isNotEmpty)
              _infoRow('阶段范围', '${e.startDate} ~ ${e.endDate}'),
            if (e.note.isNotEmpty) _infoRow('注意事项', e.note),
          ],
        ),
      ),
      _reminderRow(context, 'exercise', e.id, e.reminder),
      if (e.content.isNotEmpty) ...[
        const SectionTitle('训练内容'),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            children: e.content.map((c) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.item, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          if (c.detail.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(c.detail, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${c.minutes} 分钟', style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _deleteBtn(context, 'exercise', e.id),
    ];
  }

  Widget _infoRow(String label, String value, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: row,
      );
    }
    return row;
  }

  Widget _reminderRow(BuildContext context, String type, String id, bool reminder) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          const Text('⏰', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          const Expanded(child: Text('到点提醒', style: TextStyle(fontSize: 14))),
          Switch(
            value: reminder,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => context.read<PlanProvider>().updateItem(type, id, {'reminder': v}),
          ),
        ],
      ),
    );
  }

  Widget _deleteBtn(BuildContext context, String type, String id) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DangerButton('从计划中删除此项', onPressed: () => _confirmDelete(context, type, id)),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String type, String id) async {
    final planP = context.read<PlanProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('从计划中删除这一项？历史打卡记录会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await planP.removeItem(type, id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
