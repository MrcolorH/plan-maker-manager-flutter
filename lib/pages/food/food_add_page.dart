/// 加餐页（对应 food/add.vue）
/// 三种方式：搜索内置食物库 / AI 估算 / 手动录入；添加即计入今日热量缺口（无需打卡）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food_db.dart';
import '../../models/preset_food.dart';
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
  // 搜索
  final TextEditingController _searchCtrl = TextEditingController();
  List<FoodItem> _results = const [];

  // AI 估算
  final TextEditingController _aiDescCtrl = TextEditingController();
  final TextEditingController _aiCalCtrl = TextEditingController();
  final TextEditingController _aiProteinCtrl = TextEditingController();
  final TextEditingController _aiCarbsCtrl = TextEditingController();
  final TextEditingController _aiFatCtrl = TextEditingController();
  bool _aiLoading = false;
  bool _enableThinking = false;
  String? _aiUnit;
  String? _aiName;
  String? _aiDetail;

  // 手动录入
  final TextEditingController _manualNameCtrl = TextEditingController();
  final TextEditingController _manualCalCtrl = TextEditingController();
  final TextEditingController _manualProteinCtrl = TextEditingController();
  final TextEditingController _manualCarbsCtrl = TextEditingController();
  final TextEditingController _manualFatCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _aiDescCtrl.dispose();
    _aiCalCtrl.dispose();
    _aiProteinCtrl.dispose();
    _aiCarbsCtrl.dispose();
    _aiFatCtrl.dispose();
    _manualNameCtrl.dispose();
    _manualCalCtrl.dispose();
    _manualProteinCtrl.dispose();
    _manualCarbsCtrl.dispose();
    _manualFatCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String kw) {
    setState(() => _results = searchFoods(kw));
  }

  Future<void> _addSnack(
    String name,
    int calories,
    String source, {
    int? protein,
    int? carbs,
    int? fat,
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
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已记录：$name（$calories kcal）')));
  }

  Future<void> _applyPreset(PresetFood p) async {
    await _addSnack(
      p.name,
      p.calories,
      'preset',
      protein: p.protein,
      carbs: p.carbs,
      fat: p.fat,
    );
    if (!mounted) return;
    await context.read<PresetProvider>().recordUsed(p.id);
  }

  Future<void> _aiEstimate() async {
    final desc = _aiDescCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先描述吃了什么，如「一杯大杯珍珠奶茶」')));
      return;
    }

    // 优先本地常吃缓存（0 延迟）
    if (!_enableThinking) {
      final presetService = context.read<PresetProvider>().service;
      final cached = presetService.getCachedAiEstimate(desc);
      if (cached != null) {
        setState(() {
          _aiName = cached['name'] as String? ?? desc;
          _aiUnit = cached['unit'] as String?;
          _aiCalCtrl.text = '${cached['calories']}';
          if (cached['protein'] != null) _aiProteinCtrl.text = '${cached['protein']}';
          if (cached['carbs'] != null) _aiCarbsCtrl.text = '${cached['carbs']}';
          if (cached['fat'] != null) _aiFatCtrl.text = '${cached['fat']}';
          _aiDetail = '本地常用知识库命中';
        });
        return;
      }
    }

    // 未配置 AI → 先弹配置层，配好后再继续估算
    final ok = await ensureAiConfigured(
      context,
      message: 'AI 估算热量需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
    );
    if (!ok || !mounted) return;
    setState(() {
      _aiLoading = true;
      _aiUnit = null;
      _aiName = null;
      _aiDetail = null;
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
        _aiName = r['name'] as String?;
        _aiUnit = r['unit'] as String?;
        _aiCalCtrl.text = '${r['calories']}';
        if (r['protein'] != null) _aiProteinCtrl.text = '${r['protein']}';
        if (r['carbs'] != null) _aiCarbsCtrl.text = '${r['carbs']}';
        if (r['fat'] != null) _aiFatCtrl.text = '${r['fat']}';
        final conf = (r['confidence'] as num?) ?? 0;
        _aiDetail = '置信度 ${(conf * 100).round()}%';
      });
      // 成功自动沉淀到本地知识库
      await presetService.setCachedAiEstimate(desc, r);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _confirmAi() async {
    final cal = int.tryParse(_aiCalCtrl.text.trim());
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入 0-5000 的热量')));
      return;
    }
    final name = (_aiName != null && _aiName!.isNotEmpty) ? _aiName! : '加餐';
    final p = int.tryParse(_aiProteinCtrl.text.trim());
    final c = int.tryParse(_aiCarbsCtrl.text.trim());
    final f = int.tryParse(_aiFatCtrl.text.trim());
    await _addSnack(name, cal, 'ai', protein: p, carbs: c, fat: f);
    _aiDescCtrl.clear();
    _aiCalCtrl.clear();
    _aiProteinCtrl.clear();
    _aiCarbsCtrl.clear();
    _aiFatCtrl.clear();
    if (mounted) {
      setState(() {
        _aiName = null;
        _aiUnit = null;
        _aiDetail = null;
      });
    }
  }

  Future<void> _saveAiAsPreset() async {
    final cal = int.tryParse(_aiCalCtrl.text.trim());
    if (cal == null) return;
    final name = (_aiName != null && _aiName!.isNotEmpty) ? _aiName! : _aiDescCtrl.text.trim();
    if (name.isEmpty) return;
    final p = int.tryParse(_aiProteinCtrl.text.trim());
    final c = int.tryParse(_aiCarbsCtrl.text.trim());
    final f = int.tryParse(_aiFatCtrl.text.trim());
    await context.read<PresetProvider>().savePreset(
          name: name,
          calories: cal,
          protein: p,
          carbs: c,
          fat: f,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已存入常吃方案：「$name」')));
  }

  Future<void> _manualAdd() async {
    final name = _manualNameCtrl.text.trim();
    final cal = int.tryParse(_manualCalCtrl.text.trim());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入食物名称')));
      return;
    }
    if (cal == null || cal < 0 || cal > 5000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入 0-5000 的热量')));
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
            const SectionTitle('常用方案（点击一键加餐）'),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final p = presets[i];
                  return GestureDetector(
                    onTap: () => _applyPreset(p),
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
            const SizedBox(height: 10),
          ],

          // ---------- 搜索食物库 ----------
          const SectionTitle('搜食物库'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: '如：香辣鸡腿堡、奶茶、黄焖鸡…',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(fontSize: 13, color: AppColors.chartGray),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (_searchCtrl.text.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('内置约 74 条常见食物（KFC / 麦当劳 / 外卖 / 轻食 / 饮品 / 零食）',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub)),
              ),
            )
          else if (_results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('没搜到？试试下方「AI 估算」或手动录入',
                    style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              ),
            )
          else
            ..._results.map((f) => _foodRow(f)),

          // ---------- AI 估算 ----------
          const SizedBox(height: 10),
          const SectionTitle('AI 估算热量'),
          AppCard(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _aiDescCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: '一句话描述：如「一杯大杯珍珠奶茶全糖」「黄焖鸡米饭大份」',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
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
                        onPressed: _aiLoading ? null : _aiEstimate,
                        icon: _aiLoading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('✨'),
                        label: Text(_enableThinking ? '深度测算' : 'AI 估算'),
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
                if (_aiName != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('$_aiName${_aiUnit != null ? '（$_aiUnit）' : ''}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(width: 8),
                      Text(_aiDetail ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aiCalCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '热量 kcal',
                            filled: true,
                            fillColor: AppColors.bg,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _confirmAi,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                        child: const Text('记录'),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: _saveAiAsPreset,
                        tooltip: '存为常用方案',
                        icon: const Icon(Icons.star_border, color: AppColors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aiProteinCtrl,
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
                          controller: _aiCarbsCtrl,
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
                          controller: _aiFatCtrl,
                          keyboardType: TextInputType.number,
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
              ],
            ),
          ),

          // ---------- 手动录入 ----------
          const SizedBox(height: 10),
          const SectionTitle('手动录入'),
          AppCard(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                TextField(
                  controller: _manualNameCtrl,
                  decoration: const InputDecoration(
                    hintText: '名称',
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
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
                              borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
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
                        controller: _manualCarbsCtrl,
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
                        controller: _manualFatCtrl,
                        keyboardType: TextInputType.number,
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
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('加餐仅记在今天，计入今日热量缺口，不影响整体计划与完成度',
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
          ),
        ],
      ),
    );
  }

  Widget _foodRow(FoodItem f) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('≈${f.calories} kcal / ${f.unit}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _addSnack(f.name, f.calories, 'fooddb'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('＋ 记录', style: TextStyle(fontSize: 12, color: AppColors.primary)),
            ),
          ),
        ],
      ),
    );
  }
}
