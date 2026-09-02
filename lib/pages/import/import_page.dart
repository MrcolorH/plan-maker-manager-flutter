/// 导入计划页（对应 import/import.vue）
/// 两种模式：AI 生成（文档 → JSON）/ 手动 JSON
/// 生成后进入预览：meta 摘要 + 条目可删除/编辑 + 实时统计 → 确认导入（增量合并）
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../providers/plan_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/plan_utils.dart';
import '../../widgets/ai_config_sheet.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String _mode = 'ai'; // ai | manual
  final TextEditingController _docCtrl = TextEditingController();
  final TextEditingController _jsonCtrl = TextEditingController();
  bool _loading = false;

  Map<String, dynamic>? _raw;
  PlanData? _preview;

  bool get _hasPreview => _preview != null;

  @override
  void dispose() {
    _docCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _backToInput() {
    setState(() {
      _raw = null;
      _preview = null;
    });
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  // ---------- AI 生成 ----------

  Future<void> _generate() async {
    final doc = _docCtrl.text.trim();
    if (doc.isEmpty) {
      _showError('请先粘贴计划文档（Markdown / 纯文本 / 聊天记录均可）');
      return;
    }
    // 未配置 AI → 先弹配置层，配好后再继续生成
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 生成计划需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    setState(() => _loading = true);
    try {
      final settings = context.read<SettingsProvider>().settings;
      final usage = context.read<UsageProvider>();
      final raw = await AiService.instance.generatePlan(settings.ai, doc, onUsage: usage.addUsage);
      if (!mounted) return;
      _enterPreview(raw);
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- 手动 JSON ----------

  Future<void> _parseManual() async {
    final text = _jsonCtrl.text.trim();
    if (text.isEmpty) {
      _showError('请先粘贴计划 JSON');
      return;
    }
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) {
        _showError('JSON 根节点必须是对象 { }');
        return;
      }
      _enterPreview(Map<String, dynamic>.from(raw));
    } catch (_) {
      _showError('JSON 格式错误，请检查括号与引号');
    }
  }

  void _enterPreview(Map<String, dynamic> raw) {
    final errs = validateRaw(raw);
    if (errs.isNotEmpty) {
      _showError('校验未通过：\n${errs.join('\n')}');
      return;
    }
    setState(() {
      _raw = raw;
      _preview = normalizePlan(raw);
    });
  }

  // ---------- 预览：编辑 / 删除 ----------

  Future<void> _editMeal(MealItem m) async {
    final nameCtrl = TextEditingController(text: m.name);
    final timeCtrl = TextEditingController(text: m.time);
    final calCtrl = TextEditingController(text: m.calories != null ? '${m.calories}' : '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑餐食', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: '时间 HH:mm')),
              TextField(
                  controller: calCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '热量 kcal（留空=自由餐）')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (saved == true && _preview != null) {
      setState(() {
        m.name = nameCtrl.text.trim().isEmpty ? '未命名' : nameCtrl.text.trim();
        final t = timeCtrl.text.trim();
        if (RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t)) m.time = t;
        final cal = int.tryParse(calCtrl.text.trim());
        m.calories = (cal != null && cal >= 0) ? cal : null;
      });
    }
  }

  Future<void> _editExercise(ExerciseItem e) async {
    final nameCtrl = TextEditingController(text: e.name);
    final timeCtrl = TextEditingController(text: e.time);
    final durCtrl = TextEditingController(text: '${e.duration}');
    final burnCtrl = TextEditingController(text: '${e.caloriesBurned}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑运动', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: '时间 HH:mm')),
              TextField(
                  controller: durCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '时长（分钟）')),
              TextField(
                  controller: burnCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '预计消耗 kcal')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (saved == true && _preview != null) {
      setState(() {
        e.name = nameCtrl.text.trim().isEmpty ? '未命名' : nameCtrl.text.trim();
        final t = timeCtrl.text.trim();
        if (RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t)) e.time = t;
        final dur = int.tryParse(durCtrl.text.trim());
        if (dur != null && dur > 0 && dur <= 600) e.duration = dur;
        final burn = int.tryParse(burnCtrl.text.trim());
        if (burn != null && burn >= 0) e.caloriesBurned = burn;
      });
    }
  }

  Future<void> _confirmImport() async {
    final raw = _raw;
    final plan = _preview;
    if (raw == null || plan == null) return;
    setState(() => _loading = true);
    try {
      await context.read<PlanProvider>().importPlan(raw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已导入：餐食 ${plan.meals.length} 条 · 运动 ${plan.exercises.length} 条（增量合并，记录保留）')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入计划')),
      backgroundColor: AppColors.bg,
      body: _hasPreview ? _previewBody() : _inputBody(),
    );
  }

  Widget _inputBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 模式切换
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.tagBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _segment('✨ AI 生成', 'ai'),
              _segment('手动 JSON', 'manual'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_mode == 'ai') ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('粘贴你的计划文档', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('支持 Markdown / 纯文本 / 聊天记录：早午晚餐、加餐、运动安排，写清楚时间与星期即可。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5)),
                const SizedBox(height: 10),
                TextField(
                  controller: _docCtrl,
                  maxLines: 10,
                  decoration: InputDecoration(
                    hintText: '例：\n早餐 07:30 两个包子+豆浆\n午餐 12:00 冻豆腐虾仁荞麦面…\n周一周三周五 18:30 快走40分钟',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.chartGray),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            _loading ? '生成中（约 10~30 秒）…' : '✨ AI 生成计划',
            onPressed: _loading ? null : _generate,
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('需要先在「设置 → AI 服务」配置 API Key；生成后可在预览中逐条调整',
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
          ),
        ] else ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('粘贴计划 JSON', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('符合 v1.0 格式即可：{ version, meta, meals[], exercises[] }；不含 id 会自动生成。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                const SizedBox(height: 10),
                TextField(
                  controller: _jsonCtrl,
                  maxLines: 12,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '{ "version": "1.0", "meals": [...], "exercises": [...] }',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                    hintStyle: TextStyle(fontSize: 12, color: AppColors.chartGray),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton('校验并预览', onPressed: _loading ? null : _parseManual),
        ],
      ],
    );
  }

  Widget _segment(String label, String mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.primary : AppColors.textSub,
              )),
        ),
      ),
    );
  }

  Widget _previewBody() {
    final plan = _preview!;
    final meta = plan.meta;
    final intake = plan.meals.fold<num>(0, (a, m) => a + (m.calories ?? 0));
    final burn = plan.exercises.fold<num>(0, (a, e) => a + e.caloriesBurned);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('计划预览', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: _loading ? null : _backToInput,
              child: const Text('← 重新输入', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
            ),
          ],
        ),
        // meta 卡
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(meta.planName.isNotEmpty ? meta.planName : '未命名计划',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (meta.startDate.isNotEmpty || meta.endDate.isNotEmpty)
                Text('${meta.startDate} ~ ${meta.endDate}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _miniStat('餐食', '${plan.meals.length}', AppColors.orange),
                  _miniStat('运动', '${plan.exercises.length}', AppColors.primary),
                  _miniStat('预计摄入', '${intake.round()}', AppColors.text),
                  _miniStat('预计消耗', '${burn.round()}', AppColors.text),
                ],
              ),
              if (meta.dailyCalorieTarget != null) ...[
                const SizedBox(height: 6),
                Text('每日目标摄入 ${meta.dailyCalorieTarget!.round()} kcal（导入后写入设置）',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text('导入为增量合并：相同 id 覆盖更新，新条目追加，历史打卡保留',
              style: TextStyle(fontSize: 10, color: AppColors.textSub)),
        ),
        if (plan.meals.isNotEmpty) ...[
          const SectionTitle('餐食（点条目可编辑）'),
          ...plan.meals.map((m) => _mealPreviewRow(m)),
        ],
        if (plan.exercises.isNotEmpty) ...[
          const SectionTitle('运动（点条目可编辑）'),
          ...plan.exercises.map((e) => _exercisePreviewRow(e)),
        ],
        const SizedBox(height: 16),
        PrimaryButton(
          _loading ? '导入中…' : '确认导入',
          onPressed: _loading ? null : _confirmImport,
        ),
      ],
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
        ],
      ),
    );
  }

  Widget _mealPreviewRow(MealItem m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _editMeal(m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Tag(kTypeCn[m.type] ?? m.type, color: 'green'),
                      Text(m.time, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (m.calories != null)
            Text('${m.calories} kcal', style: const TextStyle(fontSize: 12, color: AppColors.orange))
          else
            const Text('自由餐', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          IconButton(
            onPressed: () => setState(() => planRemoveMeal(m.id)),
            icon: const Icon(Icons.close, size: 16, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  void planRemoveMeal(String id) {
    _preview!.meals.removeWhere((m) => m.id == id);
  }

  Widget _exercisePreviewRow(ExerciseItem e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _editExercise(e),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text('${e.time} · ${e.duration} 分钟',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                ],
              ),
            ),
          ),
          Text('≈-${e.caloriesBurned} kcal', style: const TextStyle(fontSize: 12, color: AppColors.primary)),
          IconButton(
            onPressed: () => setState(() => planRemoveExercise(e.id)),
            icon: const Icon(Icons.close, size: 16, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  void planRemoveExercise(String id) {
    _preview!.exercises.removeWhere((e) => e.id == id);
  }
}
