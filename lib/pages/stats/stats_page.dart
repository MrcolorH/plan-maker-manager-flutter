/// 统计页（对应 tabs/stats.vue）
/// 打卡天数 + 本周缺口图 + 月历 + 14 天趋势 + 月回顾 + 日详情/补录
library;

import 'dart:math' as math;

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
import '../../utils/date_utils.dart';
import '../../utils/plan_utils.dart';
import '../../widgets/ai_config_sheet.dart';
import '../../widgets/meal_card.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _trendTapIndex;

  // 本周缺口图尺寸：0 基准线居中，上下各 _weekHalfH 的绘图区
  static const double _weekHalfH = 42.0;
  static const double _weekTopLabelH = 13.0;
  static const double _weekChartHeight =
      _weekTopLabelH + _weekHalfH * 2 + 5 + 16; // 上标签 + 上下半区 + 间距 + 星期行（留余量防溢出）

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    final records = context.watch<RecordProvider>();
    final settings = context.watch<SettingsProvider>().settings;

    if (!plan.hasPlan) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: const [
              AppPageTitle(),
              Expanded(
                child: EmptyState(icon: '📊', text: '暂无统计数据', subText: '导入计划并开始打卡后，这里会展示你的进度'),
              ),
            ],
          ),
        ),
      );
    }

    final streak = streakDays(records.store);
    final totalDays = totalDoneDays(records.store);
    final week = weekData(plan, settings, records.store);
    final trend = trendData(plan, settings, records.store, 14);
    final monthD = monthData(plan, records.store, _month.year, _month.month);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const AppPageTitle(),
            _streakCard(streak, totalDays),
            // 三张图表各自隔离重绘：打卡引起的重建不会互相传播
            RepaintBoundary(child: _weekCard(context, week)),
            RepaintBoundary(child: _monthCard(context, plan, monthD, records.store)),
            RepaintBoundary(child: _trendCard(context, trend)),
          ],
        ),
      ),
    );
  }

  // ---------- 打卡卡 ----------
  Widget _streakCard(int streak, int totalDays) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text('$streak', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 4),
                const Text('连续打卡（天）', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          ),
          Container(width: 0.5, height: 40, color: AppColors.chartGray),
          Expanded(
            child: Column(
              children: [
                Text('$totalDays', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 4),
                const Text('累计打卡（天）', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 本周热量缺口卡 ----------
  Widget _weekCard(BuildContext context, List<WeekDay> week) {
    final today = todayStr();
    final total = week.fold<num>(0, (a, w) => a + (w.future || w.beforeStart ? 0 : w.summary.deficit));
    final count = week.where((w) => !w.future && !w.beforeStart).length;
    final avg = count > 0 ? (total / count).round() : 0;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本周热量缺口', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('共 $total · 日均 $avg',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 0 基准线布局：上半区画正值（绿，向上生长），下半区画负值（橙，向下生长）
          SizedBox(
            height: _weekChartHeight,
            child: Stack(
              children: [
                // 0 基准线（贯穿整行，位于上/下半区交界处）
                Positioned(
                  top: _weekTopLabelH + _weekHalfH - 0.5,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: AppColors.chartGray),
                ),
                // start 对齐：保证每列顶部贴齐 Stack 顶部，0 基准线位置才对得上
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: week.map((w) {
                    final wd = parseDate(w.date).weekday;
                    final isToday = w.date == today;
                    final hasBar = !w.future && !w.beforeStart;
                    final d = w.summary.deficit;
                    final positive = d >= 0;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _openDayDetail(context, w.date),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 正值标签（贴在 0 线上方顶部，固定高度避免柱高变化抖动）
                            SizedBox(
                              height: _weekTopLabelH,
                              child: Center(
                                child: Text(
                                  hasBar && positive ? '+${d.round()}' : '',
                                  style: const TextStyle(fontSize: 10, color: AppColors.primary),
                                ),
                              ),
                            ),
                            // 上半区：缺口（正值，向上）
                            SizedBox(
                              height: _weekHalfH,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: hasBar && positive ? _bar(d) : null,
                              ),
                            ),
                            // 下半区：超标（负值，向下）
                            SizedBox(
                              height: _weekHalfH,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: hasBar && !positive ? _bar(d) : null,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '周${weekCn(wd)}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isToday ? AppColors.primary : AppColors.textSub,
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text('0 线以上=缺口（掉秤方向，绿），以下=超标（橙）；点某天可补录',
              style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
        ],
      ),
    );
  }

  Color _barColor(num deficit) {
    if (deficit < 0) return AppColors.chartOrange;
    return AppColors.chartGreen;
  }

  /// 柱体：单边最大 _weekHalfH，/19 的密度约 800 kcal 顶格（典型缺口 400-800）
  Widget _bar(num deficit) {
    final h = (deficit.abs() / 19).clamp(3.0, _weekHalfH);
    final color = _barColor(deficit);
    return RepaintBoundary(
      child: Container(
        width: 14,
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ---------- 月历卡 ----------
  Widget _monthCard(BuildContext context, PlanData plan, MonthData monthD, RecordStore records) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                child: const Icon(Icons.chevron_left, size: 22, color: AppColors.textSub),
              ),
              Expanded(
                child: Center(
                  child: Text('${_month.year}年${_month.month}月',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 4),
              // 老版：标题右侧浅绿底绿字胶囊
              GestureDetector(
                onTap: () => _openMonthReview(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('月回顾', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                child: const Icon(Icons.chevron_right, size: 22, color: AppColors.textSub),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              _WeekHead('一'), _WeekHead('二'), _WeekHead('三'), _WeekHead('四'),
              _WeekHead('五'), _WeekHead('六'), _WeekHead('日'),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            children: monthD.cells.map((cell) {
              if (cell == null) return const SizedBox();
              // F10：有体重录入的格子显示小字体重（未录入的天不显示沿用值，避免满屏噪音）
              final w = records.weightRecords.records[cell.date];
              final weightText = (w == null)
                  ? null
                  : (w.weight == w.weight.roundToDouble() ? '${w.weight.round()}' : '${w.weight}');
              return GestureDetector(
                onTap: () => _openDayDetail(context, cell.date),
                child: _monthCell(cell, weightText: weightText),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // 图例（老版：居中一行）
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppColors.primary, filled: true, text: '全部完成'),
              SizedBox(width: 10),
              _LegendDot(color: Color(0xFFBFDCCB), filled: true, text: '部分完成'),
              SizedBox(width: 10),
              _LegendDot(color: AppColors.primary, filled: false, text: '待开始'),
              SizedBox(width: 10),
              _LegendDot(color: AppColors.chartGray, filled: true, text: '无数据'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: plan.meta.startedAt.isNotEmpty
                ? Text('${dateCn(plan.meta.startedAt)}开始（绿点标记），之前的日子不统计',
                    style: const TextStyle(fontSize: 10, color: AppColors.textFaint))
                : const Text('点某天可查看当天吃了什么',
                    style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
          ),
        ],
      ),
    );
  }

  /// 圆圈底色相对网格单元缩到 70%（老版撑满整格，视觉过重）
  static const double _monthCircleScale = 0.7;

  /// 月历格子（对照 stats.vue calClass + 开始日绿点）：
  /// 状态判定走 [monthCellKind]（与单测共用同一逻辑）；weightText 为当天体重小字（仅录入日显示）
  Widget _monthCell(MonthCell cell, {String? weightText}) {
    final kind = monthCellKind(cell);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final d = math.min(c.maxWidth, c.maxHeight) * _monthCircleScale;
            if (kind == MonthCellKind.none) {
              // 灰字（不画圈，也不标未完成）
              return Center(
                child: Text('${cell.day}',
                    style: const TextStyle(fontSize: 13, color: AppColors.chartGray)),
              );
            }
            final complete = kind == MonthCellKind.complete;
            final partial = kind == MonthCellKind.partial;
            final Color bg = complete
                ? AppColors.primary
                : (partial ? const Color(0xFFDCEDE3) : Colors.transparent);
            final Color fg = complete ? Colors.white : AppColors.primary;
            final Border? border = complete || partial
                ? null
                : Border.all(color: const Color(0xFFBFDCCB), width: 1.2);
            return Center(
              child: SizedBox(
                width: d,
                height: d,
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: border,
                  ),
                  alignment: Alignment.center,
                  child: Text('${cell.day}',
                      style: TextStyle(fontSize: 13, color: fg)),
                ),
              ),
            );
          },
        ),
        if (cell.isStart)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
        if (weightText != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(weightText,
                style: const TextStyle(fontSize: 8, color: AppColors.textSub, height: 1)),
          ),
      ],
    );
  }

  // ---------- 近 14 天热量缺口卡 ----------
  Widget _trendCard(BuildContext context, List<TrendPoint> trend) {
    final today = todayStr();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('近 14 天热量缺口（kcal）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(trend.length, (i) {
                final p = trend[i];
                final taped = _trendTapIndex == i;
                final isToday = p.date == today;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _trendTapIndex = taped ? null : i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 点选时显示数值
                        SizedBox(
                          height: 14,
                          child: taped
                              ? Text('${p.deficit.round()}',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: p.deficit < 0 ? AppColors.orange : AppColors.primary))
                              : const SizedBox(),
                        ),
                        SizedBox(
                          height: 58,
                          child: p.hasData
                              ? Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: 12,
                                    height: (p.deficit.abs() / 12).clamp(4.0, 58.0),
                                    decoration: BoxDecoration(
                                      color: _barColor(p.deficit),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                )
                              : const SizedBox(), // 老版：无数据的天留白
                        ),
                        const SizedBox(height: 5),
                        Text(
                          p.label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 9,
                            color: isToday ? AppColors.primary : AppColors.textSub,
                            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          const Text('向上=缺口（掉秤方向），向下=超标；点柱子看当天数值',
              style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
        ],
      ),
    );
  }

  // ---------- 日详情弹层 ----------
  void _openDayDetail(BuildContext context, String date) {
    final plan = context.read<PlanProvider>().plan;
    final records = context.read<RecordProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final detail = dayDetail(plan, settings, records.store, date);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _DayDetailSheet(date: date, detail: detail),
    );
  }

  void _openMonthReview(BuildContext context) {
    final plan = context.read<PlanProvider>().plan;
    final records = context.read<RecordProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final review = monthReview(plan, settings, records.store, _month.year, _month.month);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _MonthReviewSheet(review: review),
    );
  }
}

/// 月历格子显示状态（对照 stats.vue calClass，不含开始日绿点——dot 独立叠加）
enum MonthCellKind {
  /// 未来或今天已排计划但未打卡 → 空心绿圈「待开始」
  planned,

  /// 全部完成 → 实心绿底白字
  complete,

  /// 部分完成（done>0 未全）→ 浅绿底绿字
  partial,

  /// 灰字：未来无计划 / 开始前 / 无数据 / 过去未完成（不标「未完成」）
  none,
}

/// 由月历格子数据判定显示状态（与测试共用同一逻辑，防 UI/口径漂移）
MonthCellKind monthCellKind(MonthCell cell, {String? today}) {
  final t = today ?? todayStr();
  if ((cell.future || cell.date == t) && cell.total > 0 && cell.done == 0) {
    return MonthCellKind.planned;
  }
  if (cell.complete) return MonthCellKind.complete;
  if (cell.done > 0) return MonthCellKind.partial;
  return MonthCellKind.none;
}

class _WeekHead extends StatelessWidget {
  final String text;
  const _WeekHead(this.text);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final bool filled; // false = 空心圈
  final String text;
  const _LegendDot({required this.color, required this.filled, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: filled ? null : Border.all(color: color, width: 1.1),
          ),
        ),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
      ],
    );
  }
}

