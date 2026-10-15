/// 周报长图海报组件：用于在 App 内展示，并可通过 RepaintBoundary 导出高清长图分享
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/ai_service.dart';
import '../theme/app_theme.dart';
import '../utils/weekly_report_utils.dart';

/// 截取 GlobalKey 对应组件为 PNG 二进制数据
Future<Uint8List?> captureBoundaryToPng(GlobalKey key, {double pixelRatio = 3.0}) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (e) {
    debugPrint('[WeeklyReportPoster] 截图失败: $e');
    return null;
  }
}

class WeeklyReportPoster extends StatelessWidget {
  final WeeklyReportStats stats;
  final WeeklyAdviceResult? advice;
  final bool isScreenshotMode; // 截图模式下可做适当紧凑优化

  const WeeklyReportPoster({
    super.key,
    required this.stats,
    this.advice,
    this.isScreenshotMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(isScreenshotMode ? 0 : 20),
        boxShadow: isScreenshotMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 20),
          _buildHeroMetrics(),
          const SizedBox(height: 20),
          _buildDailyMatrix(),
          const SizedBox(height: 20),
          _buildMacroDistribution(),
          if (stats.totalExerciseBurn > 0 || stats.exerciseDays > 0) ...[
            const SizedBox(height: 20),
            _buildExerciseCard(),
          ],
          if (advice != null) ...[
            const SizedBox(height: 24),
            _buildAiAdviceSection(),
          ],
          const SizedBox(height: 24),
          _buildFooter(),
        ],
      ),
    );
  }

  // ---------- 顶部抬头 ----------
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🌿', style: TextStyle(fontSize: 12)),
                  SizedBox(width: 4),
                  Text(
                    '知轻 · 减脂周报',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              stats.weekLabel,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSub,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '每周复盘与建议',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '知止而后有定，把日子过轻一点',
          style: TextStyle(fontSize: 12, color: AppColors.textSub),
        ),
      ],
    );
  }

  // ---------- 核心成果 4 宫格 ----------
  Widget _buildHeroMetrics() {
    final hasWeight = stats.startWeight != null && stats.endWeight != null;
    final wDelta = stats.weightDelta ?? 0.0;
    final wStr = hasWeight
        ? '${wDelta > 0 ? '+' : ''}${wDelta.toStringAsFixed(2)} kg'
        : '--';
    final isDrop = wDelta <= 0;

    final deficit = stats.totalDeficit;
    final defStr = '${deficit > 0 ? '+' : ''}$deficit kcal';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tagBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _metricCell(
                  label: '体重变化',
                  value: wStr,
                  valueColor: hasWeight
                      ? (isDrop ? AppColors.primary : AppColors.orange)
                      : AppColors.textSub,
                  subLabel: hasWeight
                      ? '${stats.startWeight!.toStringAsFixed(1)} ➔ ${stats.endWeight!.toStringAsFixed(1)}'
                      : '未完整称重',
                ),
              ),
              Container(width: 1, height: 44, color: AppColors.chartGray),
              Expanded(
                child: _metricCell(
                  label: '7天累计缺口',
                  value: defStr,
                  valueColor: deficit >= 0 ? AppColors.primary : AppColors.danger,
                  subLabel: '日均 ${stats.avgDeficit} kcal',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.chartGray.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metricCell(
                  label: '理论减脂估算',
                  value: '约 ${stats.estimatedFatLossKg.toStringAsFixed(2)} kg',
                  valueColor: AppColors.text,
                  subLabel: '基于 7700 kcal 纯脂',
                ),
              ),
              Container(width: 1, height: 44, color: AppColors.chartGray),
              Expanded(
                child: _metricCell(
                  label: '记录与打卡',
                  value: '${stats.taskComplianceRate}%',
                  valueColor: AppColors.text,
                  subLabel: '记了 ${stats.recordedDays}/7 天 · 完成 ${stats.totalDoneTasks} 项',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCell({
    required String label,
    required String value,
    required Color valueColor,
    required String subLabel,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subLabel,
          style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ---------- 逐日缺口与体重矩阵 ----------
  Widget _buildDailyMatrix() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '逐日收支走势',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
        ),
        const SizedBox(height: 10),
        Row(
          children: stats.days.map((d) {
            final def = d.summary.deficit.round();
            final isPositive = def >= 0;
            final isFuture = d.isFuture;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isFuture
                      ? Colors.transparent
                      : (isPositive ? AppColors.primaryBg : AppColors.orangeBg),
                  borderRadius: BorderRadius.circular(8),
                  border: isFuture
                      ? Border.all(color: AppColors.chartGray.withValues(alpha: 0.5))
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      d.weekdayName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isFuture ? AppColors.textFaint : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isFuture ? '-' : (isPositive ? '+$def' : '$def'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isFuture
                            ? AppColors.textFaint
                            : (isPositive ? AppColors.primary : AppColors.orange),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.weight != null ? d.weight!.toStringAsFixed(1) : '·',
                      style: const TextStyle(fontSize: 9, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('正数=缺口（绿），负数=超标（橙），底部为当天体重',
                style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
          ],
        ),
      ],
    );
  }

  // ---------- 宏量营养素供能比 ----------
  Widget _buildMacroDistribution() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '营养素日均供能比',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
            Text(
              '日均摄入 ${stats.avgIntake} kcal',
              style: const TextStyle(fontSize: 11, color: AppColors.textSub),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                if (stats.proteinPercent > 0)
                  Expanded(
                    flex: stats.proteinPercent,
                    child: Container(color: AppColors.primary),
                  ),
                if (stats.carbsPercent > 0)
                  Expanded(
                    flex: stats.carbsPercent,
                    child: Container(color: AppColors.orange),
                  ),
                if (stats.fatPercent > 0)
                  Expanded(
                    flex: stats.fatPercent,
                    child: Container(color: const Color(0xFF6B9AC4)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _macroTag(
              label: '蛋白质',
              gram: '${stats.avgProtein}g',
              percent: '${stats.proteinPercent}%',
              color: AppColors.primary,
              target: stats.targetProtein != null ? '${stats.targetProtein}g' : null,
            ),
            _macroTag(
              label: '碳水',
              gram: '${stats.avgCarbs}g',
              percent: '${stats.carbsPercent}%',
              color: AppColors.orange,
              target: stats.targetCarbs != null ? '${stats.targetCarbs}g' : null,
            ),
            _macroTag(
              label: '脂肪',
              gram: '${stats.avgFat}g',
              percent: '${stats.fatPercent}%',
              color: const Color(0xFF6B9AC4),
              target: stats.targetFat != null ? '${stats.targetFat}g' : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _macroTag({
    required String label,
    required String gram,
    required String percent,
    required Color color,
    String? target,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label $percent', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            Text(
              target != null ? '$gram (目标 $target)' : gram,
              style: const TextStyle(fontSize: 10, color: AppColors.textSub),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- 运动消耗卡片 ----------
  Widget _buildExerciseCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Text('🏃', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('本周运动 ${stats.exerciseDays} 天',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.text)),
                    const SizedBox(width: 8),
                    Text('消耗 +${stats.totalExerciseBurn} kcal',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
                if (stats.exerciseNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '项目：${stats.exerciseNames.join('、')}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- AI 营养师复盘与建议 ----------
  Widget _buildAiAdviceSection() {
    final a = advice!;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶栏标签
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'AI 营养师指导',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                a.headline,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 本周点评
          if (a.review.isNotEmpty) ...[
            const Row(
              children: [
                Text('📋', style: TextStyle(fontSize: 13)),
                SizedBox(width: 4),
                Text('本周点评', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              a.review,
              style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.55),
            ),
            const SizedBox(height: 14),
          ],

          // 未来一周建议
          if (a.suggestions.isNotEmpty) ...[
            const Row(
              children: [
                Text('🎯', style: TextStyle(fontSize: 13)),
                SizedBox(width: 4),
                Text('未来一周建议', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text)),
              ],
            ),
            const SizedBox(height: 8),
            ...a.suggestions.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(top: 1, right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBg,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$idx',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.5),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 10),
          ],

          // 教练寄语
          if (a.encouragement.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.orangeBg.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a.encouragement,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 底部水印 ----------
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.chartGray.withValues(alpha: 0.5))),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('知轻 · 把日子过轻一点', style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
          Text('单机离线优先减脂助手', style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
        ],
      ),
    );
  }

}
