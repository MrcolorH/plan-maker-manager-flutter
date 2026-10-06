/// 热量缺口汇总卡（对应 calorie-summary.vue）
/// 老版布局：左「今日热量缺口」标签 + 右侧大数字/kcal + 档位提示语；下方四格明细
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/calorie_utils.dart';

class CalorieSummary extends StatelessWidget {
  final int baseBurn;
  final int exerciseBurn;
  final int intake;
  final int plannedIntake;
  final num deficit;
  final int intakeProtein;
  final int intakeCarbs;
  final int intakeFat;
  final int plannedProtein;
  final int plannedCarbs;
  final int plannedFat;
  final VoidCallback? onVerify;

  const CalorieSummary({
    super.key,
    required this.baseBurn,
    required this.exerciseBurn,
    required this.intake,
    required this.plannedIntake,
    required this.deficit,
    this.intakeProtein = 0,
    this.intakeCarbs = 0,
    this.intakeFat = 0,
    this.plannedProtein = 0,
    this.plannedCarbs = 0,
    this.plannedFat = 0,
    this.onVerify,
  });

  Color get _levelColor {
    final lv = deficitLevel(deficit);
    switch (lv) {
      case 'danger':
        return AppColors.danger;
      case 'warning':
        return AppColors.orange;
      default:
        return AppColors.primary;
    }
  }

  /// 档位提示语（老版仅异常档位显示，健康档不显示）
  String? get _hint {
    final lv = deficitLevel(deficit);
    if (lv == 'danger') return '超标啦，管住嘴迈开腿';
    if (lv == 'warning') {
      return deficit <= 300 ? '缺口偏小，减脂效率打折' : '缺口较大，注意别绷过头';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor;
    final hint = _hint;
    final sign = deficit > 0 ? '+' : '';
    final hasMacros = intakeProtein > 0 || intakeCarbs > 0 || intakeFat > 0 || plannedProtein > 0;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text('今日热量缺口', style: TextStyle(fontSize: 14, color: AppColors.textSub)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$sign${deficit.round()}',
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.bold,
                            color: color,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text('kcal', style: TextStyle(fontSize: 13, color: color)),
                        ),
                      ],
                    ),
                    if (hint != null)
                      Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.orange)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: const Color(0xFFEFEFEA)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _item('基础消耗\n（不含运动）', '$baseBurn', AppColors.text),
              _item('运动消耗', '+$exerciseBurn', AppColors.primary),
              _item('已摄入\n（增加餐）', '$intake', AppColors.orange),
              _item('计划摄入\n目标', '$plannedIntake', AppColors.text),
            ],
          ),
          if (hasMacros) ...[
            const SizedBox(height: 12),
            Container(height: 0.5, color: const Color(0xFFEFEFEA)),
            const SizedBox(height: 10),
            Row(
              children: [
                _macroBadge('蛋白质', intakeProtein, plannedProtein, const Color(0xFF4CAF50)),
                const SizedBox(width: 8),
                _macroBadge('碳水', intakeCarbs, plannedCarbs, const Color(0xFF2196F3)),
                const SizedBox(width: 8),
                _macroBadge('脂肪', intakeFat, plannedFat, const Color(0xFFFF9800)),
              ],
            ),
          ],
          if (onVerify != null) ...[
            const SizedBox(height: 10),
            Container(height: 0.5, color: const Color(0xFFEFEFEA)),
            const SizedBox(height: 8),
            InkWell(
              onTap: onVerify,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fact_check_outlined, size: 14, color: context.primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      '今日校验（AI 识别与热量二次核验）',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: context.primaryColor),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _macroBadge(String name, int current, int planned, Color accent) {
    final showPlan = planned > 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: TextStyle(fontSize: 10.5, color: accent, fontWeight: FontWeight.w600)),
                Flexible(
                  child: Text(
                    showPlan ? '$current/${planned}g' : '${current}g',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (showPlan) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: planned > 0 ? (current / planned).clamp(0.0, 1.0) : 0,
                  backgroundColor: accent.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                  minHeight: 3.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 3),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppColors.textSub, height: 1.25)),
        ],
      ),
    );
  }
}
