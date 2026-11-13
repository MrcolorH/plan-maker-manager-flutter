/// 今日页（对应 tabs/today.vue）
/// 打卡、实际摄入调整（AI 估算）、临时加餐/运动录入
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food_db.dart';
import '../../models/plan_data.dart';
import '../../models/records.dart';
import '../../models/settings.dart';
import '../../providers/app_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_utils.dart';
import '../../utils/date_utils.dart';
import '../../utils/plan_utils.dart';
import '../../widgets/ai_config_sheet.dart';
import '../../widgets/calorie_summary.dart';
import '../../widgets/convert_to_plan_sheet.dart';
import '../../widgets/exercise_breakdown_table.dart';
import '../../widgets/exercise_card.dart';
import '../../widgets/food_breakdown_table.dart';
import '../../widgets/meal_card.dart';
import '../../widgets/meal_recommendation_sheet.dart';
import '../food/food_add_page.dart';
import '../food/food_nutrition_scan_page.dart';
import '../item/item_detail_page.dart';
import 'daily_verify_page.dart';
import 'day_exercise_detail_page.dart';
import 'day_meal_detail_page.dart';

class TodayPage extends StatelessWidget {
  final ui.Image? overrideMascotImage;
  const TodayPage({super.key, this.overrideMascotImage});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    final records = context.watch<RecordProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final today = todayStr();

    final profile = context.watch<OnboardingProvider>().state.profile;
    final summary = dailySummary(plan, settings, records.store, today, profile: profile);

