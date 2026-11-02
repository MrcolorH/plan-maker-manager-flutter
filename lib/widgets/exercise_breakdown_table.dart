/// 运动与消耗拆解表格组件（对标 FoodBreakdownTable）
/// 清晰展示：做了啥（运动项目）、时长/运动量、预估消耗
library;

import 'package:flutter/material.dart';

import '../models/records.dart';
import '../theme/app_theme.dart';

class ExerciseBreakdownTable extends StatelessWidget {
  final List<FoodBreakdownItem> items;
  final int? totalCalories;
  final bool compact; // 是否紧凑模式（用于编辑弹窗内的小卡片）
  final String? subtitle;

  const ExerciseBreakdownTable({
    super.key,
    required this.items,
    this.totalCalories,
    this.compact = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final sumCal = items.fold<int>(0, (sum, it) => sum + it.calories);
    final displayTotal = totalCalories ?? (items.isNotEmpty ? sumCal : null);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: compact ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(
          color: compact ? const Color(0xFFE5E7EB) : const Color(0xFFEEEEEE),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 表头
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: compact ? const Color(0xFFF3F4F6) : AppColors.bg,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(compact ? 9 : 11),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    '运动项目',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '时长 / 运动量',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    '预估消耗',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 数据行
          ...items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final isEven = idx % 2 == 0;
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 6 : 8,
              ),
              decoration: BoxDecoration(
                color: isEven ? Colors.transparent : (compact ? Colors.white : const Color(0xFFFAFAFA)),
                border: Border(
                  top: BorderSide(
                    color: compact ? const Color(0xFFF0F2F5) : const Color(0xFFF2F2F2),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      item.portion.isNotEmpty ? item.portion : '-',
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        color: AppColors.textSub,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '-${item.calories} kcal',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // 合计底行
          if (displayTotal != null)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 7 : 9,
              ),
              decoration: BoxDecoration(
                color: compact ? const Color(0xFFF3F4F6) : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(compact ? 9 : 11),
                ),
                border: Border(
                  top: BorderSide(
                    color: compact ? const Color(0xFFE5E7EB) : const Color(0xFFFED7AA),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    flex: 8,
                    child: Text(
                      '合计消耗',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '-$displayTotal kcal',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
