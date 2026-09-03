/// 加餐页（对应 food/add.vue）
/// 三种方式：搜索内置食物库 / AI 估算 / 手动录入；添加即计入今日热量缺口（无需打卡）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food_db.dart';
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
  bool _aiLoading = false;
  String? _aiUnit;
  String? _aiName;
  String? _aiDetail;

  // 手动录入
  final TextEditingController _manualNameCtrl = TextEditingController();
  final TextEditingController _manualCalCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _aiDescCtrl.dispose();
    _aiCalCtrl.dispose();
    _manualNameCtrl.dispose();
    _manualCalCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String kw) {
    setState(() => _results = searchFoods(kw));
  }

  Future<void> _addSnack(String name, int calories, String source) async {
    await context.read<RecordProvider>().addDayEntry(
          todayStr(),
          kind: 'meal',
          slot: 'snack',
          content: name,
          calories: calories,
          source: source,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已记录：$name（$calories kcal）')));
  }

  Future<void> _aiEstimate() async {
    final desc = _aiDescCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先描述吃了什么，如「一杯大杯珍珠奶茶」')));
      return;
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
      final r = await AiService.instance.queryCalorie(settings.ai, desc, onUsage: usage.addUsage);
      if (!mounted) return;
      setState(() {
        _aiName = r['name'] as String?;
        _aiUnit = r['unit'] as String?;
        _aiCalCtrl.text = '${r['calories']}';
        final conf = (r['confidence'] as num?) ?? 0;
        _aiDetail = '置信度 ${(conf * 100).round()}%';
      });
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
    await _addSnack(name, cal, 'ai');
    _aiDescCtrl.clear();
    _aiCalCtrl.clear();
    if (mounted) {
      setState(() {
        _aiName = null;
        _aiUnit = null;
        _aiDetail = null;
      });
    }
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
    await _addSnack(name, cal, 'manual');
    _manualNameCtrl.clear();
    _manualCalCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今日加餐')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
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
                OutlinedButton.icon(
                  onPressed: _aiLoading ? null : _aiEstimate,
                  icon: _aiLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('✨'),
                  label: const Text('AI 估算'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    side: const BorderSide(color: AppColors.orange),
                    minimumSize: const Size.fromHeight(40),
                  ),
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
                            hintText: '热量 kcal（可修改）',
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
