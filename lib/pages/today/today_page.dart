/// 今日页（对应 tabs/today.vue）
/// 打卡、实际摄入调整（AI 估算）、临时加餐/运动录入
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../models/records.dart';
import '../../providers/app_provider.dart';
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
import '../../widgets/calorie_summary.dart';
import '../../widgets/exercise_card.dart';
import '../../widgets/meal_card.dart';
import '../food/food_add_page.dart';
import '../item/item_detail_page.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    final records = context.watch<RecordProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final today = todayStr();

    // 无计划 → 整页空状态
    if (!plan.hasPlan) {
      return _scaffold(
        context,
        child: const Column(
          children: [
            AppPageTitle(),
            Expanded(
              child: EmptyState(
                icon: '📭',
                text: '还没有计划',
                subText: '去「计划」页导入或创建你的减脂计划吧',
              ),
            ),
          ],
        ),
      );
    }

    final tasks = getTasksForDate(plan, today);
    final temps = records.getTempTasks(today);
    final summary = dailySummary(plan, settings, records.store, today);

    // 计划餐 + 临时加餐按时间混排
    final mealRows = <Widget>[];
    final tempMeals = temps.where((t) => !t.isExercise).toList();
    final allMeals = <(String, String, dynamic)>[
      ...tasks.meals.map((m) => ('meal', m.id, m as dynamic)),
      ...tempMeals.map((t) => ('temp', t.id, t as dynamic)),
    ]..sort((a, b) {
        final ta = a.$3 is MealItem ? (a.$3 as MealItem).time : (a.$3 as TempTask).time;
        final tb = b.$3 is MealItem ? (b.$3 as MealItem).time : (b.$3 as TempTask).time;
        return timeToMin(ta) - timeToMin(tb);
      });

    for (final row in allMeals) {
      final isTemp = row.$1 == 'temp';
      if (isTemp) {
        final t = row.$3 as TempTask;
        mealRows.add(MealCard(
          meal: MealItem(
            id: t.id,
            type: 'snack',
            name: t.name,
            time: t.time,
            calories: t.calories,
          ),
          checked: records.isChecked(today, 'temp', t.id),
          isTemp: true,
          focused: _focusMatch(context, 'temp:${t.id}'),
          onDelete: () => _confirmDelete(context, () {
            context.read<RecordProvider>().removeTempTask(today, t.id);
          }, '删除这条加餐记录？'),
        ));
      } else {
        final m = row.$3 as MealItem;
        final adj = records.getAdjust(today, 'meal', m.id);
        mealRows.add(MealCard(
          meal: m,
          checked: records.isChecked(today, 'meal', m.id),
          actualCal: adj?.calories,
          actualNote: adj?.note ?? '',
          focused: _focusMatch(context, 'meal:${m.id}'),
          onTap: () => _openDetail(context, 'meal', m.id),
          onCheck: () => context.read<RecordProvider>().toggleCheck(today, 'meal', m.id),
          onAdjust: () => _openAdjustDialog(context, m),
        ));
      }
    }

    // 运动区
    final exRows = <Widget>[];
    for (final e in tasks.exercises) {
      exRows.add(ExerciseCard(
        exercise: e,
        checked: records.isChecked(today, 'exercise', e.id),
        focused: _focusMatch(context, 'exercise:${e.id}'),
        onTap: () => _openDetail(context, 'exercise', e.id),
        onCheck: () => context.read<RecordProvider>().toggleCheck(today, 'exercise', e.id),
      ));
    }
    final tempExs = temps.where((t) => t.isExercise).toList();
    for (final t in tempExs) {
      exRows.add(ExerciseCard(
        exercise: ExerciseItem(
          id: t.id,
          name: t.name,
          time: t.time,
          duration: 0,
          caloriesBurned: t.calories,
        ),
        checked: records.isChecked(today, 'temp', t.id),
        isTemp: true,
        onDelete: () => _confirmDelete(context, () {
          context.read<RecordProvider>().removeTempTask(today, t.id);
        }, '删除这条临时运动？'),
      ));
    }

    final doneCount = summary.doneCount;
    final taskCount = summary.taskCount;

    return _scaffold(
      context,
      child: RefreshIndicator(
        onRefresh: () async => context.read<AppProvider>().refreshToday(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // 顶部居中标题
            const AppPageTitle(),
            // 顶栏：日期 + 完成度
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    dateCn(today),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppColors.text),
                  ),
                  Text(
                    '$doneCount/$taskCount 已完成',
                    style: const TextStyle(fontSize: 13, color: AppColors.primary),
                  ),
                ],
              ),
            ),
            CalorieSummary(
              baseBurn: summary.baseBurn,
              exerciseBurn: summary.exerciseBurn.round(),
              intake: summary.intake.round(),
              plannedIntake: summary.plannedIntake.round(),
              deficit: summary.deficit,
            ),
            // 今日餐食
            const SectionTitle('今日餐食'),
            if (mealRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('今天没有安排餐食', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                ),
              )
            else
              ...mealRows,
            DashedAddButton('＋ 今日加餐（搜食物库 / AI 算热量，仅今天有效）',
              onTap: () {
                Navigator.of(context).push(
                  AppRoutes.fade<void>(const FoodAddPage()),
                );
              },
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
      backgroundColor: AppColors.bg,
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

  void _openDetail(BuildContext context, String type, String id) {
    Navigator.of(context).push(AppRoutes.fade<void>(
      ItemDetailPage(type: type, itemId: id),
    ));
  }

  /// 「实际吃了多少」弹窗（对应 ✎ 调整）
  void _openAdjustDialog(BuildContext context, MealItem meal) {
    final today = todayStr();
    final records = context.read<RecordProvider>();
    final adj = records.getAdjust(today, 'meal', meal.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AdjustSheet(meal: meal, initial: adj),
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

/// 实际摄入调整底部弹层
class _AdjustSheet extends StatefulWidget {
  final MealItem meal;
  final AdjustEntry? initial;
  const _AdjustSheet({required this.meal, this.initial});

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  late final TextEditingController _calCtrl;
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _loading = false;
  String? _aiDetail;

  @override
  void initState() {
    super.initState();
    _calCtrl = TextEditingController(
        text: widget.initial != null ? '${widget.initial!.calories}' : '');
    _noteCtrl.text = widget.initial?.note ?? '';
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _aiEstimate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    // 未配置 AI → 先弹配置层，配好后再继续估算
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 估算这一餐需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    setState(() => _loading = true);
    try {
      final r = await AiService.instance.estimateMeal(settings.ai, desc, onUsage: usage.addUsage);
      if (!mounted) return;
      setState(() {
        _calCtrl.text = '${r['calories']}';
        _aiDetail = r['detail'] as String?;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({bool checkAfter = false}) async {
    final cal = int.tryParse(_calCtrl.text.trim());
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入 0-5000 的实际热量')));
      return;
    }
    final today = todayStr();
    final records = context.read<RecordProvider>();
    await records.setAdjust(today, 'meal', widget.meal.id, {
      'calories': cal,
      'note': _noteCtrl.text.trim(),
    });
    if (checkAfter) {
      await records.toggleCheck(today, 'meal', widget.meal.id);
    }
    if (mounted) Navigator.pop(context);
  }

  void _resetToPlan() {
    final today = todayStr();
    context.read<RecordProvider>().setAdjust(today, 'meal', widget.meal.id, null);
    Navigator.pop(context);
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
                const Text('今日实际摄入', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            Text(widget.meal.name, style: const TextStyle(fontSize: 14, color: AppColors.textSub)),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: '大白话描述：如「没买到豆浆，只吃了两个包子」',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
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
                    label: const Text('AI 估算'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _calCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '实际 kcal',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                ),
              ],
            ),
            if (_aiDetail != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('AI 拆解：$_aiDetail', style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                hintText: '备注（可选）',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _resetToPlan,
                    child: const Text('按计划吃（重置）', style: TextStyle(color: AppColors.textSub)),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _save(),
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
  bool _loading = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    _nameCtrl.dispose();
    _calCtrl.dispose();
    super.dispose();
  }

  Future<void> _aiEstimate() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) return;
    // 未配置 AI → 先弹配置层，配好后再继续估算
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 估算运动消耗需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    final ob = context.read<OnboardingProvider>();
    setState(() => _loading = true);
    try {
      final r = await AiService.instance.estimateBurn(
        settings.ai,
        desc,
        ob.state.profile.weight,
        onUsage: usage.addUsage,
      );
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = r['name'] as String;
        _calCtrl.text = '${r['calories']}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final cal = int.tryParse(_calCtrl.text.trim());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入运动名称')));
      return;
    }
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入 0-5000 的消耗热量')));
      return;
    }
    final records = context.read<RecordProvider>();
    await records.addTempTask(todayStr(),
        type: 'exercise', name: name, calories: cal, source: 'manual');
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
                const Text('＋ 今日运动', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                hintText: '一句话描述：如「慢跑 40 分钟」',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
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
                    label: const Text('AI 算'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
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
              ],
            ),
            const SizedBox(height: 8),
            TextField(
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
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
              child: const Text('记录（计入今日消耗）'),
            ),
          ],
        ),
      ),
    );
  }
}

/// （虚线按钮已统一为 theme 里的 DashedAddButton）