/// 某日详情弹层
class _DayDetailSheet extends StatelessWidget {
  final String date;
  final DayDetail detail;
  const _DayDetailSheet({required this.date, required this.detail});

  String get _statusText {
    if (detail.future) return '未开始';
    final t = todayStr();
    final diff = _diffDays(date, t);
    if (diff >= -2 && diff <= 0) return '可补录';
    return '';
  }

  int _diffDays(String a, String b) {
    final pa = parseDate(a);
    final pb = parseDate(b);
    return DateTime(pa.y, pa.m, pa.d).difference(DateTime(pb.y, pb.m, pb.d)).inDays;
  }

  // 弹层缺口文案：未来显示「待开始」，无记录显示「暂无」，避免出现 TDEE 假缺口
  String _defText() {
    final s = detail.summary;
    if (detail.future) return '待开始';
    if (!s.hasData) return '暂无';
    final v = s.deficit.round();
    return v > 0 ? '+$v' : '$v';
  }

  // 缺口着色（对照 numClass）：未来/无数据 muted；负 red；0-300 orange；其余绿
  Color _defColor() {
    final s = detail.summary;
    if (detail.future || !s.hasData) return AppColors.textSub;
    if (s.deficit < 0) return AppColors.danger;
    if (s.deficit <= 300) return AppColors.orange;
    return AppColors.primary;
  }

