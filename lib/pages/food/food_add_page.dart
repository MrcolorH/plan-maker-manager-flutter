/// 加餐页（对应 food/add.vue）
/// 1.0.4 重构：
/// 1. 常用方案支持长按删除、点击份量选择弹层（防误触）；
/// 2. 独立食物库合入智能估算引擎：优先端侧食物库秒级匹配+份量换算，支持以 AI 重新估算，未命中无感走大模型；
/// 3. 用户采纳/存为常用方案时，自动归一化萃取单位热量沉淀入本地食物库。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food_db.dart';
import '../../models/preset_food.dart';
import '../../models/records.dart';
import '../../providers/preset_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/ai_config_sheet.dart';

class FoodAddPage extends StatefulWidget {
  const FoodAddPage({super.key});

  @override
  State<FoodAddPage> createState() => _FoodAddPageState();
}

class _FoodAddPageState extends State<FoodAddPage> {
  // 智能估算输入与结果
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _calCtrl = TextEditingController();
  final TextEditingController _proteinCtrl = TextEditingController();
  final TextEditingController _carbsCtrl = TextEditingController();
  final TextEditingController _fatCtrl = TextEditingController();
  bool _loading = false;
  bool _enableThinking = false;
  String? _resName;
  String? _resUnit;
  String? _resDetail;
  String? _resSource; // '内置食物库' | '自定义食物库' | 'AI 大模型测算'
  bool _isMatchedFromDb = false;
  List<FoodBreakdownItem>? _resItems;

  // 手动录入
  final TextEditingController _manualNameCtrl = TextEditingController();
  final TextEditingController _manualCalCtrl = TextEditingController();
  final TextEditingController _manualProteinCtrl = TextEditingController();
  final TextEditingController _manualCarbsCtrl = TextEditingController();
  final TextEditingController _manualFatCtrl = TextEditingController();

  @override
  void dispose() {
    _descCtrl.dispose();
    _calCtrl.dispose();
    _proteinCtrl.dispose();
    _carbsCtrl.dispose();
    _fatCtrl.dispose();
    _manualNameCtrl.dispose();
    _manualCalCtrl.dispose();
    _manualProteinCtrl.dispose();
    _manualCarbsCtrl.dispose();
    _manualFatCtrl.dispose();
    super.dispose();
  }