    // F11 快照渲染：当日餐食/运动以「当日条目快照」为准（计划=模板，套用后当天即事实）
    // 今日首次进入兜底：跨天/首启时若当天还没有快照或缺少正餐骨架，则进行快照同步
    final entries = records.store.dayEntries[today];
    if (entries == null || !entries.any((e) => e.kind == 'meal')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context
            .read<RecordProvider>()
            .syncDayEntries(today, context.read<PlanProvider>().plan);
      });
    }
    final entryList = entries ?? const <DayEntry>[];
    final mealEntries = entryList.where((e) => e.kind == 'meal').toList();
    final exEntries = entryList.where((e) => e.kind == 'exercise').toList();

    // 餐食区：计划餐快照 + 今日加餐混排（存储已按 time 排序）
    final mealRows = <Widget>[];
    for (final e in mealEntries) {
      mealRows.add(MealCard(
        entry: e,
        planCalories: (!e.isPlan || e.detached)
            ? null
            : _planMealCal(plan, e.planItemId),
        checked: records.isEntryChecked(today, e),
        focused: _focusMatch(context, 'meal:${e.isPlan ? e.planItemId : e.id}'),
        onTap: () {
          if (e.content.isEmpty) {
            _openEditDialog(context, e);
          } else if (e.detached || !e.isPlan) {
            _openDayMealDetail(context, e);
          } else {
            _openDetail(context, 'meal', e.planItemId);
          }
        },
        onCheck: e.content.isNotEmpty
            ? () => context.read<RecordProvider>().toggleEntryCheck(
                  today,
                  e,
                  plan: context.read<PlanProvider>().plan,
                )
            : null,
        onAdjust: () => _openEditDialog(context, e),
        onDelete: e.isPlan
            ? null
            : () => _confirmDelete(context, () {
                context.read<RecordProvider>().removeDayEntry(today, e.id);
              }, '删除这条${e.slot == 'snack' ? '加餐' : (kTypeCn[e.slot] ?? '餐食')}记录？'),
        onConvertToPlan: (!e.isPlan && e.content.isNotEmpty)
            ? () => _openConvertToPlan(context, e)
            : null,
      ));
    }

    // 运动区：计划运动快照 + 临时加练
    final exRows = <Widget>[];
    for (final e in exEntries) {
      exRows.add(ExerciseCard(
        entry: e,
        planBurn: (!e.isPlan || e.detached)
            ? null
            : _planExBurn(plan, e.planItemId),
        checked: records.isEntryChecked(today, e),
        focused: _focusMatch(context, 'exercise:${e.isPlan ? e.planItemId : e.id}'),
        onTap: () {
          if (e.content.isEmpty) {
            _openEditDialog(context, e);
          } else if (e.detached || !e.isPlan) {
            _openDayExerciseDetail(context, e);
          } else {
            _openDetail(context, 'exercise', e.planItemId);
          }
        },
        onCheck: e.isPlan
            ? () => context.read<RecordProvider>().toggleEntryCheck(
                  today,
                  e,
                  plan: context.read<PlanProvider>().plan,
                )
            : null,
        onAdjust: () => _openEditDialog(context, e),
        onDelete: e.isPlan
            ? null
            : () => _confirmDelete(context, () {
                context.read<RecordProvider>().removeDayEntry(today, e.id);
              }, '删除这条临时运动？'),
      ));
    }

    final doneCount = summary.doneCount;
    final taskCount = summary.taskCount;

    return _scaffold(
      context,
      child: RefreshIndicator(
        onRefresh: () async {
          context.read<AppProvider>().refreshToday();
          context.read<RecordProvider>().cleanDuplicates(today);
          await SyncService().syncInboxToLocal(
            context.read<RecordProvider>(),
            aiConfig: context.read<SettingsProvider>().settings.ai,
            onUsage: context.read<UsageProvider>().addUsage,
          );
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            // 顶部居中标题
            const AppPageTitle(),
            // 顶栏：日期 + 完成度 + 看板娘点缀
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateCn(today),
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          taskCount > 0 ? '$doneCount/$taskCount 已完成' : (doneCount > 0 ? '已打卡 $doneCount 项' : '自由记录'),
                          style: TextStyle(fontSize: 13, color: context.primaryColor, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  _AnimeMascotWidget(overrideImage: overrideMascotImage),
                ],
              ),
            ),
            CalorieSummary(
              baseBurn: summary.baseBurn,
              exerciseBurn: summary.exerciseBurn.round(),
              intake: summary.intake.round(),
              plannedIntake: summary.plannedIntake.round(),
              deficit: summary.deficit,
              intakeProtein: summary.intakeProtein,
              intakeCarbs: summary.intakeCarbs,
              intakeFat: summary.intakeFat,
              plannedProtein: summary.plannedProtein,
              plannedCarbs: summary.plannedCarbs,
              plannedFat: summary.plannedFat,
              onVerify: () => _openDailyVerify(context),
              onRecommend: () => _openMealRecommendation(context),
            ),
            // 今日餐食
            SectionTitle(
              '今日餐食',
              trailing: InkWell(
                onTap: () => _openMealRecommendation(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: context.primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        '推荐吃什么',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: context.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (mealRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('今天没有安排餐食', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                ),
              )
            else
              ...mealRows,
            Row(
              children: [
                Expanded(
                  child: DashedAddButton(
                    '＋ 今日加餐',
                    onTap: () {
                      Navigator.of(context).push(
                        AppRoutes.fade<void>(const FoodAddPage()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DashedAddButton(
                    '📸 拍成分表换算',
                    onTap: () {
                      Navigator.of(context).push(
                        AppRoutes.fade<void>(const FoodNutritionScanPage(initialSlot: 'snack')),
                      );
                    },
                  ),
                ),
              ],
            ),
            // 今日运动
            const SectionTitle('今日运动'),
            if (exRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('今天没有安排运动，好好休息 💤',
                      style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                ),
              )
            else
              ...exRows,
            DashedAddButton('＋ 今日运动', onTap: () {
              _openExerciseDialog(context);
            }),
          ],
        ),
      ),
    );
  }

  Widget _scaffold(BuildContext context, {required Widget child}) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: child),
    );
  }

  bool _focusMatch(BuildContext context, String key) {
    final focus = context.watch<AppProvider>().focusKey;
    return focus.isNotEmpty && focus == key;
  }

  void _confirmDelete(BuildContext context, VoidCallback onOk, String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onOk();
            },
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _openDailyVerify(BuildContext context) {
    Navigator.of(context).push(AppRoutes.fade<void>(
      DailyVerifyPage(date: todayStr()),
    ));
  }

  void _openMealRecommendation(BuildContext context) {
    showMealRecommendationSheet(context);
  }

  void _openDayMealDetail(BuildContext context, DayEntry entry) {
    Navigator.of(context).push(AppRoutes.fade<void>(
      DayMealDetailPage(
        date: todayStr(),
        entry: entry,
        onOpenEdit: () => _openEditDialog(context, entry),
      ),
    ));
  }

  void _openDayExerciseDetail(BuildContext context, DayEntry entry) {
    Navigator.of(context).push(AppRoutes.fade<void>(
      DayExerciseDetailPage(
        date: todayStr(),
        entry: entry,
        onOpenEdit: () => _openEditDialog(context, entry),
      ),
    ));
  }

  void _openDetail(BuildContext context, String type, String id) {
    Navigator.of(context).push(AppRoutes.fade<void>(
      ItemDetailPage(type: type, itemId: id),
    ));
  }

  int? _planMealCal(PlanData plan, String id) {
    for (final m in plan.meals) {
      if (m.id == id) return m.calories;
    }
    return null;
  }

  int? _planExBurn(PlanData plan, String id) {
    for (final e in plan.exercises) {
      if (e.id == id) return e.caloriesBurned;
    }
    return null;
  }

  /// 「编辑这一餐/这一次运动」弹窗（餐食与运动同构；对应 F11 三字段：内容/热量/备注）
  void _openEditDialog(BuildContext context, DayEntry entry) {
    final today = todayStr();
    final records = context.read<RecordProvider>();
    final plan = context.read<PlanProvider>().plan;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _EntryEditSheet(
        date: today,
        entry: entry,
        plan: plan,
        checked: records.isEntryChecked(today, entry),
      ),
    );
  }

  /// 「设为日常计划」弹窗
  void _openConvertToPlan(BuildContext context, DayEntry entry) {
    final today = todayStr();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ConvertToPlanSheet(
        date: today,
        entry: entry,
      ),
    );
  }

  /// 临时运动录入弹窗
  void _openExerciseDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _ExerciseSheet(),
    );
  }
}

