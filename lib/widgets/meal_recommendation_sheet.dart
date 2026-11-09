/// AI 实时饮食与运动推荐弹层（依据时间、剩余热量缺口及宏量营养素）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/onboarding.dart';
import '../models/records.dart';
import '../models/settings.dart';
import '../models/nearby_store.dart';
import '../providers/onboarding_provider.dart';
import '../providers/plan_provider.dart';
import '../providers/record_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/usage_provider.dart';
import '../services/ai_service.dart';
import '../services/nearby_service.dart';
import '../theme/app_theme.dart';
import '../utils/calorie_utils.dart';
import '../utils/date_utils.dart';
import 'ai_config_sheet.dart';

/// 弹出饮食与运动推荐底部弹层
Future<void> showMealRecommendationSheet(BuildContext context) async {
  final ok = await ensureAiConfigured(
    context,
    title: '未配置 AI 服务',
    message: '智能饮食推荐需要连接 AI 服务（DeepSeek / Gemini 等），请先完成配置。',
  );
  if (!ok || !context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const MealRecommendationSheet(),
  );
}

class MealRecommendationSheet extends StatefulWidget {
  const MealRecommendationSheet({super.key});

  @override
  State<MealRecommendationSheet> createState() => _MealRecommendationSheetState();
}

class _MealRecommendationSheetState extends State<MealRecommendationSheet> {
  bool _isLoading = false;
  bool _isLocating = false;
  String? _error;
  MealRecommendationResult? _result;
  final Set<String> _addedOptionKeys = {}; // 记录已采纳添加到今日的选项，防止重复点击
  List<NearbyStore> _nearbyStores = [];

  // 餐饮倾向: 'dine_out' (去店里吃) | 'takeout' (外卖) | 'cook' (自己做) | 'all' (不限)
  String _mealPreference = 'dine_out';
  final TextEditingController _ingredientsCtrl = TextEditingController();
  final TextEditingController _targetStoresCtrl = TextEditingController();
  final TextEditingController _deliveryCtrl = TextEditingController();

  // 备选项展开/收起控制（默认收起备选项，节省视觉空间）
  bool _showIngredientsOptions = false;
  bool _showDeliveryOptions = false;
  bool _showStoreOptions = false;
  bool _isCookPanelExpanded = true;
  bool _isTakeoutPanelExpanded = true;
  bool _isDineOutPanelExpanded = true;

  static const List<String> _kCommonIngredients = [
    '鸡蛋', '黄瓜', '西红柿', '鸡胸肉', '西兰花',
    '老豆腐', '即食燕麦', '冷米饭', '虾仁', '纯牛奶',
    '生菜', '洋葱', '瘦牛肉', '紫薯', '魔芋爽'
  ];

  static const List<String> _kCommonStores = [
    '肯德基 (KFC)', '麦当劳', '黄焖鸡米饭', '兰州牛肉面',
    '大米先生/自选快餐', '老乡鸡', '沙县小吃', '赛百味',
    '便利店(711/全家)', '清汤麻辣烫/米线'
  ];

  static const List<String> _kDeliveryKeywords = [
    '老乡鸡/大米先生', '轻食沙拉/波奇碗', '赛百味减脂卷', '麻辣烫(清汤自选)',
    '自选中式快餐', '牛肉面/清汤捞面', '日料轻食/刺身便当', '馄饨水饺'
  ];

  @override
  void initState() {
    super.initState();
    // 关键体验：去店里吃和点外卖自动根据剩余热量进行推荐，解决不知道吃啥的问题；
    // 自己做则先等待用户挑选现有食材再点击推荐。
    if (_mealPreference == 'dine_out') {
      _initDineOut();
    } else if (_mealPreference == 'takeout' || _mealPreference == 'all') {
      _fetchRecommendation();
    }
  }

  @override
  void dispose() {
    _ingredientsCtrl.dispose();
    _targetStoresCtrl.dispose();
    _deliveryCtrl.dispose();
    super.dispose();
  }

