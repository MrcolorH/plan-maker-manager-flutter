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

  const CalorieSummary({
    super.key,
    required this.baseBurn,
    required this.exerciseBurn,
    required this.intake,
    required this.plannedIntake,
    required this.deficit,
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
        ],
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
