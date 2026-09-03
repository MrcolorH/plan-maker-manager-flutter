/// 运动卡片（F11 快照版，对应 exercise-card.vue + 当日条目快照）
/// 左栏 🏃+橙色时间；中栏「运动/临时练」tag(+「已改」)+运动内容 content+消耗子行；右栏 ✎ / ✕ / ✓
library;

import 'package:flutter/material.dart';

import '../models/records.dart';
import '../theme/app_theme.dart';
import 'meal_card.dart';

class ExerciseCard extends StatelessWidget {
  final DayEntry entry;
  final int? planBurn; // 关联计划项当前消耗（未脱钩计划条目传值，供覆盖划线；其余传 null）
  final bool checked;
  final bool focused;
  final VoidCallback? onTap;
  final VoidCallback? onCheck; // 打卡（计划条目）
  final VoidCallback? onAdjust; // ✎ 编辑（新增）
  final VoidCallback? onDelete; // ✕（计划外）

  const ExerciseCard({
    super.key,
    required this.entry,
    this.planBurn,
    required this.checked,
    this.focused = false,
    this.onTap,
    this.onCheck,
    this.onAdjust,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isTemp = !entry.isPlan;
    final Color bg = checked
        ? AppColors.primaryBg
        : (isTemp ? const Color(0xFFFCF6EE) : Colors.white);
    final cal = entry.calories ?? 0;
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: focused
            ? Border.all(color: AppColors.orange, width: 1.5)
            : (isTemp ? Border.all(color: const Color(0xFFF2DDBC)) : null),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左栏：🏃 + 橙色时间
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    const Text('🏃', style: TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(entry.time,
                        style: const TextStyle(fontSize: 11, color: AppColors.orange)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isTemp)
                          const Tag('临时练', color: 'orange')
                        else
                          const Tag('运动', color: 'green'),
                        if (entry.detached && entry.isPlan) ...[
                          const SizedBox(width: 4),
                          const Tag('已改', color: 'orange'),
                        ],
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (!entry.isPlan)
                          Text('≈ -$cal kcal',
                              style: const TextStyle(fontSize: 12, color: AppColors.primary))
                        else if (entry.detached)
                          Text('≈ -$cal kcal',
                              style: const TextStyle(fontSize: 12, color: AppColors.primary))
                        else if (entry.caloriesDirty && planBurn != null && planBurn != cal)
                          Flexible(
                            child: Text('实际 -$cal',
                                style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                          )
                        else
                          Text('≈ -$cal kcal',
                              style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                        if (entry.isPlan &&
                            entry.caloriesDirty &&
                            planBurn != null &&
                            planBurn != cal) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('计划 -$planBurn',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSub,
                                    decoration: TextDecoration.lineThrough)),
                          ),
                        ],
                        if (checked) ...[
                          const SizedBox(width: 6),
                          const Tag('已计入', color: 'orange'),
                        ],
                      ],
                    ),
                    if (entry.note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(entry.note,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isTemp) ...[
                    GestureDetector(
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.close, size: 18, color: AppColors.textSub),
                      ),
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: onAdjust,
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(Icons.edit_outlined, size: 17, color: AppColors.textSub),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CheckCircle(checked: checked, onTap: onCheck),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