  // F10 体重格：未来「—」；沿用链生效体重；无任何来源「未记录」
  String _weightText(RecordStore store) {
    if (detail.future) return '—';
    final wt = weightForDate(store, date);
    if (wt == null) return '未记录';
    return wt == wt.roundToDouble() ? '${wt.round()} kg' : '$wt kg';
  }

  Color _weightColor(RecordStore store) {
    if (detail.future) return AppColors.textSub;
    final wt = weightForDate(store, date);
    return wt == null ? AppColors.textSub : AppColors.text;
  }

  @override
  Widget build(BuildContext context) {
    final records = context.read<RecordProvider>();
    final s = detail.summary;
    final canAdjust = _statusText == '可补录';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateCn(date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      if (_statusText.isNotEmpty)
                        Tag(_statusText, color: 'orange'),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _stat('计划完成', '${s.doneCount}/${s.taskCount}', AppColors.text)),
                  Expanded(child: _stat('已摄入', detail.future ? '—' : '${s.intake.round()}', detail.future ? AppColors.textSub : AppColors.orange)),
                  Expanded(child: _stat('热量缺口', _defText(), _defColor())),
                  Expanded(child: _stat('体重', _weightText(records.store), _weightColor(records.store))),
                ],
              ),
              if (!detail.future && !detail.beforeStart && s.hasData)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '基础消耗 ${s.baseBurn} kcal（BMR×1.2，不含运动）· 运动消耗 ${s.exerciseBurn.round()} kcal',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                  ),
                ),
              if (detail.future)
                const _DetailHint('还没到这天，以下是计划安排')
              else if (detail.beforeStart)
                const _DetailHint('计划开始前，无统计数据')
              else if (!canAdjust)
                const _DetailHint('仅支持补录近 3 天（前天～今天）的记录'),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    if (detail.meals.isNotEmpty) ...[
                      const _SectionLabel('餐食'),
                      ...detail.meals.map((m) => _mealRow(context, records, m, canAdjust)),
                    ],
                    if (detail.snacks.isNotEmpty) ...[
                      const _SectionLabel('加餐'),
                      ...detail.snacks.map((t) => _snackRow(context, records, t)),
                    ],
                    if (detail.exercises.isNotEmpty) ...[
                      const _SectionLabel('运动'),
                      ...detail.exercises.map((e) => _exerciseRow(context, records, e, canAdjust)),
                    ],
                    if (detail.tempExercises.isNotEmpty) ...[
                      const _SectionLabel('临时运动'),
                      ...detail.tempExercises.map((t) => _tempExRow(context, records, t)),
                    ],
                    if (canAdjust) ...[
                      const SizedBox(height: 10),
                      DashedAddButton('＋ 补录加餐',
                          margin: const EdgeInsets.symmetric(horizontal: 0),
                          onTap: () => _addSnack(ctx, date)),
                      const SizedBox(height: 8),
                      DashedAddButton('＋ 补录锻炼',
                          margin: const EdgeInsets.symmetric(horizontal: 0),
                          onTap: () => _addExercise(ctx, date)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
      ],
    );
  }

  Widget _mealRow(BuildContext context, RecordProvider records, DayDetailItem m, bool canAdjust) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: canAdjust ? () => records.toggleCheck(date, 'meal', m.id) : null,
            child: CheckCircle(checked: m.checked, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('${kTypeCn[m.type] ?? ''} · ${m.time}', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                if (m.note.isNotEmpty)
                  Text(m.note, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          Text('${m.actualCal ?? m.plannedCal ?? 0} kcal', style: const TextStyle(fontSize: 12, color: AppColors.orange)),
        ],
      ),
    );
  }

  Widget _snackRow(BuildContext context, RecordProvider records, DaySnack t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Text('＋', style: TextStyle(fontSize: 16, color: AppColors.orange)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text('食物库/AI · ${t.time}', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          Text('${t.calories} kcal', style: const TextStyle(fontSize: 12, color: AppColors.orange)),
          IconButton(
            onPressed: () => records.removeDayEntry(date, t.id),
            icon: const Icon(Icons.close, size: 16, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _exerciseRow(BuildContext context, RecordProvider records, DayDetailExercise e, bool canAdjust) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: canAdjust ? () => records.toggleCheck(date, 'exercise', e.id) : null,
            child: CheckCircle(checked: e.checked, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(e.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Text('${e.duration > 0 ? '${e.duration}min · ' : ''}≈-${e.burn}', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
        ],
      ),
    );
  }

  Widget _tempExRow(BuildContext context, RecordProvider records, DaySnack t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Text('🏃', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(t.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Text('≈-${t.calories}', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
          IconButton(
            onPressed: () => records.removeDayEntry(date, t.id),
            icon: const Icon(Icons.close, size: 16, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  void _addSnack(BuildContext context, String date) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => _RecordSheet(date: date, type: 'snack'),
    );
  }

  void _addExercise(BuildContext context, String date) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) => _RecordSheet(date: date, type: 'exercise'),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSub)),
    );
  }
}

/// 日详情弹层的状态提示行（未来/开始前/只读说明）
class _DetailHint extends StatelessWidget {
  final String text;
  const _DetailHint(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
    );
  }
}

/// 补录弹窗（加餐/锻炼）：AI 估算 + 手动录入
class _RecordSheet extends StatefulWidget {
  final String date;
  final String type;
  const _RecordSheet({required this.date, required this.type});

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _calCtrl = TextEditingController();
  bool _loading = false;
  bool _aiUsed = false;
  String? _aiDetail;

  bool get _isSnack => widget.type == 'snack';

  @override
  void dispose() {
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _calCtrl.dispose();
    super.dispose();
  }

  Future<void> _aiEstimate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isSnack ? '请先描述吃了什么，如「一杯大杯珍珠奶茶」' : '请先描述做了什么运动，如「慢跑 40 分钟」')));
      return;
    }
    // 未配置 AI → 先弹配置层，配好后再继续估算
    final ok = await ensureAiConfigured(
      context,
      message:
          'AI 估算${_isSnack ? '热量' : '运动消耗'}需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    setState(() => _loading = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final usage = context.read<UsageProvider>();
      String? detail;
      if (_isSnack) {
        final r = await AiService.instance.queryCalorie(settings.ai, desc, onUsage: usage.addUsage);
        if (!mounted) return;
        _nameCtrl.text = r['name'] as String;
        _calCtrl.text = '${r['calories']}';
        final unit = (r['unit'] as String?) ?? '';
        final conf = ((r['confidence'] as num?) ?? 0);
        detail = 'AI 估算 · 置信度 ${(conf * 100).round()}%${unit.isNotEmpty ? ' · $unit' : ''}';
      } else {
        // F10：运动消耗结合个人资料 —— 补录日生效体重（记录链）优先，profile 兜底；信息完整才传性别/年龄/身高
        final ob = context.read<OnboardingProvider>();
        final p = ob.state.profile;
        final wd = weightForDate(context.read<RecordProvider>().store, widget.date);
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
        _nameCtrl.text = r['name'] as String;
        _calCtrl.text = '${r['calories']}';
        final d = r['detail'] as String?;
        if (d != null && d.isNotEmpty) detail = 'AI 拆解：$d';
      }
      setState(() {
        _aiUsed = true;
        _aiDetail = detail;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final cal = int.tryParse(_calCtrl.text.trim());
    if (name.isEmpty || cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写名称和 0-5000 的热量')));
      return;
    }
    await context.read<RecordProvider>().addDayEntry(
          widget.date,
          kind: _isSnack ? 'meal' : 'exercise',
          slot: _isSnack ? 'snack' : '',
          content: name,
          calories: cal,
          source: _aiUsed ? 'ai' : 'manual',
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isSnack ? '补录加餐' : '补录锻炼',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: _isSnack ? 2 : 1,
              decoration: InputDecoration(
                hintText: _isSnack ? '一句话描述：如「一杯大杯珍珠奶茶全糖」' : '一句话描述：如「慢跑 40 分钟」',
                filled: true,
                fillColor: AppColors.bg,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _aiEstimate,
                  icon: _loading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('✨'),
                  label: const Text('AI 估算'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    side: const BorderSide(color: AppColors.orange),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: _isSnack ? '名称' : '运动名',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _calCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: _isSnack ? '热量 kcal' : '消耗 kcal',
                filled: true,
                fillColor: AppColors.bg,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            if (_aiDetail != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_aiDetail!, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 月回顾弹层
class _MonthReviewSheet extends StatelessWidget {
  final MonthReview review;
  const _MonthReviewSheet({required this.review});

  @override
  Widget build(BuildContext context) {
    final r = review;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('月回顾', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: _stat('计划完成天数', '${r.doneDays}', AppColors.primary)),
              Expanded(child: _stat('总缺口', '${r.totalDeficit.round()}', AppColors.text)),
              Expanded(child: _stat('日均缺口', '${r.avgDeficit}', AppColors.text)),
            ],
          ),
          const SizedBox(height: 6),
          Text('已记录 ${r.activeDays} 天', style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 12),
          if (r.maxBurnDay != null) _maxCard(context, '🔥 消耗最多的一天', r.maxBurnDay!),
          const SizedBox(height: 8),
          if (r.maxIntakeDay != null) _maxCard(context, '🍽 摄入最多的一天', r.maxIntakeDay!),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
      ],
    );
  }

  Widget _maxCard(BuildContext context, String title, MaxDay day) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(day.date, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 6),
          Text('缺口 ${day.deficit.round()} · 总摄入 ${day.intake.round()} · 总消耗 ${day.burn.round()}（基础 ${day.base} + 运动 ${day.exercise.round()}）',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              // 打开日详情
              final plan = context.read<PlanProvider>().plan;
              final records = context.read<RecordProvider>();
              final settings = context.read<SettingsProvider>().settings;
              final detail = dayDetail(plan, settings, records.store, day.date);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (ctx) => _DayDetailSheet(date: day.date, detail: detail),
              );
            },
            child: const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('查看详情 ›', style: TextStyle(fontSize: 12, color: AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }
}
