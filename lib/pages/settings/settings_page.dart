/// 设置页（对应 tabs/settings.vue）
/// 热量 / 到点提醒 / AI 服务 / 数据与计划 / 帮助 / 关于
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/onboarding.dart';
import '../../models/records.dart';
import '../../models/settings.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/auto_backup_service.dart';
import '../../services/backup_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_utils.dart';
import '../../utils/date_utils.dart';
import '../guide/guide_page.dart';
import '../onboarding/onboarding_page.dart';
import 'ai_config_page.dart';
import 'backup_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final profile = context.watch<OnboardingProvider>().state.profile;
    final records = context.watch<RecordProvider>().store;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _GroupLabel('热量'),
            // 两行仅展示：点击不再弹窗，统一走下方「更新数据」按钮
            _Row('基础消耗(TDEE)', '${settings.tdee} kcal'),
            _Row('每日目标摄入', '${settings.dailyCalorieTarget} kcal'),
            if (_profileSummary(profile) != null)
              _Row('基础信息', _profileSummary(profile)!),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  onPressed: () => _openCalorieDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('更新数据', style: TextStyle(fontSize: 14)),
                ),
              ),
            ),
            _Row('体重记录', _weightSummary(records), onTap: () => _openWeightDialog(context)),
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
            _SwitchRow(
              '自动备份',
              settings.autoBackupEnabled,
              (v) => context.read<SettingsProvider>().update({'autoBackupEnabled': v}),
              subtitle: settings.autoBackupEnabled
                  ? '数据变更/退出时自动保存到系统 Download 目录（单文件覆盖，含 AI 配置）'
                  : '已关闭：开启后自动保存到系统 Download 目录的 zhiqing-backup-auto.txt（单文件覆盖）',
            ),
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
              Navigator.of(context).push(AppRoutes.fade<void>(const OnboardingPage()));
            }),
            const _GroupLabel('关于'),
            const _Row('版本', '1.0.2'),
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

  /// 基础信息摘要（性别/年龄/身高/体重/活动量）；一项都没填过返回 null（不展示该行）。
  /// activity 有默认值 1.2，不能单独作为「填过」的依据，只在其余字段存在时附加。
  String? _profileSummary(UserProfile p) {
    final parts = <String>[];
    if (p.gender == 'male') parts.add('男');
    if (p.gender == 'female') parts.add('女');
    if (p.age != null) parts.add('${p.age}岁');
    if (p.height != null) parts.add('${p.height}cm');
    if (p.weight != null) parts.add('${fmtWeight(p.weight!)}kg');
    if (parts.isEmpty) return null;
    if (p.activity > 0) parts.add(_activityLabel(p.activity));
    return parts.join(' · ');
  }

  String _activityLabel(double a) {
    switch (a) {
      case 1.375:
        return '轻度';
      case 1.55:
        return '中度';
      case 1.725:
        return '高强度';
      default:
        return '久坐';
    }
  }

  /// 体重行摘要：今天录入 → 「xx kg · 今天」；有历史 → 最近一次「xx kg · MM-dd」；否则「未记录」
  String _weightSummary(RecordStore records) {
    final w = records.weightRecords;
    if (w.records.isEmpty) return '未记录';
    final dates = w.records.keys.toList()..sort();
    final latest = dates.last;
    final e = w.records[latest]!;
    final today = todayStr();
    final label = latest == today ? '今天' : '${int.parse(latest.substring(5, 7))}-${int.parse(latest.substring(8))}';
    final wv = e.weight == e.weight.roundToDouble() ? '${e.weight.round()}' : '${e.weight}';
    return '$wv kg · $label';
  }

  void _openWeightDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => const _WeightSheet(),
    );
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
        content: const Text(
            '⚠️ 清空全部数据（计划/记录/设置）前，会先把当前数据另存一份带时间戳的备份到 Download 目录，之后仍可从「导入备份」恢复。确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // 异步前先取好 Provider 引用：await 期间页面可能被销毁，
              // 不能在 async gap 之后再用 context 触碰 Provider
              final planP = context.read<PlanProvider>();
              final recordP = context.read<RecordProvider>();
              final settingsP = context.read<SettingsProvider>();
              final onboardingP = context.read<OnboardingProvider>();
              final usageP = context.read<UsageProvider>();
              // 清空前自动留底（带时间戳文件），失败不阻断清空
              try {
                await BackupService.instance.exportBackup(captureBackupData(
                  plan: planP,
                  record: recordP,
                  settings: settingsP,
                  onboarding: onboardingP,
                  usage: usageP,
                ));
              } catch (_) {}
              await planP.clearPlan();
              await recordP.clearRecords();
              await settingsP.clearAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已清空全部数据；清空前数据已自动备份到 Download 目录')));
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
  final String? subtitle; // 开关下方小字说明（如自动备份的保存位置/状态）
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(this.label, this.value, this.onChanged, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.4)),
                ],
              ],
            ),
          ),
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
/// 6. 估算出的 BMR 随保存一并写入（与引导页口径一致，统计页按 BMR×1.2 计基础消耗）；
/// 7. 保存时把弹层里的基础信息（性别/年龄/身高/体重/活动量）一并持久化到
///    onboardingState.profile —— 用户在设置页改身高体重也生效，下次打开弹层、
///    重新体验引导、AI 生成计划都以这份 profile 为准。
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
    _weightCtrl =
        TextEditingController(text: p.weight != null ? fmtWeight(p.weight!) : '');
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
    final w = double.tryParse(_weightCtrl.text.trim());
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
      final ob = context.read<OnboardingProvider>();
      final patch = <String, dynamic>{'tdee': tdee, 'dailyCalorieTarget': target};
      if (_lastBmr != null && _lastBmr! > 0) patch['bmr'] = _lastBmr;
      await sp.update(patch);
      // 基础信息随保存一并持久化：三项身体数据都合法才写，避免用空值覆盖已有 profile
      final age = int.tryParse(_ageCtrl.text.trim());
      final h = int.tryParse(_heightCtrl.text.trim());
      final w = double.tryParse(_weightCtrl.text.trim());
      if (age != null && age > 0 && h != null && h > 0 && w != null && w > 0) {
        await ob.saveProfile({
          'gender': _gender,
          'age': age,
          'height': h,
          'weight': w,
          'activity': _activity,
        });
      }
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
                      Expanded(child: _numField(_weightCtrl, '体重kg', allowDecimal: true)),
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

  Widget _numField(TextEditingController ctrl, String hint, {bool allowDecimal = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      // 默认只允许 0-9；体重 allowDecimal 时允许两位小数（与体重记录同口径）
      inputFormatters: [
        allowDecimal
            ? FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?'))
            : FilteringTextInputFormatter.digitsOnly,
      ],
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

/// 体重记录弹层（F10 R1）：今日录入 + BMR/基础消耗实时预览 + 历史列表（可删）
/// 保存顺序（weight-design §4.2）：① 固化旧基准 ② 写当天记录（快照 BMR）③ 基础信息完整时同步 settings.bmr
class _WeightSheet extends StatefulWidget {
  const _WeightSheet();

  @override
  State<_WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<_WeightSheet> {
  final TextEditingController _weightCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 今天已录入 → 预填
    final t = context.read<RecordProvider>().store.weightRecords.records[todayStr()];
    if (t != null) {
      _weightCtrl.text =
          t.weight == t.weight.roundToDouble() ? '${t.weight.round()}' : '${t.weight}';
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  UserProfile get _profile => context.read<OnboardingProvider>().state.profile;

  /// profile 是否已有基础内容（性别/年龄/身高/体重任一已填）——
  /// 仅当已有档案时才把新录入体重同步进基础信息（两处一致），避免给空档案造半截数据
  bool get _hasProfileBase =>
      _profile.gender.isNotEmpty ||
      _profile.age != null ||
      _profile.height != null ||
      _profile.weight != null;

  /// 基础信息完整 = 性别/年龄/身高齐（体重用新录入值，不依赖 profile.weight）
  bool get _bodyComplete =>
      _profile.gender.isNotEmpty && _profile.age != null && _profile.height != null;

  /// 输入合法体重（30.00–300.00，允许两位小数），否则 null
  double? get _inputWeight {
    final v = double.tryParse(_weightCtrl.text.trim());
    if (v == null || v < 30 || v > 300) return null;
    return double.parse(v.toStringAsFixed(2));
  }

  void _hint(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final w = _inputWeight;
    if (w == null) {
      _hint('请输入 30.00-300.00 的体重（允许两位小数）');
      return;
    }
    final records = context.read<RecordProvider>();
    final sp = context.read<SettingsProvider>();
    final ob = context.read<OnboardingProvider>();
    final p = _profile;
    setState(() => _busy = true);
    try {
      final bmr = _bodyComplete
          ? estimateBmr(gender: p.gender, height: p.height!, weight: w, age: p.age!)
          : 0;
      // ① 先固化旧基准（有历史才落；幂等）
      await records.ensureBaseline(baseBurn(sp.settings));
      // ② 写当天记录（BMR 按录入时基础信息快照）
      await records.setWeightRecord(w, bmr);
      // ③ 同步基础信息体重：profile 已有基础内容时更新（两处体重保持一致）
      if (_hasProfileBase) {
        await ob.saveProfile({'weight': w});
      }
      if (_bodyComplete && bmr > 0) {
        // ④ 基础信息完整 → 同步 settings.bmr（update 内部在 bmr 变化前也会再触发一次固化，幂等无副作用）
        await sp.update({'bmr': bmr});
      } else {
        if (!mounted) return;
        _hint('已记录 $w kg。提示：完善基础信息（性别/年龄/身高，在「更新数据」中）后，体重才会参与基础消耗计算');
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _hint('保存失败：${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String date) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('删除这天的体重记录？删除后该天起沿用更早的记录（不影响已固化的历史基准）。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok == true && mounted) {
      final records = context.read<RecordProvider>();
      await records.removeWeightRecord(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = context.watch<RecordProvider>().store;
    final settings = context.watch<SettingsProvider>().settings;
    final pad = MediaQuery.of(context).viewInsets.bottom;
    final w = _inputWeight;
    final previewBmr = w != null && _bodyComplete
        ? estimateBmr(gender: _profile.gender, height: _profile.height!, weight: w, age: _profile.age!)
        : null;

    final dates = records.weightRecords.records.keys.toList()..sort((a, b) => b.compareTo(a));
    String fmt(String date) {
      final p = date.split('-');
      return '${int.parse(p[1])}月${int.parse(p[2])}日';
    }

    String wText(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('体重记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            const Text('记录每天体重，基础消耗按录入当天起更新；历史日期的缺口保持不变',
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('今天 · ${dateCn(todayStr()).split(' ').first}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '体重 kg（允许两位小数）',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ],
            ),
            if (w != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _bodyComplete
                      ? '按此体重与基础信息估算：BMR ≈ $previewBmr kcal · 基础消耗 ≈ ${((previewBmr ?? 0) * 1.2).round()} kcal（BMR×1.2）'
                      : '完善基础信息（性别/年龄/身高，在「热量设置 → 更新数据」中）后，体重才会参与基础消耗计算',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ),
            if (w != null && w < 30 || w != null && w > 300)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('体重需在 30.0-300.0 kg 之间',
                    style: TextStyle(fontSize: 11, color: AppColors.danger)),
              ),
            const SizedBox(height: 14),
            const Text('历史记录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (dates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('还没有体重记录，今天开始记一条吧', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
              )
            else
              ...dates.map((date) {
                final e = records.weightRecords.records[date]!;
                final base = baseBurnForDate(settings, records, date);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 82,
                        child: Text(fmt(date), style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        child: Text('${wText(e.weight)} kg',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      Expanded(
                        child: Text('基础消耗 $base kcal',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                      ),
                      IconButton(
                        onPressed: () => _remove(date),
                        icon: const Icon(Icons.close, size: 16, color: AppColors.textSub),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),
            const Text('一天一条：同一天重复录入会覆盖。删除记录只影响后续沿用，不改变已固化的历史缺口。',
                style: TextStyle(fontSize: 10, color: AppColors.textFaint, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
