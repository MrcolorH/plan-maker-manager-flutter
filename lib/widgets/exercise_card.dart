/// 运动卡片（对应 exercise-card.vue）
/// 左栏 🏃+橙色时间；中栏「运动」tag+名称+时长/消耗子行；右栏 ✓ / ✕
library;

import 'package:flutter/material.dart';

import '../models/plan_data.dart';
import '../theme/app_theme.dart';
import 'meal_card.dart';

class ExerciseCard extends StatelessWidget {
  final ExerciseItem exercise;
  final bool checked;
  final bool isTemp; // 临时运动
  final bool focused;
  final VoidCallback? onTap;
  final VoidCallback? onCheck;
  final VoidCallback? onDelete;

  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.checked,
    this.isTemp = false,
    this.focused = false,
    this.onTap,
    this.onCheck,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = checked
        ? AppColors.primaryBg
        : (isTemp ? const Color(0xFFFCF6EE) : Colors.white);
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
                    Text(exercise.time,
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
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            exercise.name,
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
                        Text('${exercise.duration} 分钟',
                            style: const TextStyle(fontSize: 12, color: AppColors.text)),
                        const SizedBox(width: 6),
                        Text('≈ -${exercise.caloriesBurned} kcal',
                            style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                        if (checked) ...[
                          const SizedBox(width: 6),
                          const Tag('已计入', color: 'orange'),
                        ],
                      ],
                    ),
                    if (exercise.note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(exercise.note,
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
                    const SizedBox(width: 8),
                  ],
                  CheckCircle(checked: checked, onTap: onCheck),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
