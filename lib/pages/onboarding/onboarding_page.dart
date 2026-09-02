/// 首次使用引导（对应 onboarding/onboarding.vue，6 步）
/// 1 欢迎 → 2 性别 → 3 身体数据 → 4 活动量+目标 → 5 计划录入 → 6 确认完成
/// 计划录入支持「AI 一句话」与「逐条录入」两种方式
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/plan_data.dart';
import '../../models/settings.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/plan_utils.dart';
import '../../widgets/ai_config_sheet.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int _total = 6;
  final PageController _pageCtrl = PageController();
  int _step = 0;

  // 基本信息
  String _gender = 'male';
  final TextEditingController _ageCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  double _activity = 1.2;
  int _bmr = 0;
  int _tdee = 0;
  int _target = 0;
  final TextEditingController _targetCtrl = TextEditingController();

  // 计划录入
  String _planMode = 'ai'; // ai | manual
  final TextEditingController _aiInputCtrl = TextEditingController();
  final List<MealItem> _draftMeals = [];
  final List<ExerciseItem> _draftExercises = [];

  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _initFromProfile();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _targetCtrl.dispose();
    _aiInputCtrl.dispose();
    super.dispose();
  }

  void _initFromProfile() {
    final p = context.read<OnboardingProvider>().state.profile;
    if (p.gender.isNotEmpty) _gender = p.gender;
    if (p.age != null) _ageCtrl.text = '${p.age}';
    if (p.height != null) _heightCtrl.text = '${p.height}';
    if (p.weight != null) _weightCtrl.text = '${p.weight}';
    if (p.activity > 0) _activity = p.activity;
  }

  bool _canNext() {
    if (_step == 2) {
      return _ageCtrl.text.trim().isNotEmpty &&
          _heightCtrl.text.trim().isNotEmpty &&
          _weightCtrl.text.trim().isNotEmpty;
    }
    return true;
  }

  void _next() {
    if (!_canNext()) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先填写完整信息')));
      return;
    }
    if (_step == 2) _recalc();
    if (_step == 3) _recalc();
    if (_step == _total - 1) {
      _finish();
      return;
    }
    _pageCtrl.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _prev() {
    if (_step == 0) return;
    _pageCtrl.previousPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  void _recalc() {
    final age = int.tryParse(_ageCtrl.text.trim());
    final h = int.tryParse(_heightCtrl.text.trim());
    final w = int.tryParse(_weightCtrl.text.trim());
    if (age == null || h == null || w == null) return;
    _bmr = estimateBmr(gender: _gender, height: h, weight: w, age: age);
    _tdee = estimateTdee(gender: _gender, height: h, weight: w, age: age, activity: _activity);
    _target = recommendTarget(_bmr, _activity, _gender);
    _targetCtrl.text = '$_target';
  }

  // ---------- 完成 ----------

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final ob = context.read<OnboardingProvider>();
      final sp = context.read<SettingsProvider>();
      final usage = context.read<UsageProvider>();
      final planP = context.read<PlanProvider>();
      final age = int.tryParse(_ageCtrl.text.trim());
      final h = int.tryParse(_heightCtrl.text.trim());
      final w = int.tryParse(_weightCtrl.text.trim());
      final profileComplete = age != null && h != null && w != null;

      if (profileComplete) {
        await ob.saveProfile({
          'gender': _gender,
          'age': age,
          'height': h,
          'weight': w,
          'activity': _activity,
        });
      }

      final patch = <String, dynamic>{};
      if (_bmr > 0) patch['bmr'] = _bmr;
      if (_tdee > 0) patch['tdee'] = _tdee;
      final t = int.tryParse(_targetCtrl.text.trim());
      if (t != null && t > 0) patch['dailyCalorieTarget'] = t;
      if (patch.isNotEmpty) await sp.update(patch);

      // 生成计划
      Map<String, dynamic>? raw;
      if (!mounted) return;
      if (_planMode == 'ai' && _aiInputCtrl.text.trim().isNotEmpty) {
        // 未配置 AI → 引导页内弹配置层（可「暂不，手动模式」跳过，输入文本保留不丢）
        if (!sp.settings.ai.hasConfig) {
          final r = await showAiConfigSheet(
            context,
            title: '配置 AI，让计划自动生成',
            message: '填好 API Key 后会立刻用你写的内容生成计划。',
            confirmText: '保存并生成',
            allowSkip: true,
          );
          if (!mounted) return;
          if (r != AiConfigSheetResult.configured) {
            if (r == AiConfigSheetResult.skipped) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已跳过 AI，可改用「逐条录入」完成计划')));
            }
            return; // 未完成引导，停留在当前步，输入内容不丢
          }
        }
        raw = await AiService.instance.generatePlanFromInput(
          sp.settings.ai,
          _aiInputCtrl.text.trim(),
          ob.state.profile,
          onUsage: usage.addUsage,
        );
      } else if (_draftMeals.isNotEmpty || _draftExercises.isNotEmpty) {
        raw = {
          'version': '1.0',
          'meta': {
            'dailyCalorieTarget': t != null && t > 0 ? t : null,
            'tdee': _tdee > 0 ? _tdee : null,
          },
          'meals': _draftMeals.map((m) => m.toJson()).toList(),
          'exercises': _draftExercises.map((e) => e.toJson()).toList(),
        };
      }
      if (raw != null) {
        final errs = validateRaw(raw);
        if (errs.isEmpty) {
          await planP.importPlan(raw);
        }
      }

      await ob.finishOnboarding();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  void _skip() {
    context.read<OnboardingProvider>().skipOnboarding();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _exit() {
    context.read<OnboardingProvider>().dismissOnboarding();
    Navigator.of(context).pop();
  }

  // ---------- 逐条录入 ----------

  Future<void> _addMeal() async {
    final typeCtrl = ValueNotifier<String>('breakfast');
    final nameCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '08:00');
    final calCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加餐食', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: typeCtrl,
                builder: (ctx, type, _) => Wrap(
                  spacing: 6,
                  children: [
                    _typeChip(typeCtrl, 'breakfast', '早餐'),
                    _typeChip(typeCtrl, 'lunch', '午餐'),
                    _typeChip(typeCtrl, 'dinner', '晚餐'),
                    _typeChip(typeCtrl, 'snack', '加餐'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
              TextField(controller: timeCtrl, decoration: const InputDecoration(labelText: '时间 HH:mm')),
              TextField(
                  controller: calCtrl, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '热量 kcal（留空=自由餐）')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _draftMeals.add(MealItem(
          id: genId('m'),
          type: typeCtrl.value,
          name: nameCtrl.text.trim().isEmpty ? '未命名' : nameCtrl.text.trim(),
          time: _validTime(timeCtrl.text.trim()) ? timeCtrl.text.trim() : '12:00',
          calories: int.tryParse(calCtrl.text.trim()),
          days: const [1, 2, 3, 4, 5, 6, 7],
        ));
      });
    }
  }

  Future<void> _addExercise() async {
    final nameCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '18:30');
    final durCtrl = TextEditingController(text: '30');
    final burnCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加运动', style: TextStyle(fontSize: 16)),
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
            child: const Text('添加', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _draftExercises.add(ExerciseItem(
          id: genId('e'),
          name: nameCtrl.text.trim().isEmpty ? '未命名' : nameCtrl.text.trim(),
          time: _validTime(timeCtrl.text.trim()) ? timeCtrl.text.trim() : '18:30',
          duration: int.tryParse(durCtrl.text.trim()) ?? 30,
          caloriesBurned: int.tryParse(burnCtrl.text.trim()) ?? 0,
          days: const [1, 2, 3, 4, 5, 6, 7],
        ));
      });
    }
  }

  bool _validTime(String t) => RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t);

  Widget _typeChip(ValueNotifier<String> notifier, String value, String label) {
    return ValueListenableBuilder<String>(
      valueListenable: notifier,
      builder: (ctx, cur, _) => ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: cur == value,
        onSelected: (_) => notifier.value = value,
        selectedColor: AppColors.primaryBg,
        labelStyle: TextStyle(color: cur == value ? AppColors.primary : AppColors.textSub),
      ),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text('第 $_step 步 / $_total'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: _step == 0 ? _exit : _prev,
          ),
          actions: [
            TextButton(onPressed: _skip, child: const Text('跳过', style: TextStyle(color: AppColors.textSub))),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_step + 1) / _total,
                backgroundColor: AppColors.tagBg,
                color: AppColors.primary,
                minHeight: 3,
              ),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _step = i),
                  children: [
                    _welcomeStep(),
                    _genderStep(),
                    _bodyStep(),
                    _activityStep(),
                    _planStep(),
                    _finishStep(),
                  ],
                ),
              ),
              _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: PlainButton('上一步', onPressed: _prev),
            )
          else
            const Expanded(child: SizedBox()),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: PrimaryButton(
              _step == _total - 1 ? (_finishing ? '生成中…' : '确认完成，开始用') : '下一步',
              onPressed: _finishing ? null : _next,
            ),
          ),
        ],
      ),
    );
  }

  // 1 欢迎
  Widget _welcomeStep() {
    return _stepWrap(
      children: [
        const Text('🥗', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 16),
        const Text('欢迎使用减肥搭子',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text)),
        const SizedBox(height: 10),
        const Text('填 3 步信息，就能算出你的基础代谢；\n再把想吃的餐食和运动告诉它，一键生成减脂计划。\n数据只存本机，离线可用。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.6)),
        const SizedBox(height: 20),
        const Text('开始前先了解一下你：', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
      ],
    );
  }

  // 2 性别
  Widget _genderStep() {
    return _stepWrap(
      children: [
        const Text('性别', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('用于 Mifflin-St Jeor 公式估算基础代谢',
            style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: _genderCard('male', '👨', '男')),
            const SizedBox(width: 12),
            Expanded(child: _genderCard('female', '👩', '女')),
          ],
        ),
      ],
    );
  }

  Widget _genderCard(String value, String icon, String label) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBg : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.text,
                )),
          ],
        ),
      ),
    );
  }

  // 3 身体数据
  Widget _bodyStep() {
    return _stepWrap(
      children: [
        const Text('身体数据', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('年龄 / 身高 / 体重（体重也会用于运动消耗估算）',
            style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 20),
        _numField(_ageCtrl, '年龄', '岁'),
        const SizedBox(height: 10),
        _numField(_heightCtrl, '身高', 'cm'),
        const SizedBox(height: 10),
        _numField(_weightCtrl, '体重', 'kg'),
      ],
    );
  }

  // 4 活动量
  Widget _activityStep() {
    return _stepWrap(
      children: [
        const Text('日常活动量', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('工作/生活整体强度（运动计划之外的日常消耗）',
            style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 16),
        _activityChip(1.2, '久坐办公'),
        _activityChip(1.375, '轻度活动'),
        _activityChip(1.55, '中度活动'),
        _activityChip(1.725, '高强度'),
        const SizedBox(height: 20),
        if (_bmr > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text('BMR 基础代谢 $_bmr · 每日基础消耗 $_tdee kcal',
                    style: const TextStyle(fontSize: 13, color: AppColors.text)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('每日目标摄入', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _targetCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 14, color: AppColors.primary),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('kcal', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _activityChip(double value, String label) {
    final selected = _activity == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() {
          _activity = value;
          _recalc();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBg : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.2),
          ),
          child: Row(
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: selected ? AppColors.primary : AppColors.text)),
              const Spacer(),
              if (selected)
                const Icon(Icons.check_circle, size: 18, color: AppColors.primary)
              else
                Icon(Icons.circle_outlined, size: 18, color: AppColors.chartGray),
            ],
          ),
        ),
      ),
    );
  }

  // 5 计划录入
  Widget _planStep() {
    return _stepWrap(
      children: [
        const Text('录入你的计划', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('两种方式任选；运动也可以一起录入', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 16),
        _modeCard('ai', '✨ AI 一句话', '把想吃的/想练的写成一段话，AI 自动拆分餐次、配时间、算热量'),
        const SizedBox(height: 10),
        if (_planMode == 'ai')
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: TextField(
              controller: _aiInputCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '例：早餐两个包子+豆浆；午餐荞麦面+煎蛋；晚餐鸡胸肉+青菜；\n周一周三周五晚上快走40分钟',
                filled: true,
                fillColor: AppColors.bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                hintStyle: TextStyle(fontSize: 12, color: AppColors.chartGray),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        _modeCard('manual', '📝 逐条录入', '一餐一餐手动添加，运动同样支持'),
        const SizedBox(height: 10),
        if (_planMode == 'manual') ...[
          if (_draftMeals.isNotEmpty) ...[
            ..._draftMeals.map((m) => _draftRow(
                  title: '${kTypeCn[m.type] ?? m.type} · ${m.name}',
                  sub: '${m.time}${m.calories != null ? ' · ${m.calories} kcal' : ' · 自由餐'}',
                  onDelete: () => setState(() => _draftMeals.remove(m)),
                )),
          ],
          if (_draftExercises.isNotEmpty) ...[
            ..._draftExercises.map((e) => _draftRow(
                  title: '🏃 ${e.name}',
                  sub: '${e.time} · ${e.duration} 分钟${e.caloriesBurned > 0 ? ' · ≈-${e.caloriesBurned} kcal' : ''}',
                  onDelete: () => setState(() => _draftExercises.remove(e)),
                )),
          ],
          _dashedAdd('＋ 添加餐食', _addMeal),
          const SizedBox(height: 8),
          _dashedAdd('＋ 添加运动', _addExercise),
        ],
      ],
    );
  }

  Widget _modeCard(String value, String title, String desc) {
    final selected = _planMode == value;
    return GestureDetector(
      onTap: () => setState(() => _planMode = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.primary : AppColors.text,
                      )),
                  const SizedBox(height: 3),
                  Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 18, color: AppColors.primary)
            else
              Icon(Icons.circle_outlined, size: 18, color: AppColors.chartGray),
          ],
        ),
      ),
    );
  }

  Widget _draftRow({required String title, required String sub, required VoidCallback onDelete}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 16, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _dashedAdd(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary),
        ),
        alignment: Alignment.center,
        child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.primary)),
      ),
    );
  }

  // 6 完成
  Widget _finishStep() {
    final hasPlan = (_planMode == 'ai' && _aiInputCtrl.text.trim().isNotEmpty) ||
        _draftMeals.isNotEmpty ||
        _draftExercises.isNotEmpty;
    final target = int.tryParse(_targetCtrl.text.trim()) ?? _target;
    return _stepWrap(
      children: [
        const Text('🎉', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        const Text('准备好了！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          _bmr > 0 ? '基础代谢 $_bmr · 每日基础消耗 $_tdee kcal\n每日目标摄入 $target kcal' : '未填写身体数据，可稍后在「设置 → 热量」中补全',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.6),
        ),
        const SizedBox(height: 16),
        if (hasPlan)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.primaryBg, borderRadius: BorderRadius.circular(10)),
            child: Text(
              _planMode == 'ai'
                  ? '计划：AI 生成（${_aiInputCtrl.text.trim().length} 字描述）'
                  : '计划：餐食 ${_draftMeals.length} 条 · 运动 ${_draftExercises.length} 条',
              style: const TextStyle(fontSize: 13, color: AppColors.primary),
            ),
          )
        else
          const Text('还没录入计划，可以先点「完成」进 App，之后随时在「计划」页导入',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 16),
        const Text('完成即开启到点提醒：餐食/运动到时间自动通知（可在设置中关闭）',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textSub)),
      ],
    );
  }

  Widget _stepWrap({required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label, String unit) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
            ),
            style: const TextStyle(fontSize: 15),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 32, child: Text(unit, style: const TextStyle(fontSize: 14, color: AppColors.textSub))),
      ],
    );
  }
}