/// 编辑当日条目弹窗（F11）：餐食与运动同构 —— 内容 / 热量或消耗 / 备注 + AI 测算 + 恢复计划内容
/// 计划条目：改「内容」保存 → 该条与计划脱钩（detached）；只改热量/备注为当日覆盖（不脱钩）
class _EntryEditSheet extends StatefulWidget {
  final String date;
  final DayEntry entry;
  final PlanData plan;
  final bool checked;
  const _EntryEditSheet({
    required this.date,
    required this.entry,
    required this.plan,
    required this.checked,
  });

  @override
  State<_EntryEditSheet> createState() => _EntryEditSheetState();
}

class _EntryEditSheetState extends State<_EntryEditSheet> {
  late final TextEditingController _contentCtrl;
  late final TextEditingController _calCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _carbsCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _noteCtrl;
  bool _loading = false;
  bool _enableThinking = false;
  bool _syncToPlan = false;
  String? _aiDetail;
  List<FoodBreakdownItem>? _breakdownItems;

  bool get _isEx => widget.entry.kind == 'exercise';
  bool get _isPlan => widget.entry.isPlan;

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(text: widget.entry.content);
    _calCtrl =
        TextEditingController(text: widget.entry.calories != null ? '${widget.entry.calories}' : '');
    _proteinCtrl =
        TextEditingController(text: widget.entry.protein != null ? '${widget.entry.protein}' : '');
    _carbsCtrl =
        TextEditingController(text: widget.entry.carbs != null ? '${widget.entry.carbs}' : '');
    _fatCtrl =
        TextEditingController(text: widget.entry.fat != null ? '${widget.entry.fat}' : '');
    _noteCtrl = TextEditingController(text: widget.entry.note);

    if (widget.entry.items != null && widget.entry.items!.isNotEmpty) {
      _breakdownItems = List<FoodBreakdownItem>.from(widget.entry.items!);
    } else if (widget.entry.detail != null && widget.entry.detail!.isNotEmpty) {
      _breakdownItems = AiService.parseBreakdownFromText(widget.entry.detail);
    }
    _aiDetail = widget.entry.detail;
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ---------- 计划参照（恢复 / 脱钩判定用）----------
  MealItem? get _meal {
    if (!_isPlan || _isEx) return null;
    for (final m in widget.plan.meals) {
      if (m.id == widget.entry.planItemId) return m;
    }
    return null;
  }

  ExerciseItem? get _ex {
    if (!_isPlan || !_isEx) return null;
    for (final e in widget.plan.exercises) {
      if (e.id == widget.entry.planItemId) return e;
    }
    return null;
  }

