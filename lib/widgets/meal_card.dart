/// 餐食卡片（对应 meal-card.vue）
/// 左栏 emoji+橙色时间；中栏类型 tag+名称+子行；右栏操作（✎ 调整 / ✕ 删除 / ✓ 打卡）
library;

import 'package:flutter/material.dart';

import '../models/plan_data.dart';
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
  final MealItem meal;
  final bool checked;
  final bool isTemp; // 临时加餐（非计划餐）
  final bool focused; // 通知定位高亮
  final int? actualCal; // 当日实际摄入覆盖
  final String actualNote;
  final VoidCallback? onTap; // 卡片空白 → 详情
  final VoidCallback? onCheck; // 打卡
  final VoidCallback? onAdjust; // ✎
  final VoidCallback? onDelete; // ✕（临时项）

  const MealCard({
    super.key,
    required this.meal,
    required this.checked,
    this.isTemp = false,
    this.focused = false,
    this.actualCal,
    this.actualNote = '',
    this.onTap,
    this.onCheck,
    this.onAdjust,
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
              // 左栏：emoji + 橙色时间
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    Text(_typeEmoji[meal.type] ?? '🍽',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(meal.time,
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
                          Tag(kTypeCn[meal.type] ?? meal.type, color: 'green'),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            meal.name,
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
                    const SizedBox(width: 6),
                  ] else ...[
                    _iconBtn(Icons.edit_outlined,
                        actualCal != null ? AppColors.primary : AppColors.textSub,
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
    if (isTemp) {
      return Row(
        children: [
          Text('${meal.calories ?? 0} kcal',
              style: const TextStyle(fontSize: 12, color: AppColors.orange)),
          if (checked) ...[
            const SizedBox(width: 6),
            const Tag('已计入', color: 'orange'),
          ],
        ],
      );
    }
    // 计划餐
    final free = meal.calories == null;
    if (actualCal != null) {
      // 实际覆盖（老版：橙色实际值 + 灰色删除线计划值）
      return Row(
        children: [
          Text('实际 $actualCal kcal',
              style: const TextStyle(fontSize: 12, color: AppColors.orange)),
          if (meal.calories != null) ...[
            const SizedBox(width: 4),
            Text('计划 ${meal.calories}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub, decoration: TextDecoration.lineThrough)),
          ],
          if (actualNote.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(actualNote,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          ],
        ],
      );
    }
    if (free) {
      return const Row(
        children: [
          Tag('自由餐', color: 'default'),
          Text('打卡后补录实际热量', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
        ],
      );
    }
    return Row(
      children: [
        Text('${meal.calories} kcal',
            style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        if (meal.note.isNotEmpty) ...[
          const SizedBox(width: 4),
          Expanded(
            child: Text(meal.note,
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
