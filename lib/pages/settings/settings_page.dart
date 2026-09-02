/// 设置页（对应 tabs/settings.vue）
/// 热量 / 到点提醒 / AI 服务 / 数据与计划 / 帮助 / 关于
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/onboarding.dart';
import '../../models/settings.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../guide/guide_page.dart';
import 'ai_config_page.dart';
import 'backup_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _GroupLabel('热量'),
            _Row('基础消耗(TDEE)', '${settings.tdee} kcal', onTap: () => _openCalorieDialog(context)),
            _Row('每日目标摄入', '${settings.dailyCalorieTarget} kcal', onTap: () => _openCalorieDialog(context)),
            const _GroupLabel('到点提醒'),
            _SwitchRow('提醒开关', settings.reminderEnabled, (v) {
              context.read<SettingsProvider>().update({'reminderEnabled': v});
            }),
            _Row('提前提醒', '${settings.reminderAdvance} 分钟',
                onTap: () => _openAdvanceDialog(context)),
            _Row('通知权限', null, onTap: () => _checkPermission(context)),
            const _GroupLabel('AI 服务'),
            _Row('AI 服务', '${_providerLabel(settings.ai.provider)} · ${settings.ai.model}',
                onTap: () => Navigator.of(context).push(
                    AppRoutes.fade<void>(const AiConfigPage()))),
            const _GroupLabel('数据与计划'),
            _Row('导出备份', '分享 .txt 文件', onTap: () => _openBackup(context, 'export')),
            _Row('导入备份', '增量合并 / 覆盖', onTap: () => _openBackup(context, 'import')),
            _Row('清空餐食计划', null, onTap: () => _confirmClear(context, 'meal')),
            _Row('清空运动计划', null, onTap: () => _confirmClear(context, 'exercise')),
            _Row('清空全部数据', null, danger: true, onTap: () => _confirmClearAll(context)),
            const _GroupLabel('帮助'),
            _Row('使用指引', '8 篇教程',                 onTap: () => Navigator.of(context).push(
                    AppRoutes.fade<void>(const GuidePage()))),
            _Row('重新体验首次引导', null, onTap: () {
              context.read<OnboardingProvider>().rerunOnboarding();
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已重置引导，重启 App 后可见')));
            }),
            const _GroupLabel('关于'),
            const _Row('版本', '1.0.0'),
            const _Row('作者', '听风闻人语'),
            _Row('QQ', '1419046431', onTap: () => _copyQQ(context, '1419046431')),
            const SizedBox(height: 12),
            const Center(
              child: Text('知轻 · 单机离线优先，数据仅存本机',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            ),
          ],
        ),
      ),
    );
  }

  String _providerLabel(String provider) {
    for (final p in kAiProviders) {
      if (p.value == provider) return p.label;
    }
    return '自定义';
  }

  void _openCalorieDialog(BuildContext context) {
    final sp = context.read<SettingsProvider>();
    final profile = context.read<OnboardingProvider>().state.profile;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _CalorieSheet(settings: sp.settings, profile: profile),
    );
  }

  void _openAdvanceDialog(BuildContext context) {
    final sp = context.read<SettingsProvider>();
    final settings = sp.settings;
    final ctrl = TextEditingController(text: '${settings.reminderAdvance}');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提前提醒（分钟）', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0-30 分钟'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v != null && v >= 0 && v <= 30) {
                sp.update({'reminderAdvance': v});
              }
              Navigator.pop(ctx);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPermission(BuildContext context) async {
    final granted = await ReminderService.instance.checkNotifPermission();
    if (!context.mounted) return;
    if (!granted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('通知权限未开启', style: TextStyle(fontSize: 16)),
          content: const Text('未授权时提醒无法显示，点击「去开启」申请通知权限。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去开启', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (ok == true) {
        final r = await ReminderService.instance.requestNotifPermission();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(r ? '通知权限已开启' : '未获得授权，提醒可能无法显示')));
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('通知权限已开启')));
    }
  }

  void _copyQQ(BuildContext context, String qq) {
    Clipboard.setData(ClipboardData(text: qq));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 QQ：$qq')));
  }

  void _openBackup(BuildContext context, String mode) {
    Navigator.of(context).push(
      AppRoutes.fade<void>(BackupPage(mode: mode)),
    );
  }

  void _confirmClear(BuildContext context, String type) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(type == 'meal' ? '清空全部餐食计划？打卡记录会保留。' : '清空全部运动计划？打卡记录会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (type == 'meal') {
                context.read<PlanProvider>().clearMeals();
              } else {
                context.read<PlanProvider>().clearExercises();
              }
            },
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('⚠️ 清空全部数据（计划/记录/设置）后不可恢复，确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final planP = context.read<PlanProvider>();
              final recordP = context.read<RecordProvider>();
              final settingsP = context.read<SettingsProvider>();
              await planP.clearPlan();
              await recordP.clearRecords();
              await settingsP.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空全部数据')));
              }
            },
            child: const Text('全部清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w600)),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;
  const _Row(this.label, this.value, {this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: danger ? Border.all(color: AppColors.danger) : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            if (value != null)
              Text(value!, style: TextStyle(fontSize: 13, color: danger ? AppColors.danger : AppColors.textSub)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textSub),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 热量设置弹层：手填 TDEE / 目标摄入，或用 Mifflin-St Jeor 公式估算。
/// 与旧实现的差异（修复「点了没反应 / 保存不了」）：
/// 1. 结果/错误就地显示在弹层内 —— SnackBar 会被 bottom sheet 面板盖住，永远看不见；
/// 2. 内容可滚动，估算/保存按钮固定在底部，键盘弹出也不会被遮挡；
/// 3. 数字输入只允许 0-9，杜绝全角/小数点导致 int.tryParse 静默失败；
/// 4. 性别/年龄/身高/体重/活动量自动带入首次引导（onboarding profile）填过的值；
/// 5. 导入数据中 TDEE/目标摄入为 0 时留空并就地引导先估算，而不是无提示拦截；
/// 6. 估算出的 BMR 随保存一并写入（与引导页口径一致，统计页按 BMR×1.2 计基础消耗）。
class _CalorieSheet extends StatefulWidget {
  final AppSettings settings;
  final UserProfile profile;
  const _CalorieSheet({required this.settings, required this.profile});

  @override
  State<_CalorieSheet> createState() => _CalorieSheetState();
}

class _CalorieSheetState extends State<_CalorieSheet> {
  late final TextEditingController _tdeeCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _weightCtrl;
  late String _gender;
  late double _activity;

  /// 就地提示（成功绿 / 失败红），不依赖会被弹层遮挡的 SnackBar
  String _msg = '';
  bool _msgError = false;

  /// 最近一次估算的 BMR；>0 时保存随 patch 写入（估算过才写，手填不覆盖旧值）
  int? _lastBmr;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    final p = widget.profile;
    // 历史数据里 TDEE/目标摄入为 0（未设置过）时留空，交估算或手填
    _tdeeCtrl = TextEditingController(text: s.tdee > 0 ? '${s.tdee}' : '');
    _targetCtrl =
        TextEditingController(text: s.dailyCalorieTarget > 0 ? '${s.dailyCalorieTarget}' : '');
    _ageCtrl = TextEditingController(text: p.age?.toString() ?? '');
    _heightCtrl = TextEditingController(text: p.height?.toString() ?? '');
    _weightCtrl = TextEditingController(text: p.weight?.toString() ?? '');
    _gender = p.gender == 'female' ? 'female' : 'male';
    _activity = p.activity > 0 ? p.activity : 1.2;
  }

  @override
  void dispose() {
    _tdeeCtrl.dispose();
    _targetCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _estimate() {
    FocusScope.of(context).unfocus(); // 收起键盘，让结果行可见可点保存
    final age = int.tryParse(_ageCtrl.text.trim());
    final h = int.tryParse(_heightCtrl.text.trim());
    final w = int.tryParse(_weightCtrl.text.trim());
    if (age == null || age <= 0 || h == null || h <= 0 || w == null || w <= 0) {
      setState(() {
        _msg = '请先完整填写年龄 / 身高 / 体重（数字即可）';
        _msgError = true;
      });
      return;
    }
    final bmr = estimateBmr(gender: _gender, height: h, weight: w, age: age);
    final tdee =
        estimateTdee(gender: _gender, height: h, weight: w, age: age, activity: _activity);
    final target = recommendTarget(bmr, _activity, _gender);
    _tdeeCtrl.text = '$tdee';
    _targetCtrl.text = '$target';
    _lastBmr = bmr;
    setState(() {
      _msg = '已估算并填入：BMR = $bmr kcal · 基础消耗 = $tdee kcal · 推荐目标摄入 = $target kcal';
      _msgError = false;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final tdee = int.tryParse(_tdeeCtrl.text.trim());
    final target = int.tryParse(_targetCtrl.text.trim());
    if (tdee == null || target == null || tdee <= 0 || target <= 0) {
      setState(() {
        _msg = 'TDEE 与目标摄入需为大于 0 的数字：可直接手填，或先点「估算并填入」自动生成';
        _msgError = true;
      });
      return;
    }
    try {
      final sp = context.read<SettingsProvider>();
      final patch = <String, dynamic>{'tdee': tdee, 'dailyCalorieTarget': target};
      if (_lastBmr != null && _lastBmr! > 0) patch['bmr'] = _lastBmr;
      await sp.update(patch);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = '保存失败：$e';
        _msgError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 键盘弹出时把弹层整体顶起，固定按钮区始终在键盘上方
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('热量设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          // 输入区可滚动：小屏 + 键盘弹出时不会溢出/遮挡
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _numField(_tdeeCtrl, '基础消耗 TDEE（kcal）'),
                  const SizedBox(height: 8),
                  _numField(_targetCtrl, '每日目标摄入（kcal）'),
                  const SizedBox(height: 12),
                  const Text('或用 Mifflin-St Jeor 公式估算',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _genderChip('male', '男'),
                      const SizedBox(width: 8),
                      _genderChip('female', '女'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _numField(_ageCtrl, '年龄')),
                      const SizedBox(width: 8),
                      Expanded(child: _numField(_heightCtrl, '身高cm')),
                      const SizedBox(width: 8),
                      Expanded(child: _numField(_weightCtrl, '体重kg')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _activityChip(1.2, '久坐'),
                      _activityChip(1.375, '轻度'),
                      _activityChip(1.55, '中度'),
                      _activityChip(1.725, '高强度'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 固定操作区：估算 / 就地提示 / 保存，键盘弹出时仍然可达
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _estimate,
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size.fromHeight(40)),
                child: const Text('估算并填入 ↑'),
              ),
            ),
          ),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _msgError ? AppColors.dangerBg : AppColors.primaryBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _msg,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: _msgError ? AppColors.danger : AppColors.primary),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44)),
                child: const Text('保存'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genderChip(String value, String label) {
    final selected = _gender == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _gender = value),
      selectedColor: AppColors.primaryBg,
      labelStyle: TextStyle(
          color: selected ? AppColors.primary : AppColors.textSub, fontSize: 12),
    );
  }

  Widget _activityChip(double value, String label) {
    final selected = _activity == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => setState(() => _activity = value),
      selectedColor: AppColors.primaryBg,
      labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSub),
    );
  }

  Widget _numField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      // 只允许 0-9：全角数字/小数点/空格会在输入时被过滤，杜绝 int.tryParse 静默失败
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.bg,
        border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.all(10),
      ),
    );
  }
}