  /// 计划模板的「内容」文本（计划项已删时退化为当前内容 → 脱钩状态不变）
  String get _planContent {
    if (_isEx) return _ex?.name ?? widget.entry.content;
    return _meal?.name ?? widget.entry.content;
  }

  /// 计划模板的热量/消耗值（null = 自由餐/无计划值）
  int? get _planCal {
    if (_isEx) return _ex?.caloriesBurned ?? widget.entry.calories;
    return _meal?.calories;
  }

  /// 是否可「恢复计划内容」：已脱钩且计划项仍在
  bool get _canRestore => _isPlan && widget.entry.detached && (_isEx ? _ex != null : _meal != null);

  Future<void> _aiEstimate() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) return;
    final note = _noteCtrl.text.trim();
    final desc = note.isNotEmpty ? '$content（备注：$note）' : content;

    // 优先检查本地食物库与沉淀知识库（0 延迟秒出）
    if (!_isEx && !_enableThinking) {
      final userFoods = context.read<PresetProvider>().userFoods;
      final matched = matchAndCalculateFood(desc, userFoods: userFoods) ??
          (note.isNotEmpty ? matchAndCalculateFood(content, userFoods: userFoods) : null);
      if (matched != null) {
        setState(() {
          _calCtrl.text = '${matched.totalCalories}';
          if (matched.totalProtein != null) _proteinCtrl.text = '${matched.totalProtein}';
          if (matched.totalCarbs != null) _carbsCtrl.text = '${matched.totalCarbs}';
          if (matched.totalFat != null) _fatCtrl.text = '${matched.totalFat}';
          _aiDetail = '食物库命中：${matched.calculationDetail}';
          _breakdownItems = matched.breakdownItems;
        });
        return;
      }

      final presetService = context.read<PresetProvider>().service;
      final cached = presetService.getCachedAiEstimate(desc);
      if (cached != null) {
        setState(() {
          _calCtrl.text = '${cached['calories']}';
          if (cached['protein'] != null) _proteinCtrl.text = '${cached['protein']}';
          if (cached['carbs'] != null) _carbsCtrl.text = '${cached['carbs']}';
          if (cached['fat'] != null) _fatCtrl.text = '${cached['fat']}';
          _aiDetail = (cached['detail'] as String?) ?? '（已从本地常吃知识库秒级命中）';
          _breakdownItems = AiService.parseBreakdownItems(cached['items'], cached['detail'] as String?);
        });
        return;
      }
    }

    // 未配置 AI → 先弹配置层，配好后再继续估算
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 测算${_isEx ? '运动消耗' : '这一餐热量'}需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    final ob = context.read<OnboardingProvider>();
    final presetService = context.read<PresetProvider>().service;
    setState(() => _loading = true);
    try {
      final r = _isEx
          ? await _burnNow(settings, usage, ob, desc)
          : await AiService.instance.estimateMeal(settings.ai, desc,
              enableThinking: _enableThinking, onUsage: usage.addUsage);
      if (!mounted) return;
      setState(() {
        _calCtrl.text = '${r['calories']}';
        if (r['protein'] != null) _proteinCtrl.text = '${r['protein']}';
        if (r['carbs'] != null) _carbsCtrl.text = '${r['carbs']}';
        if (r['fat'] != null) _fatCtrl.text = '${r['fat']}';
        _aiDetail = r['detail'] as String?;
        final items = r['items'] as List<FoodBreakdownItem>?;
        _breakdownItems = (items != null && items.isNotEmpty)
            ? items
            : AiService.parseBreakdownFromText(r['detail'] as String?);
      });
      // 成功后自动沉淀为本地知识缓存
      if (!_isEx) {
        await presetService.setCachedAiEstimate(desc, r);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// F10：运动消耗按「当天生效体重（记录链）?? profile.weight」+ 个人资料（信息完整才传）估算
  Future<Map<String, dynamic>> _burnNow(AppSettings settings, UsageProvider usage,
      OnboardingProvider ob, String desc) async {
    final p = ob.state.profile;
    final wd = weightForDate(context.read<RecordProvider>().store, todayStr());
    return AiService.instance.estimateBurn(
      settings.ai,
      desc,
      weight: wd ?? p.weight,
      gender: p.complete ? p.gender : null,
      age: p.complete ? p.age : null,
      height: p.complete ? p.height : null,
      onUsage: usage.addUsage,
    );
  }

  /// 恢复为计划内容：内容/热量复位、备注清空、解除脱钩
  void _restoreToPlan() {
    if (!_canRestore) return;
    setState(() {
      _contentCtrl.text = _planContent;
      final pc = _planCal;
      _calCtrl.text = pc != null ? '$pc' : '';
      final m = _meal;
      _proteinCtrl.text = m?.protein != null ? '${m!.protein}' : '';
      _carbsCtrl.text = m?.carbs != null ? '${m!.carbs}' : '';
      _fatCtrl.text = m?.fat != null ? '${m!.fat}' : '';
      _noteCtrl.clear();
      _aiDetail = null;
      _breakdownItems = null;
    });
  }

  Future<void> _saveAsPreset() async {
    final content = _contentCtrl.text.trim();
    final cal = int.tryParse(_calCtrl.text.trim());
    if (content.isEmpty || cal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先输入食物内容和热量')));
      return;
    }
    final p = int.tryParse(_proteinCtrl.text.trim());
    final c = int.tryParse(_carbsCtrl.text.trim());
    final f = int.tryParse(_fatCtrl.text.trim());
    await context.read<PresetProvider>().savePreset(
          name: content,
          calories: cal,
          protein: p,
          carbs: c,
          fat: f,
          note: _noteCtrl.text.trim(),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已存入常用预设方案：「$content」')));
  }

  Future<DayEntry?> _save({bool checkAfter = false, bool pop = true}) async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('请填写${_isEx ? '运动内容' : '食物内容'}，如「黄焖鸡米饭一份」')));
      return null;
    }
    // 若为运动且尚未拆解/未填消耗，自动执行 AI 拆解与测算
    if (_isEx && (_calCtrl.text.trim().isEmpty || _breakdownItems == null)) {
      await _aiEstimate();
      if (!mounted) return null;
    }
    final calText = _calCtrl.text.trim();
    int? cal;
    if (calText.isNotEmpty) {
      cal = int.tryParse(calText);
      final minCal = _isEx ? 0 : -2000;
      if (cal == null || cal < minCal || cal > 5000) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('请输入 ${_isEx ? '0-5000 的消耗' : '-2000 ~ 5000 的热量（损耗可填负数）'}，留空=待补录')));
        return null;
      }
    }
    final pVal = int.tryParse(_proteinCtrl.text.trim());
    final cVal = int.tryParse(_carbsCtrl.text.trim());
    final fVal = int.tryParse(_fatCtrl.text.trim());

    final old = widget.entry;
    final date = widget.date;
    final records = context.read<RecordProvider>();
    // 计划外条目恒脱钩；计划条目：内容与计划模板不一致即脱钩
    final detachedNow = !_isPlan || old.detached || content != _planContent;
    final dirtyNow = !_isPlan || old.caloriesDirty || (cal != _planCal);
    final updated = DayEntry(
      id: old.id,
      kind: old.kind,
      slot: old.slot,
      time: old.time,
      content: content,
      calories: cal,
      protein: pVal,
      carbs: cVal,
      fat: fVal,
      note: _noteCtrl.text.trim(),
      source: old.source,
      planItemId: old.planItemId,
      detached: detachedNow,
      caloriesDirty: dirtyNow,
      detail: _aiDetail,
      items: _breakdownItems,
    );
    final planProv = context.read<PlanProvider>();
    await records.updateDayEntry(date, updated);

    // 若勾选同步更新长期计划
    if (_syncToPlan && _isPlan && !_isEx) {
      await planProv.syncMealItemFromSnapshot(
            mealId: old.planItemId,
            newName: content,
            newCalories: cal,
            protein: pVal,
            carbs: cVal,
            fat: fVal,
            note: _noteCtrl.text.trim(),
          );
    }

    if (checkAfter) {
      if (!records.isEntryChecked(date, updated)) {
        await records.toggleEntryCheck(date, updated, plan: widget.plan);
      }
    }
    if (pop && mounted) Navigator.pop(context);
    return updated;
  }

  Future<void> _convertToPlan() async {
    final updated = await _save(checkAfter: false, pop: false);
    if (updated == null || !mounted) return;
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ConvertToPlanSheet(
        date: widget.date,
        entry: updated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    final calHint = _isEx ? '如慢跑 5 公里 / 快走 40 分钟' : '如外卖黄焖鸡米饭一份';
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isEx ? '编辑这次运动' : '编辑这一餐',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  '${_isEx ? '运动' : (kTypeCn[widget.entry.slot] ?? '')} · ${widget.entry.time}',
                  style: const TextStyle(fontSize: 14, color: AppColors.textSub),
                ),
                if (widget.entry.detached && _isPlan) ...[
                  const SizedBox(width: 6),
                  const Tag('已改（不跟随计划）', color: 'orange'),
                ],
              ],
            ),
            if (_isPlan)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('改内容 = 换成实际吃的/练的，AI 按新内容测算；只改${_isEx ? '消耗' : '热量'}当天生效，明天恢复计划',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: _isEx ? '运动内容：$calHint' : '食物内容：$calHint',
                filled: true,
                fillColor: AppColors.bg,
                border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _aiEstimate,
                    icon: _loading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('✨'),
                    label: Text(_isEx ? 'AI 算消耗' : (_enableThinking ? '深度测算' : 'AI 测算')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                    ),
                  ),
                ),
                if (!_isEx) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() => _enableThinking = !_enableThinking),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                      decoration: BoxDecoration(
                        color: _enableThinking ? AppColors.orange.withValues(alpha: 0.12) : AppColors.tagBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _enableThinking ? AppColors.orange : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.psychology, size: 14, color: _enableThinking ? AppColors.orange : AppColors.textSub),
                          const SizedBox(width: 2),
                          Text('深度思考', style: TextStyle(fontSize: 11, color: _enableThinking ? AppColors.orange : AppColors.textSub)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _calCtrl,
                    keyboardType: _isEx ? TextInputType.number : const TextInputType.numberWithOptions(signed: true),
                    decoration: InputDecoration(
                      hintText: _isEx ? '消耗 kcal' : '热量 kcal (损耗填负数)',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ),
              ],
            ),
            if (!_isEx) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _proteinCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '蛋白质 g',
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: EdgeInsets.all(8),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _carbsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '碳水 g',
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: EdgeInsets.all(8),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _fatCtrl,
                      keyboardType: const TextInputType.numberWithOptions(signed: true),
                      decoration: const InputDecoration(
                        hintText: '脂肪 g',
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                        isDense: true,
                        contentPadding: EdgeInsets.all(8),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            if (_breakdownItems != null && _breakdownItems!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(_isEx ? Icons.fitness_center_rounded : Icons.table_chart_outlined,
                      size: 14, color: _isEx ? AppColors.orange : AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    _isEx ? '运动项目与消耗拆解' : '成分与热量拆解',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  const Spacer(),
                  if (_aiDetail != null && _aiDetail!.isNotEmpty)
                    Flexible(
                      child: Text(
                        _aiDetail!,
                        style: const TextStyle(fontSize: 10, color: AppColors.textSub),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (_isEx)
                ExerciseBreakdownTable(
                  items: _breakdownItems!,
                  compact: true,
                  totalCalories: int.tryParse(_calCtrl.text.trim()),
                )
              else
                FoodBreakdownTable(
                  items: _breakdownItems!,
                  compact: true,
                  totalCalories: int.tryParse(_calCtrl.text.trim()),
                ),
            ] else if (_aiDetail != null && _aiDetail!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('AI 拆解：$_aiDetail',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                hintText: '备注（可选）',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
            if (!_isEx) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_canRestore)
                    TextButton.icon(
                      onPressed: _restoreToPlan,
                      icon: const Icon(Icons.restore, size: 15),
                      label: const Text('恢复计划', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
                    )
                  else if (!_isPlan) ...[
                    TextButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text('删除这条${_isEx ? '运动' : (kTypeCn[widget.entry.slot] ?? '餐食')}？'),
                            content: Text('确认删除「${widget.entry.content}」？该热量将从今日数据中剔除。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确认删除', style: TextStyle(color: AppColors.danger)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          await context.read<RecordProvider>().removeDayEntry(widget.date, widget.entry.id);
                          if (mounted) Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.delete_outline, size: 15, color: AppColors.danger),
                      label: const Text('删除此条', style: TextStyle(fontSize: 12, color: AppColors.danger)),
                    ),
                    TextButton.icon(
                      onPressed: _convertToPlan,
                      icon: const Icon(Icons.event_repeat_rounded, size: 15),
                      label: const Text('设为日常计划', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ]
                  else
                    const SizedBox.shrink(),
                  TextButton.icon(
                    onPressed: _saveAsPreset,
                    icon: const Icon(Icons.star_border, size: 15),
                    label: const Text('存为常用预设', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.orange),
                  ),
                ],
              ),
            ],
            if (_isPlan && !_isEx) ...[
              Row(
                children: [
                  Checkbox(
                    value: _syncToPlan,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _syncToPlan = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                      '同时更新回长期计划模板（未来该餐以此为准）',
                      style: TextStyle(fontSize: 12, color: AppColors.text),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _save(checkAfter: false),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    child: const Text('保存'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _save(checkAfter: true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    child: const Text('保存并打卡'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 临时运动录入底部弹层
class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet();

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _calCtrl = TextEditingController();
  final FocusNode _descFocusNode = FocusNode();

  Timer? _debounceTimer;
  String _lastEstimatedDesc = '';
  bool _loading = false;
  String? _aiDetail;
  List<FoodBreakdownItem>? _breakdownItems;

  @override
  void initState() {
    super.initState();
    _descCtrl.addListener(_onDescChanged);
    _descFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _descCtrl.removeListener(_onDescChanged);
    _descFocusNode.removeListener(_onFocusChanged);
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _calCtrl.dispose();
    _descFocusNode.dispose();
    super.dispose();
  }

  void _onDescChanged() {
    final text = _descCtrl.text.trim();
    if (text.isEmpty) {
      if (_breakdownItems != null || _aiDetail != null || _lastEstimatedDesc.isNotEmpty) {
        setState(() {
          _breakdownItems = null;
          _aiDetail = null;
          _lastEstimatedDesc = '';
        });
      }
      return;
    }
    if (text == _lastEstimatedDesc) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      _triggerAiEstimate(auto: true);
    });
  }

  void _onFocusChanged() {
    if (!_descFocusNode.hasFocus) {
      final text = _descCtrl.text.trim();
      if (text.isNotEmpty && text != _lastEstimatedDesc && !_loading) {
        _debounceTimer?.cancel();
        _triggerAiEstimate(auto: true);
      }
    }
  }

  Future<void> _triggerAiEstimate({bool auto = false}) async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    if (desc == _lastEstimatedDesc && _breakdownItems != null) return;

    final settings = context.read<SettingsProvider>().settings;
    if (auto && settings.ai.apiKey.isEmpty) {
      // 自动静默触发时不强行弹配置层打扰输入
      return;
    }

    if (!auto) {
      final ok = await ensureAiConfigured(
        context,
        message: 'AI 拆解运动与测算消耗需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
      );
      if (!ok || !mounted) return;
    }

    final usage = context.read<UsageProvider>();
    final ob = context.read<OnboardingProvider>();
    setState(() => _loading = true);
    try {
      final p = ob.state.profile;
      final wd = weightForDate(context.read<RecordProvider>().store, todayStr());
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
      final name = (r['name'] as String?)?.trim() ?? '';
      final cal = r['calories'];
      final detail = r['detail'] as String?;
      final items = r['items'] as List<FoodBreakdownItem>?;
      final parsedItems = (items != null && items.isNotEmpty)
          ? items
          : AiService.parseBreakdownFromText(detail);

      setState(() {
        _lastEstimatedDesc = desc;
        _nameCtrl.text = name.isNotEmpty ? name : desc;
        _calCtrl.text = cal != null ? '$cal' : '';
        _aiDetail = detail;
        _breakdownItems = parsedItems;
      });
    } catch (e) {
      if (!mounted) return;
      if (!auto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final desc = _descCtrl.text.trim();
    // 录入时若输入了一句话描述但尚未拆解，保存时自动先触发 AI 拆解与估算
    if (desc.isNotEmpty && (_calCtrl.text.trim().isEmpty || _nameCtrl.text.trim().isEmpty || _breakdownItems == null)) {
      await _triggerAiEstimate(auto: false);
      if (!mounted) return;
    }

    final name = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : desc;
    final cal = int.tryParse(_calCtrl.text.trim());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入运动名称或描述')));
      return;
    }
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入 0-5000 的消耗热量')));
      return;
    }
    final records = context.read<RecordProvider>();
    final isAi = (_breakdownItems != null && _breakdownItems!.isNotEmpty) || _aiDetail != null;
    await records.addDayEntry(
      todayStr(),
      kind: 'exercise',
      content: name,
      calories: cal,
      source: isAi ? 'ai' : 'manual',
      detail: _aiDetail,
      items: _breakdownItems,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('＋ 今日运动', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Tag('AI 自动拆解', color: 'orange'),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              focusNode: _descFocusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _triggerAiEstimate(),
              decoration: const InputDecoration(
                hintText: '描述运动（输入后自动拆解）：如「慢跑30分钟，拉伸10分钟」',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange)),
                    SizedBox(width: 8),
                    Text('✨ 正在自动拆解运动项目与测算消耗...',
                        style: TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
            if (!_loading && _breakdownItems != null && _breakdownItems!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.fitness_center_rounded, size: 14, color: AppColors.orange),
                  const SizedBox(width: 4),
                  const Text(
                    '运动项目与消耗拆解',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                  const Spacer(),
                  if (_aiDetail != null && _aiDetail!.isNotEmpty)
                    Flexible(
                      child: Text(
                        _aiDetail!,
                        style: const TextStyle(fontSize: 10, color: AppColors.textSub),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              ExerciseBreakdownTable(
                items: _breakdownItems!,
                compact: true,
                totalCalories: int.tryParse(_calCtrl.text.trim()),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      hintText: '运动名',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _calCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '消耗 kcal',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _triggerAiEstimate(),
                  icon: _loading
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('✨', style: TextStyle(fontSize: 12)),
                  label: Text(_breakdownItems != null ? '重测' : 'AI拆解', style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    side: const BorderSide(color: AppColors.orange),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(60, 40),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('记录（计入今日消耗）'),
            ),
          ],
        ),
      ),
    );
  }
}

/// （虚线按钮已统一为 theme 里的 DashedAddButton）

/// 萌系二次元看板娘点缀组件
class _AnimeMascotWidget extends StatefulWidget {
  final ui.Image? overrideImage;
  const _AnimeMascotWidget({this.overrideImage});

  @override
  State<_AnimeMascotWidget> createState() => _AnimeMascotWidgetState();
}

class _AnimeMascotWidgetState extends State<_AnimeMascotWidget> {
  static const _quotes = [
    '今天也要元气满满哦！(๑•̀ㅂ•́)و✧',
    '少喝一杯奶茶，离理想身材又近一步~ 🥤',
    '吃饱了才有力气减脂，营养均衡最重要！🍱',
    '坚持打卡，你流下的每滴汗水都不会被辜负✨',
    '哇！今天的打卡做得很棒，继续保持哦！🎉',
    '慢慢来，罗马不是一天建成的，身材也是~ 🌱',
  ];
  int _quoteIndex = 0;

  void _tapMascot() {
    setState(() {
      _quoteIndex = (_quoteIndex + 1) % _quotes.length;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Text('✨ ', style: TextStyle(fontSize: 16)),
            Expanded(child: Text(_quotes[_quoteIndex])),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeConfig = context.themeConfig;
    final customMascot = themeConfig.customMascotPath;

    Widget avatarWidget;
    if (widget.overrideImage != null) {
      avatarWidget = RawImage(image: widget.overrideImage, fit: BoxFit.cover);
    } else if (customMascot != null &&
        customMascot.isNotEmpty &&
        File(customMascot).existsSync()) {
      avatarWidget = Image.file(File(customMascot), fit: BoxFit.cover);
    } else {
      avatarWidget = Image.asset(
        'assets/themes/mascot_chibi.jpg',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.favorite, color: Colors.pinkAccent),
      );
    }

    return GestureDetector(
      onTap: _tapMascot,
      child: Tooltip(
        message: '知轻打气娘（点击打气）',
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: context.primaryColor.withValues(alpha: 0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: context.primaryColor.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: avatarWidget,
          ),
        ),
      ),
    );
  }
}
