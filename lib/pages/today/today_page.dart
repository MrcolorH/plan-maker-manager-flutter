/// 今日页（对应 tabs/today.vue）
/// 打卡、实际摄入调整（AI 估算）、临时加餐/运动录入
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../models/records.dart';
import '../../models/settings.dart';
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

    final summary = dailySummary(plan, settings, records.store, today);

    // F11 快照渲染：当日餐食/运动以「当日条目快照」为准（计划=模板，套用后当天即事实）
    // 今日首次进入兜底：跨天/首启时若当天还没有快照，则从计划实例化
    final entries = records.store.dayEntries[today];
    if (plan.hasPlan && entries == null) {
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
        onTap: e.isPlan
            ? () => _openDetail(context, 'meal', e.planItemId)
            : () => _openEditDialog(context, e),
        onCheck: e.isPlan
            ? () => context.read<RecordProvider>().toggleCheck(today, 'meal', e.planItemId)
            : null,
        onAdjust: () => _openEditDialog(context, e),
        onDelete: e.isPlan
            ? null
            : () => _confirmDelete(context, () {
                context.read<RecordProvider>().removeDayEntry(today, e.id);
              }, '删除这条加餐记录？'),
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
        onTap: e.isPlan
            ? () => _openDetail(context, 'exercise', e.planItemId)
            : () => _openEditDialog(context, e),
        onCheck: e.isPlan
            ? () => context
                .read<RecordProvider>()
                .toggleCheck(today, 'exercise', e.planItemId)
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
  late final TextEditingController _noteCtrl;
  bool _loading = false;
  String? _aiDetail;

  bool get _isEx => widget.entry.kind == 'exercise';
  bool get _isPlan => widget.entry.isPlan;

  @override
  void initState() {
    super.initState();
    _contentCtrl = TextEditingController(text: widget.entry.content);
    _calCtrl =
        TextEditingController(text: widget.entry.calories != null ? '${widget.entry.calories}' : '');
    _noteCtrl = TextEditingController(text: widget.entry.note);
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _calCtrl.dispose();
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
    // 未配置 AI → 先弹配置层，配好后再继续估算
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 测算${_isEx ? '运动消耗' : '这一餐热量'}需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    final ob = context.read<OnboardingProvider>();
    setState(() => _loading = true);
    try {
      final r = _isEx
          ? await _burnNow(settings, usage, ob, desc)
          : await AiService.instance.estimateMeal(settings.ai, desc, onUsage: usage.addUsage);
      if (!mounted) return;
      setState(() {
        _calCtrl.text = '${r['calories']}';
        _aiDetail = r['detail'] as String?;
      });
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
      _noteCtrl.clear();
      _aiDetail = null;
    });
  }

  Future<void> _save({bool checkAfter = false}) async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('请填写${_isEx ? '运动内容' : '食物内容'}，如「黄焖鸡米饭一份」')));
      return;
    }
    final calText = _calCtrl.text.trim();
    int? cal;
    if (calText.isNotEmpty) {
      cal = int.tryParse(calText);
      if (cal == null || cal < 0 || cal > 5000) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('请输入 0-5000 的${_isEx ? '消耗' : '热量'}，留空=待补录')));
        return;
      }
    }
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
      note: _noteCtrl.text.trim(),
      source: old.source,
      planItemId: old.planItemId,
      detached: detachedNow,
      caloriesDirty: dirtyNow,
    );
    await records.updateDayEntry(date, updated);
    if (checkAfter && _isPlan) {
      final keyType = old.kind == 'meal' ? 'meal' : 'exercise';
      if (!records.isChecked(date, keyType, old.planItemId)) {
        await records.toggleCheck(date, keyType, old.planItemId);
      }
    }
    if (mounted) Navigator.pop(context);
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
                    label: Text(_isEx ? 'AI 算消耗' : 'AI 测算'),
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
                    decoration: InputDecoration(
                      hintText: _isEx ? '消耗 kcal' : '热量 kcal',
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
            if (_aiDetail != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('AI 拆解：$_aiDetail',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              ),
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
            if (_canRestore) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _restoreToPlan,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('恢复为计划内容'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSub),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _save(checkAfter: _isPlan ? false : false),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    child: const Text('保存'),
                  ),
                ),
                if (_isPlan) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _save(checkAfter: true),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      child: const Text('保存并打卡'),
                    ),
                  ),
                ],
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
      // F10：按当天生效体重（记录链）+ 个人资料估算
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
    await records.addDayEntry(todayStr(),
        kind: 'exercise', content: name, calories: cal, source: 'manual');
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