  /// 初始化去店里吃：并行探测真实周边店铺与启动推荐
  Future<void> _initDineOut() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final stores = await NearbyService.instance.searchNearbyRestaurants();
      if (mounted) {
        setState(() {
          _nearbyStores = stores;
          _isLocating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }

    if (mounted) {
      _fetchRecommendation();
    }
  }

  /// 手动重新定位探测周边实体店铺
  Future<void> _refreshNearbyStores() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final stores = await NearbyService.instance.searchNearbyRestaurants();
      if (mounted) {
        setState(() {
          _nearbyStores = stores;
          _isLocating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _fetchRecommendation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final settings = context.read<SettingsProvider>().settings;
    final plan = context.read<PlanProvider>().plan;
    final records = context.read<RecordProvider>();
    final profile = context.read<OnboardingProvider>().state.profile;
    final today = todayStr();
    final summary = dailySummary(plan, settings, records.store, today, profile: profile);
    final entries = records.store.dayEntries[today] ?? const <DayEntry>[];

    // 如果是去店里吃且用户未手动指定，优先注入周边真实探测到的前 5 家店铺及距离
    String targetStoresText = _targetStoresCtrl.text.trim();
    if (targetStoresText.isEmpty && _nearbyStores.isNotEmpty && _mealPreference == 'dine_out') {
      targetStoresText = _nearbyStores.take(6).map((s) => s.displayTag).join(', ');
    }

    final contextText = buildRecommendationContext(
      summary: summary,
      entries: entries,
      now: DateTime.now(),
      targetDeficit: 400,
      profile: profile,
      mealPreference: _mealPreference,
      availableIngredients: _ingredientsCtrl.text.trim(),
      targetStores: targetStoresText,
      deliveryKeywords: _deliveryCtrl.text.trim(),
    );

    try {
      final res = await AiService.instance.recommendMeals(
        settings.ai,
        contextText,
        onUsage: (u) {
          try {
            context.read<UsageProvider>().addUsage(u);
          } catch (_) {}
        },
      );
      if (mounted) {
        setState(() {
          _result = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  /// 一键采纳加入今日餐食
  Future<void> _adoptMealOption(MealSlotPlan plan, MealOption opt) async {
    final key = '${plan.slotKey}:${opt.name}';
    if (_addedOptionKeys.contains(key)) return;

    final today = todayStr();
    final timeStr = nowTimeStr();

    await context.read<RecordProvider>().addDayEntry(
      today,
      kind: 'meal',
      content: opt.name,
      calories: opt.calories,
      protein: opt.protein > 0 ? opt.protein : null,
      carbs: opt.carbs > 0 ? opt.carbs : null,
      fat: opt.fat > 0 ? opt.fat : null,
      slot: plan.slotKey.isNotEmpty ? plan.slotKey : 'snack',
      time: timeStr,
      note: 'AI推荐采纳（${opt.scene}）：${opt.reason}',
      source: 'ai',
      detail: '${opt.name} 预估热量 ${opt.calories} kcal（P:${opt.protein}g C:${opt.carbs}g F:${opt.fat}g）',
      autoCheck: true,
    );

    if (mounted) {
      setState(() {
        _addedOptionKeys.add(key);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将「${opt.name}」加入今日${plan.timeSlot}打卡！'),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 一键采纳加入今日运动
  Future<void> _adoptExerciseOption(ExerciseAdvice advice) async {
    final key = 'exercise:${advice.burnCalories}';
    if (_addedOptionKeys.contains(key)) return;

    final today = todayStr();
    final timeStr = nowTimeStr();

    await context.read<RecordProvider>().addDayEntry(
      today,
      kind: 'exercise',
      content: advice.suggestion,
      calories: advice.burnCalories,
      time: timeStr,
      note: 'AI推荐运动建议',
      source: 'ai',
      detail: advice.suggestion,
      autoCheck: true,
    );

    if (mounted) {
      setState(() {
        _addedOptionKeys.add(key);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加运动「${advice.suggestion}」至今日打卡！'),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 复制推荐内容
  void _copyRecommendation() {
    if (_result == null) return;
    final sb = StringBuffer();
    sb.writeln('【AI 饮食与运动剩余规划】');
    sb.writeln(_result!.summary);
    if (_result!.macroFocus.isNotEmpty) {
      sb.writeln('营养侧重：${_result!.macroFocus}');
    }
    sb.writeln('');
    for (final p in _result!.plans) {
      sb.writeln('■ ${p.timeSlot}（建议预算：${p.recommendedCalories} kcal）');
      for (final opt in p.options) {
        sb.writeln('  · [${opt.scene}] ${opt.name} - ${opt.calories}kcal (P:${opt.protein}g C:${opt.carbs}g F:${opt.fat}g)');
        if (opt.reason.isNotEmpty) sb.writeln('    理由：${opt.reason}');
      }
      sb.writeln('');
    }
    if (_result!.exerciseAdvice != null && _result!.exerciseAdvice!.suggestion.isNotEmpty) {
      sb.writeln('■ 运动弹性建议：');
      sb.writeln('  · ${_result!.exerciseAdvice!.suggestion}（消耗约 ${_result!.exerciseAdvice!.burnCalories} kcal）');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制推荐建议到剪切板'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部把手与标题
            _buildHeader(context),
            // 最近一餐就餐倾向与现有食材控制栏
            _buildPreferenceBar(context),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            // 主体内容区
            Expanded(
              child: _isLoading
                  ? _buildLoading()
                  : _error != null
                      ? _buildError()
                      : _result == null
                          ? _buildEmptyGuide(context)
                          : _buildContent(),
            ),

            // 底部动作栏
            if (!_isLoading && _result != null) _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.primaryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.restaurant_menu_rounded, size: 20, color: context.primaryColor),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 饮食参谋 · 剩余规划',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '结合当前时刻、已摄入与保底 ≥400 kcal 缺口',
                      style: TextStyle(fontSize: 11, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22, color: AppColors.textSub),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(context.primaryColor),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '正在根据当前时间（$timeStr）测算...',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
            const SizedBox(height: 8),
            const Text(
              '营养师正在计算剩余可用配额、宏量营养查漏，并预留 ≥400 kcal 缺口...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            const Text('推荐生成失败', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _error ?? '网络或服务异常',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => showAiConfigSheet(context),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('检查配置'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _fetchRecommendation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final res = _result!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        // 顶部核心概况卡片
        _buildSummaryCard(res),
        const SizedBox(height: 16),

        // 分时段餐食推荐
        for (final plan in res.plans) ...[
          _buildPlanSlotCard(plan),
          const SizedBox(height: 14),
        ],

        // 运动弹性建议（若有）
        if (res.exerciseAdvice != null && res.exerciseAdvice!.suggestion.isNotEmpty) ...[
          _buildExerciseCard(res.exerciseAdvice!),
          const SizedBox(height: 14),
        ],

        // 底部温和免责提示
        Center(
          child: Text(
            '💡 减脂建议仅供参考，请根据个人饱腹感与身体反馈灵活调整',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(MealRecommendationResult res) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.primaryColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      '已锁定保底 ≥400 kcal 缺口',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (res.remainingCalorieBudget > 0)
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                    children: [
                      const TextSpan(text: '余可用 '),
                      TextSpan(
                        text: '${res.remainingCalorieBudget}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.primaryColor,
                        ),
                      ),
                      const TextSpan(text: ' kcal'),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            res.summary,
            style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
          if (res.macroFocus.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.track_changes_rounded, size: 14, color: AppColors.orange),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    res.macroFocus,
                    style: const TextStyle(fontSize: 12, color: AppColors.orange, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanSlotCard(MealSlotPlan plan) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：时段名 + 建议预算
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(_getSlotIcon(plan.slotKey), size: 18, color: context.primaryColor),
                const SizedBox(width: 8),
                Text(
                  plan.timeSlot,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '预算约 ${plan.recommendedCalories} kcal',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSub),
                  ),
                ),
              ],
            ),
          ),
          // 选项清单
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (var i = 0; i < plan.options.length; i++) ...[
                  if (i > 0) const Divider(height: 18, color: Color(0xFFF2F2F2)),
                  _buildOptionItem(plan, plan.options[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem(MealSlotPlan plan, MealOption opt) {
    final key = '${plan.slotKey}:${opt.name}';
    final records = context.watch<RecordProvider>();
    final today = todayStr();
    final todayEntries = records.store.dayEntries[today] ?? const <DayEntry>[];
    final existsInToday = todayEntries.any((e) => e.content == opt.name);
    final isAdopted = existsInToday || _addedOptionKeys.contains(key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getSceneBadgeColor(opt.scene).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                opt.scene,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _getSceneBadgeColor(opt.scene),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                opt.name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${opt.calories} kcal',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.primaryColor,
              ),
            ),
          ],
        ),
        if (opt.protein > 0 || opt.carbs > 0 || opt.fat > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              _buildMacroSmall('蛋', '${opt.protein}g', const Color(0xFF4CAF50)),
              const SizedBox(width: 6),
              _buildMacroSmall('碳', '${opt.carbs}g', const Color(0xFF2196F3)),
              const SizedBox(width: 6),
              _buildMacroSmall('脂', '${opt.fat}g', const Color(0xFFFF9800)),
            ],
          ),
        ],
        if (opt.reason.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            opt.reason,
            style: const TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.35),
          ),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: isAdopted ? null : () => _adoptMealOption(plan, opt),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isAdopted ? Colors.grey.shade100 : context.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isAdopted ? Colors.grey.shade300 : context.primaryColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isAdopted ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                    size: 13,
                    color: isAdopted ? AppColors.textSub : context.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isAdopted ? '已加入今日' : '采纳加入今日',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isAdopted ? AppColors.textSub : context.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExerciseCard(ExerciseAdvice advice) {
    final key = 'exercise:${advice.burnCalories}';
    final records = context.watch<RecordProvider>();
    final today = todayStr();
    final todayEntries = records.store.dayEntries[today] ?? const <DayEntry>[];
    final existsInToday = todayEntries.any((e) => e.content == advice.suggestion);
    final isAdopted = existsInToday || _addedOptionKeys.contains(key);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE0B2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_run_rounded, size: 18, color: Color(0xFFE65100)),
              const SizedBox(width: 6),
              const Text(
                '运动调节弹性方案（非强制）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
              ),
              const Spacer(),
              if (advice.burnCalories > 0)
                Text(
                  '+${advice.burnCalories} kcal 消耗',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            advice.suggestion,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.4),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: isAdopted ? null : () => _adoptExerciseOption(advice),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isAdopted ? Colors.grey.shade200 : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isAdopted ? Colors.grey.shade300 : const Color(0xFFFFB74D)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAdopted ? Icons.check_circle_rounded : Icons.fitness_center_rounded,
                      size: 13,
                      color: isAdopted ? AppColors.textSub : const Color(0xFFE65100),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isAdopted ? '已加入运动' : '采纳此运动',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isAdopted ? AppColors.textSub : const Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroSmall(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(width: 2),
          Text(value, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _copyRecommendation,
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制方案'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _fetchRecommendation,
              icon: const Icon(Icons.autorenew_rounded, size: 18),
              label: const Text('换一批方案'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyGuide(BuildContext context) {
    final settings = context.read<SettingsProvider>().settings;
    final plan = context.read<PlanProvider>().plan;
    final records = context.read<RecordProvider>();
    final profile = context.read<OnboardingProvider>().state.profile;
    final today = todayStr();
    final summary = dailySummary(plan, settings, records.store, today, profile: profile);
    final remainingBudget = (summary.burn - summary.intake - 400).round();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.primaryColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.restaurant_rounded, size: 40, color: context.primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              _mealPreference == 'cook' ? '🍳 准备自己做减脂餐' : '准备好规划下一餐了吗？',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              '当前已锁定保底 ≥400 kcal 缺口\n今日剩余可用摄入预算约为 ${remainingBudget > 0 ? remainingBudget : 0} kcal',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt_rounded, size: 16, color: AppColors.orange),
                      const SizedBox(width: 4),
                      Text(
                        _mealPreference == 'cook' ? '库存食材优先利用' : '智能减脂参谋',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _mealPreference == 'cook'
                        ? '请在上方勾选或手输你手头现有的食材（如鸡蛋、剩饭、黄瓜、鸡胸肉等）。\nAI 将优先利用你的库存食材，为你设计控油控盐的快手减脂餐。'
                        : '• 🏬 去店里吃：已自动探测周边真实店铺，按剩余热量自动推荐怎么吃不超标\n'
                            '• 🛵 点外卖：已自动按外卖热搜品类推荐高分低卡搭配与神仙备注\n'
                            '• 🍳 自己做：先选食材后点击生成，把家里现有食材变身减脂大餐',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _mealPreference == 'cook' ? '⚡ 优先用现有食材生成减脂规划' : '⚡ 生成专属减脂规划',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                onPressed: _fetchRecommendation,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceBar(BuildContext context) {
    final themeColor = context.primaryColor;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '最近一餐就餐倾向：',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text),
              ),
              const Spacer(),
              if (_mealPreference == 'cook' && _ingredientsCtrl.text.isNotEmpty)
                Text(
                  '已选现有食材',
                  style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.bold),
                )
              else if (_mealPreference == 'takeout' && _deliveryCtrl.text.isNotEmpty)
                const Text(
                  '已设外卖偏好',
                  style: TextStyle(fontSize: 11, color: Color(0xFF1976D2), fontWeight: FontWeight.bold),
                )
              else if (_mealPreference == 'dine_out' && _targetStoresCtrl.text.isNotEmpty)
                const Text(
                  '已选周边店铺',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8E24AA), fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 4 个就餐倾向选择卡
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPrefChip('🍳 自己做', 'cook'),
                _buildPrefChip('🛵 点外卖', 'takeout'),
                _buildPrefChip('🏬 去店里吃', 'dine_out'),
                _buildPrefChip('✨ 全部推荐', 'all'),
              ],
            ),
          ),
          // 自己做时，展开手头现有食材输入与快捷标签（支持折叠，默认收起备选项）
          if (_mealPreference == 'cook') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: themeColor.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isCookPanelExpanded = !_isCookPanelExpanded),
                    child: Row(
                      children: [
                        Icon(Icons.kitchen_rounded, size: 16, color: themeColor),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '输入现有食材（优先用已有食材做减脂餐）：',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                          ),
                        ),
                        if (_ingredientsCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              setState(() => _ingredientsCtrl.clear());
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text('清空', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                            ),
                          ),
                        Icon(
                          _isCookPanelExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textSub,
                        ),
                      ],
                    ),
                  ),
                  if (_isCookPanelExpanded) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _ingredientsCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '如：鸡蛋、黄瓜、剩饭、西红柿、鸡胸肉...',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onSubmitted: (_) => _fetchRecommendation(),
                    ),
                    const SizedBox(height: 6),
                    // 备选项折叠/展开栏（默认收起）
                    InkWell(
                      onTap: () => setState(() => _showIngredientsOptions = !_showIngredientsOptions),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _showIngredientsOptions ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: themeColor,
                            ),
                            Text(
                              _showIngredientsOptions
                                  ? '收起常用食材备选'
                                  : '展开常用食材备选 (${_kCommonIngredients.length}种)',
                              style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.w600),
                            ),
                            if (!_showIngredientsOptions && _ingredientsCtrl.text.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '已选：${_ingredientsCtrl.text}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: AppColors.textSub),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_showIngredientsOptions) ...[
                      const SizedBox(height: 6),
                      // 常用食材快捷点选 Chip
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _kCommonIngredients.map((ing) {
                          final isSelected = _ingredientsCtrl.text.contains(ing);
                          return GestureDetector(
                            onTap: () {
                              final cur = _ingredientsCtrl.text.trim();
                              if (isSelected) {
                                final reg = RegExp('(?:^|[,，、\\s]+)${RegExp.escape(ing)}');
                                final next = cur.replaceAll(reg, '').replaceAll(RegExp(r'^[,，、\s]+'), '');
                                setState(() => _ingredientsCtrl.text = next);
                              } else {
                                final next = cur.isEmpty ? ing : '$cur, $ing';
                                setState(() => _ingredientsCtrl.text = next);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? themeColor.withOpacity(0.12) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? themeColor : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                isSelected ? '✓ $ing' : '+ $ing',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? themeColor : const Color(0xFF4B5563),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text('优先用现有食材生成自烹减脂餐', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _isLoading ? null : _fetchRecommendation,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 点外卖时，展开美团搜索品类与推荐
          if (_mealPreference == 'takeout') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isTakeoutPanelExpanded = !_isTakeoutPanelExpanded),
                    child: Row(
                      children: [
                        const Icon(Icons.delivery_dining_rounded, size: 16, color: Color(0xFF1976D2)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '美团外卖意向搜索（AI定制低卡搭配与神仙备注）：',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                          ),
                        ),
                        if (_deliveryCtrl.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              setState(() => _deliveryCtrl.clear());
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text('清空', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                            ),
                          ),
                        Icon(
                          _isTakeoutPanelExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textSub,
                        ),
                      ],
                    ),
                  ),
                  if (_isTakeoutPanelExpanded) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _deliveryCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '如：老乡鸡、轻食沙拉、赛百味、麻辣烫清汤底...',
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      onSubmitted: (_) => _fetchRecommendation(),
                    ),
                    const SizedBox(height: 6),
                    // 备选项折叠/展开栏（默认收起）
                    InkWell(
                      onTap: () => setState(() => _showDeliveryOptions = !_showDeliveryOptions),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _showDeliveryOptions ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: const Color(0xFF1976D2),
                            ),
                            Text(
                              _showDeliveryOptions
                                  ? '收起外卖热门品类备选'
                                  : '展开外卖热门品类备选 (${_kDeliveryKeywords.length}项)',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF1976D2), fontWeight: FontWeight.w600),
                            ),
                            if (!_showDeliveryOptions && _deliveryCtrl.text.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '已选：${_deliveryCtrl.text}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: AppColors.textSub),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_showDeliveryOptions) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _kDeliveryKeywords.map((kw) {
                          final isSelected = _deliveryCtrl.text.contains(kw);
                          return GestureDetector(
                            onTap: () {
                              final cur = _deliveryCtrl.text.trim();
                              if (isSelected) {
                                final reg = RegExp('(?:^|[,，、\\s]+)${RegExp.escape(kw)}');
                                final next = cur.replaceAll(reg, '').replaceAll(RegExp(r'^[,，、\s]+'), '');
                                setState(() => _deliveryCtrl.text = next);
                              } else {
                                final next = cur.isEmpty ? kw : '$cur, $kw';
                                setState(() => _deliveryCtrl.text = next);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF1976D2).withOpacity(0.12) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF1976D2) : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                isSelected ? '✓ $kw' : '+ $kw',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? const Color(0xFF1976D2) : const Color(0xFF4B5563),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text('生成美团外卖减脂避坑推荐', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _isLoading ? null : _fetchRecommendation,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 到店里吃时，展开周围实体店铺点选与搜索
          if (_mealPreference == 'dine_out') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8E24AA).withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => setState(() => _isDineOutPanelExpanded = !_isDineOutPanelExpanded),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF8E24AA)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _isLocating
                                ? '正在探测周边真实餐饮实体店...'
                                : (_nearbyStores.isNotEmpty ? '周围真实店铺（已定位）：' : '周围实体餐饮店铺：'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                          ),
                        ),
                        InkWell(
                          onTap: _isLocating ? null : _refreshNearbyStores,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                _isLocating
                                    ? const SizedBox(
                                        width: 11,
                                        height: 11,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8E24AA)),
                                      )
                                    : const Icon(Icons.my_location_rounded, size: 13, color: Color(0xFF8E24AA)),
                                const SizedBox(width: 3),
                                Text(
                                  _isLocating ? '定位中' : '重新定位',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF8E24AA), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_targetStoresCtrl.text.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() => _targetStoresCtrl.clear());
                              _fetchRecommendation();
                            },
                            child: const Text('清空', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Icon(
                          _isDineOutPanelExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.textSub,
                        ),
                      ],
                    ),
                  ),
                  if (_isDineOutPanelExpanded) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _targetStoresCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '点击下方店铺或手输（如：肯德基、麦当劳、黄焖鸡）...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onSubmitted: (_) => _fetchRecommendation(),
                  ),
                    const SizedBox(height: 6),
                    // 备选项折叠/展开栏（默认收起）
                    InkWell(
                      onTap: () => setState(() => _showStoreOptions = !_showStoreOptions),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _showStoreOptions ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: const Color(0xFF8E24AA),
                            ),
                            Text(
                              _showStoreOptions
                                  ? '收起周围店铺备选'
                                  : (_nearbyStores.isNotEmpty
                                      ? '展开周边真实店铺备选 (${_nearbyStores.length}家)'
                                      : '展开常用餐饮店铺备选 (${_kCommonStores.length}家)'),
                              style: const TextStyle(fontSize: 11, color: Color(0xFF8E24AA), fontWeight: FontWeight.w600),
                            ),
                            if (!_showStoreOptions && _targetStoresCtrl.text.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '已选：${_targetStoresCtrl.text}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10, color: AppColors.textSub),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_showStoreOptions) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: (_nearbyStores.isNotEmpty
                                ? _nearbyStores.map((s) => s.name).toList()
                                : _kCommonStores)
                            .map((stName) {
                          final isSelected = _targetStoresCtrl.text.contains(stName);
                          final matchedStore = _nearbyStores.where((s) => s.name == stName).firstOrNull;
                          final tagText = matchedStore != null ? matchedStore.displayTag : stName;
                          return GestureDetector(
                            onTap: () {
                              final cur = _targetStoresCtrl.text.trim();
                              if (isSelected) {
                                final reg = RegExp('(?:^|[,，、\\s]+)${RegExp.escape(stName)}');
                                final next = cur.replaceAll(reg, '').replaceAll(RegExp(r'^[,，、\s]+'), '');
                                setState(() => _targetStoresCtrl.text = next);
                              } else {
                                final next = cur.isEmpty ? stName : '$cur, $stName';
                                setState(() => _targetStoresCtrl.text = next);
                              }
                              _fetchRecommendation();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF8E24AA).withOpacity(0.12) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF8E24AA) : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Text(
                                isSelected ? '✓ $tagText' : '📍 $tagText',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? const Color(0xFF8E24AA) : const Color(0xFF4B5563),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (_targetStoresCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8E24AA),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.bolt_rounded, size: 16),
                          label: const Text('按指定店铺重新规划', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          onPressed: _isLoading ? null : _fetchRecommendation,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],

          // 全部推荐时
          if (_mealPreference == 'all') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 36,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('生成全场景综合推荐方案（自制+外卖+堂食）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _isLoading ? null : _fetchRecommendation,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrefChip(String label, String key) {
    final isSelected = _mealPreference == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        selectedColor: context.primaryColor.withOpacity(0.15),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? context.primaryColor : AppColors.text,
        ),
        side: BorderSide(
          color: isSelected ? context.primaryColor : const Color(0xFFE2E2DC),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (val) {
          if (val && _mealPreference != key) {
            setState(() {
              _mealPreference = key;
            });
            // 核心交互：去店里吃和点外卖自动根据剩余热量推荐，解决“不知道吃啥”；自己做先让用户选食材
            if (key == 'dine_out') {
              if (_nearbyStores.isEmpty && !_isLocating) {
                _initDineOut();
              } else {
                _fetchRecommendation();
              }
            } else if (key == 'takeout' || key == 'all') {
              _fetchRecommendation();
            } else if (key == 'cook') {
              setState(() {
                _result = null; // 切换到自己做时展示食材输入引导卡片
              });
            }
          }
        },
      ),
    );
  }

  IconData _getSlotIcon(String slotKey) {
    switch (slotKey.toLowerCase()) {
      case 'breakfast':
        return Icons.free_breakfast_outlined;
      case 'lunch':
        return Icons.lunch_dining_outlined;
      case 'dinner':
        return Icons.dinner_dining_outlined;
      case 'snack':
      default:
        return Icons.local_cafe_outlined;
    }
  }

  Color _getSceneBadgeColor(String scene) {
    if (scene.contains('已有食材') || scene.contains('现有食材')) return const Color(0xFF00897B);
    if (scene.contains('外卖')) return const Color(0xFF1976D2);
    if (scene.contains('便利店') || scene.contains('快手')) return const Color(0xFF388E3C);
    if (scene.contains('自制') || scene.contains('家常') || scene.contains('自烹') || scene.contains('做')) return const Color(0xFFE65100);
    if (scene.contains('堂食') || scene.contains('店里') || scene.contains('餐厅')) return const Color(0xFF8E24AA);
    return const Color(0xFF7B1FA2);
  }
}
