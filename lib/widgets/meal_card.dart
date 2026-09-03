/// 餐食卡片（F11 快照版，对应 meal-card.vue + 当日条目快照）
/// 左栏 emoji+橙色时间；中栏类型 tag(+「已改」)+食物内容 content+子行；右栏 ✎ 调整 / ✕ 删除（计划外）/ ✓ 打卡
library;

import 'package:flutter/material.dart';

import '../models/records.dart';
import '../theme/app_theme.dart';
import '../utils/plan_utils.dart';

const Map<String, String> _typeEmoji = {
  'breakfast': '🥣',
  'lunch': '🍚',
  'dinner': '🍽',
  'snack': '☕',
};

/// 打卡圆圈按钮（老版尺寸更大更醒目）
class CheckCircle extends StatelessWidget {
  final bool checked;
  final VoidCallback? onTap;
  final double size;
  const CheckCircle({super.key, required this.checked, this.onTap, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: checked ? AppColors.primary : Colors.white,
          border: Border.all(
            color: checked ? AppColors.primary : AppColors.chartGray,
            width: checked ? 0 : 1.4,
          ),
        ),
        child: checked
            ? Icon(Icons.check, size: size * 0.55, color: Colors.white)
            : const SizedBox(),
      ),
    );
  }
}

class MealCard extends StatelessWidget {
  final DayEntry entry;
  final int? planCalories; // 计划当前热量（未脱钩计划条目传值，供覆盖划线；其余传 null）
  final bool checked;
  final bool focused;
  final VoidCallback? onTap; // 卡片空白 → 详情
  final VoidCallback? onCheck; // 打卡（计划条目）
  final VoidCallback? onAdjust; // ✎
  final VoidCallback? onDelete; // ✕（计划外条目）

  const MealCard({
    super.key,
    required this.entry,
    this.planCalories,
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
              // 左栏：emoji + 橙色时间
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    Text(_typeEmoji[entry.slot] ?? '🍽',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(entry.time,
                        style: const TextStyle(fontSize: 11, color: AppColors.orange)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 中栏
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isTemp)
                          const Tag('今日加', color: 'orange')
                        else
                          Tag(kTypeCn[entry.slot] ?? entry.slot, color: 'green'),
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
                    _subRow(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 右栏操作
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isTemp) ...[
                    _iconBtn(Icons.close, AppColors.textSub, onDelete, 18),
                  ] else ...[
                    _iconBtn(Icons.edit_outlined,
                        entry.caloriesDirty || entry.detached ? AppColors.primary : AppColors.textSub,
                        onAdjust, 17),
                    const SizedBox(width: 8),
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

  Widget _subRow() {
    final cal = entry.calories;
    if (!entry.isPlan) {
      // 计划外加餐：即计缺口，展示热量
      return Row(
        children: [
          Text('${cal ?? 0} kcal',
              style: const TextStyle(fontSize: 12, color: AppColors.orange)),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(entry.note,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          ],
        ],
      );
    }
    if (cal == null) {
      // 待补录（自由餐 / 未测算）
      return Row(
        children: [
          const Tag('自由餐', color: 'default'),
          const Text('打卡后补录实际热量', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(entry.note,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          ],
        ],
      );
    }
    if (entry.detached) {
      // 已脱钩：只显示实际值 + 备注（无划线计划值，与计划无关）
      return Row(
        children: [
          Text('$cal kcal',
              style: const TextStyle(fontSize: 12, color: AppColors.orange)),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(entry.note,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          ],
        ],
      );
    }
    // 未脱钩：覆盖则显示实际 + 划线计划值；否则计划值 + 备注
    final dirty = entry.caloriesDirty && planCalories != null && planCalories != cal;
    if (dirty) {
      return Row(
        children: [
          Text('实际 $cal kcal',
              style: const TextStyle(fontSize: 12, color: AppColors.orange)),
          const SizedBox(width: 4),
          Text('计划 $planCalories',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSub, decoration: TextDecoration.lineThrough)),
          if (entry.note.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(entry.note,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          ],
        ],
      );
    }
    return Row(
      children: [
        Text('$cal kcal',
            style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        if (entry.note.isNotEmpty) ...[
          const SizedBox(width: 4),
          Expanded(
            child: Text(entry.note,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
          ),
        ],
      ],
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback? onTap, double size) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