  Future<void> _addSnack(
    String name,
    int calories,
    String source, {
    int? protein,
    int? carbs,
    int? fat,
    String? detail,
    List<FoodBreakdownItem>? items,
  }) async {
    await context.read<RecordProvider>().addDayEntry(
          todayStr(),
          kind: 'meal',
          slot: 'snack',
          content: name,
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
          source: source,
          detail: detail,
          items: items,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已记录：$name（$calories kcal）')));
  }

  // ---------- 常用方案：份量选择与长按管理 ----------

  void _showPresetPortionSheet(PresetFood p) {
    double portion = 1.0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final curCal = (p.calories * portion).round();
            final curP = p.protein != null ? (p.protein! * portion).round() : null;
            final curC = p.carbs != null ? (p.carbs! * portion).round() : null;
            final curF = p.fat != null ? (p.fat! * portion).round() : null;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.restaurant, size: 18, color: AppColors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '基准：${p.calories} kcal / ${p.unit.isNotEmpty ? p.unit : '1份'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('选择份量：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(
                        portion == 1.0 ? '1 份' : '${portion.toStringAsFixed(1)} 份',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [0.5, 1.0, 1.5, 2.0].map((val) {
                      final selected = (portion - val).abs() < 0.05;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton(
                            onPressed: () => setSheetState(() => portion = val),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected ? AppColors.orange.withValues(alpha: 0.1) : Colors.white,
                              side: BorderSide(
                                color: selected ? AppColors.orange : const Color(0xFFE2E2DC),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: Text(
                              '${val == 1.0 ? '1' : val == 2.0 ? '2' : val}份',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                                color: selected ? AppColors.orange : AppColors.text,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        onPressed: portion > 0.5 ? () => setSheetState(() => portion = (portion - 0.5).clamp(0.5, 5.0)) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Expanded(
                        child: Slider(
                          value: portion,
                          min: 0.5,
                          max: 4.0,
                          divisions: 7,
                          activeColor: AppColors.orange,
                          onChanged: (v) => setSheetState(() => portion = v),
                        ),
                      ),
                      IconButton(
                        onPressed: portion < 4.0 ? () => setSheetState(() => portion = (portion + 0.5).clamp(0.5, 5.0)) : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '实际折算：$curCal kcal',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                        if (curP != null || curC != null || curF != null)
                          Text(
                            'P:${curP ?? 0}g  C:${curC ?? 0}g  F:${curF ?? 0}g',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final presetProv = context.read<PresetProvider>();
                        Navigator.pop(ctx);
                        final displayName = portion == 1.0 ? p.name : '${p.name} (${portion.toStringAsFixed(1)}份)';
                        await _addSnack(
                          displayName,
                          curCal,
                          'preset',
                          protein: curP,
                          carbs: curC,
                          fat: curF,
                        );
                        await presetProv.recordUsed(p.id);
                      },
                      child: Text('＋ 确认记录（$curCal kcal）', style: const TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPresetManageSheet(PresetFood p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.settings, size: 18, color: AppColors.textSub),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '常用方案管理：${p.name}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.danger),
                title: const Text('删除该常用方案', style: TextStyle(color: AppColors.danger, fontSize: 14)),
                subtitle: const Text('从常用快捷条中移除', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await context.read<PresetProvider>().deletePreset(p.id);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除常用方案：「${p.name}」')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, color: AppColors.textSub),
                title: const Text('取消', style: TextStyle(fontSize: 14)),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---------- 智能估算引擎（食物库匹配优先 + AI 兜底） ----------

  Future<void> _smartEstimate({bool forceAi = false}) async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入吃了什么，如「半个香辣鸡腿堡」「200g米饭」')),
      );
      return;
    }

    // 1. 若非强制 AI 且未开启深度思考，优先本地食物库秒级匹配与份量折算（0 网络延迟）
    if (!forceAi && !_enableThinking) {
      final userFoods = context.read<PresetProvider>().userFoods;
      final match = matchAndCalculateFood(desc, userFoods: userFoods);
      if (match != null) {
        setState(() {
          _resName = match.food.name;
          _resUnit = match.quantityText;
          _calCtrl.text = '${match.totalCalories}';
          if (match.totalProtein != null) _proteinCtrl.text = '${match.totalProtein}';
          if (match.totalCarbs != null) _carbsCtrl.text = '${match.totalCarbs}';
          if (match.totalFat != null) _fatCtrl.text = '${match.totalFat}';
          _resSource = match.isUserCustom
              ? '自定义食物库'
              : (match.calculationDetail.contains(' + ') ? '食物库组合' : '内置食物库');
          _resDetail = match.calculationDetail;
          _resItems = match.breakdownItems;
          _isMatchedFromDb = true;
        });
        return;
      }
    }

    // 2. 食物库未命中 或 用户主动要求以 AI 重新估算 → 调大模型
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 估算热量需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;

    setState(() {
      _loading = true;
      _resUnit = null;
      _resName = null;
      _resDetail = null;
      _resSource = null;
      _resItems = null;
      _isMatchedFromDb = false;
    });

    try {
      final settings = context.read<SettingsProvider>().settings;
      final usage = context.read<UsageProvider>();
      final presetService = context.read<PresetProvider>().service;
      final r = await AiService.instance.queryCalorie(
        settings.ai,
        desc,
        enableThinking: _enableThinking,
        onUsage: usage.addUsage,
      );
      if (!mounted) return;
      setState(() {
        _resName = r['name'] as String?;
        _resUnit = r['unit'] as String?;
        _calCtrl.text = '${r['calories']}';
        if (r['protein'] != null) _proteinCtrl.text = '${r['protein']}';
        if (r['carbs'] != null) _carbsCtrl.text = '${r['carbs']}';
        if (r['fat'] != null) _fatCtrl.text = '${r['fat']}';
        final conf = (r['confidence'] as num?) ?? 0;
        final detailText = (r['detail'] as String?)?.trim();
        _resSource = 'AI 大模型测算';
        _resDetail = (detailText != null && detailText.isNotEmpty)
            ? 'AI 拆解：$detailText'
            : '置信度 ${(conf * 100).round()}%';
        _resItems = AiService.parseBreakdownFromText(detailText);
        _isMatchedFromDb = false;
      });
      // 成功自动沉淀为 AI 缓存
      await presetService.setCachedAiEstimate(desc, r);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmSmart() async {
    final cal = int.tryParse(_calCtrl.text.trim());
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入 0-5000 的有效热量')));
      return;
    }
    final name = (_resName != null && _resName!.isNotEmpty) ? _resName! : _descCtrl.text.trim();
    final p = int.tryParse(_proteinCtrl.text.trim());
    final c = int.tryParse(_carbsCtrl.text.trim());
    final f = int.tryParse(_fatCtrl.text.trim());
    final displayName = _resUnit != null ? '$name ($_resUnit)' : name;

    await _addSnack(
      displayName,
      cal,
      _isMatchedFromDb ? 'fooddb' : 'ai',
      protein: p,
      carbs: c,
      fat: f,
      detail: _resDetail,
      items: _resItems,
    );

    _descCtrl.clear();
    _calCtrl.clear();
    _proteinCtrl.clear();
    _carbsCtrl.clear();
    _fatCtrl.clear();
    if (mounted) {
      setState(() {
        _resName = null;
        _resUnit = null;
        _resDetail = null;
        _resSource = null;
        _resItems = null;
        _isMatchedFromDb = false;
      });
    }
  }

  /// 存为常用方案（同时沉淀单位热量至用户自定义食物库）
  Future<void> _saveSmartAsPreset() async {
    final cal = int.tryParse(_calCtrl.text.trim());
    if (cal == null) return;
    final name = (_resName != null && _resName!.isNotEmpty) ? _resName! : _descCtrl.text.trim();
    if (name.isEmpty) return;
    final p = int.tryParse(_proteinCtrl.text.trim());
    final c = int.tryParse(_carbsCtrl.text.trim());
    final f = int.tryParse(_fatCtrl.text.trim());

    await context.read<PresetProvider>().savePreset(
          name: name,
          calories: cal,
          protein: p,
          carbs: c,
          fat: f,
          unit: _resUnit ?? '份',
          syncToFoodDb: true,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已存入常用方案并沉淀至食物库：「$name」')),
    );
  }

  // ---------- 手动录入 ----------

  Future<void> _manualAdd() async {
    final name = _manualNameCtrl.text.trim();
    final cal = int.tryParse(_manualCalCtrl.text.trim());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入食物名称')));
      return;
    }
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入 0-5000 的热量')));
      return;
    }
    final p = int.tryParse(_manualProteinCtrl.text.trim());
    final c = int.tryParse(_manualCarbsCtrl.text.trim());
    final f = int.tryParse(_manualFatCtrl.text.trim());
    await _addSnack(name, cal, 'manual', protein: p, carbs: c, fat: f);
    _manualNameCtrl.clear();
    _manualCalCtrl.clear();
    _manualProteinCtrl.clear();
    _manualCarbsCtrl.clear();
    _manualFatCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetProvider>().presets;

    return Scaffold(
      appBar: AppBar(title: const Text('今日加餐')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ---------- 常用预设方案快捷条 ----------
          if (presets.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionTitle('常用方案'),
                Text(
                  '点选加餐 · 长按删除',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub.withValues(alpha: 0.8)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final p = presets[i];
                  return GestureDetector(
                    onTap: () => _showPresetPortionSheet(p),
                    onLongPress: () => _showPresetManageSheet(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: const Color(0xFFE2E2DC)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: AppColors.orange),
                          const SizedBox(width: 4),
                          Text(p.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 4),
                          Text('${p.calories}k', style: const TextStyle(fontSize: 11, color: AppColors.orange)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ---------- 智能估算热量（集成食物库+AI） ----------
          Row(
            children: [
              const SectionTitle('智能加餐估算'),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('食物库秒搜 + AI', style: TextStyle(fontSize: 10, color: AppColors.orange)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '描述吃的食物与份量：如「半个香辣鸡腿堡」「200g白米饭」「黄焖鸡米饭小份」',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.all(10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : () => _smartEstimate(forceAi: false),
                        icon: _loading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('✨'),
                        label: Text(_enableThinking ? '深度测算' : '智能估算'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.orange,
                          side: const BorderSide(color: AppColors.orange),
                          minimumSize: const Size.fromHeight(40),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _enableThinking = !_enableThinking),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: _enableThinking ? AppColors.orange.withValues(alpha: 0.12) : AppColors.tagBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _enableThinking ? AppColors.orange : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.psychology, size: 16, color: _enableThinking ? AppColors.orange : AppColors.textSub),
                            const SizedBox(width: 3),
                            Text('深度思考', style: TextStyle(fontSize: 12, color: _enableThinking ? AppColors.orange : AppColors.textSub)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // 估算结果卡片展示
                if (_resName != null) ...[
                  const SizedBox(height: 12),
                  // 来源徽标与换算详情
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isMatchedFromDb
                          ? AppColors.primary.withValues(alpha: 0.06)
                          : AppColors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isMatchedFromDb
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.orange.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _isMatchedFromDb ? AppColors.primary : AppColors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _resSource ?? '测算结果',
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$_resName${_resUnit != null ? '（$_resUnit）' : ''}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (_resDetail != null && _resDetail!.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            _resDetail!,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.4),
                          ),
                        ],
                        // 若来自食物库秒配，提示用户是否仍需以 AI 测算
                        if (_isMatchedFromDb) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              InkWell(
                                onTap: () => _smartEstimate(forceAi: true),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh, size: 12, color: AppColors.orange),
                                    SizedBox(width: 2),
                                    Text(
                                      '仍需以 AI 重新估算？',
                                      style: TextStyle(fontSize: 11, color: AppColors.orange, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _calCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '热量 kcal',
                            filled: true,
                            fillColor: AppColors.bg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _confirmSmart,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('记录'),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _saveSmartAsPreset,
                        tooltip: '存为常用方案并沉淀至食物库',
                        icon: const Icon(Icons.star_border, color: AppColors.orange),
                      ),
                    ],
                  ),
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
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                              borderSide: BorderSide.none,
                            ),
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
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                              borderSide: BorderSide.none,
                            ),
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
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '脂肪 g',
                            filled: true,
                            fillColor: AppColors.bg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(8)),
                              borderSide: BorderSide.none,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.all(8),
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ---------- 手动录入 ----------
          const SizedBox(height: 14),
          const SectionTitle('手动录入'),
          const SizedBox(height: 6),
          AppCard(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                TextField(
                  controller: _manualNameCtrl,
                  decoration: const InputDecoration(
                    hintText: '食物名称',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.all(10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualCalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '热量 kcal',
                          filled: true,
                          fillColor: AppColors.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.all(10),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _manualAdd,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualProteinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '蛋白质 g',
                          filled: true,
                          fillColor: AppColors.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _manualCarbsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '碳水 g',
                          filled: true,
                          fillColor: AppColors.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _manualFatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '脂肪 g',
                          filled: true,
                          fillColor: AppColors.bg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.all(8),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '加餐仅记在今天，计入今日热量缺口，不影响整体计划与完成度',
              style: TextStyle(fontSize: 11, color: AppColors.textSub),
            ),
          ),
        ],
      ),
    );
  }
}
