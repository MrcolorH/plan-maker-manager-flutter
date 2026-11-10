/// 设置页（对应 tabs/settings.vue）
/// 热量 / AI 服务 / 数据与备份 / 帮助 / 关于
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
import '../../providers/theme_provider.dart';
import '../../services/app_update_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/calorie_utils.dart';
import '../../utils/date_utils.dart';
import '../../widgets/update_dialog.dart';
import '../guide/guide_page.dart';
import '../onboarding/onboarding_page.dart';
import 'ai_config_page.dart';
import 'backup_page.dart';
import 'cloud_sync_page.dart';
import 'theme_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final profile = context.watch<OnboardingProvider>().state.profile;
    final records = context.watch<RecordProvider>().store;
    final themeProvider = context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const AppPageTitle(),
            const _GroupLabel('个性化与外观'),
            _Row(
              '主题与壁纸',
              themeProvider.currentConfig.name,
              onTap: () => Navigator.of(context).push(
                AppRoutes.fade<void>(const ThemeSettingsPage()),
              ),
            ),
            const _GroupLabel('热量'),
            _CalorieInfoCard(
              tdee: settings.tdee,
              profileSummary: _profileSummary(profile),
              onTap: () => _openCalorieDialog(context),
            ),
            _Row('体重记录', _weightSummary(records), onTap: () => _openWeightDialog(context)),
            const _GroupLabel('AI 服务'),
            _Row(
                'AI 服务',
                settings.ai.hasConfig
                    ? '已启用 ${_providerLabel(settings.ai.provider)} · ${settings.ai.model}'
                    : '未配置',
                onTap: () => Navigator.of(context).push(
                    AppRoutes.fade<void>(const AiConfigPage()))),
            const _GroupLabel('数据与备份'),
            _Row(
              '本地备份与恢复',
              '自动备份 · 导入 · 导出',
              onTap: () => _openBackup(context),
            ),
            _Row(
              '云端同步与 QQ 绑定',
              '云端备份 · 机器人打卡收件箱',
              onTap: () => Navigator.of(context).push(
                AppRoutes.fade<void>(const CloudSyncPage()),
              ),
            ),
            const _GroupLabel('帮助'),
            _Row('使用指引', '7 篇教程',
                onTap: () => Navigator.of(context).push(
                    AppRoutes.fade<void>(const GuidePage()))),
            _Row('重新体验首次引导', null, onTap: () {
              context.read<OnboardingProvider>().rerunOnboarding();
              Navigator.of(context).push(AppRoutes.fade<void>(const OnboardingPage()));
            }),
            const _GroupLabel('关于'),
            _Row(
              '检查更新',
              '当前版本 v${AppUpdateService.currentVersion}',
              onTap: () => _checkAppUpdate(context),
            ),
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

  /// 体重行摘要：今天录入 → 「xx kg · 今天」；有体脂 → 「xx kg · 体脂 yy% · 今天」；有历史 → 最近一次；否则「未记录」
  String _weightSummary(RecordStore records) {
    final w = records.weightRecords;
    if (w.records.isEmpty) return '未记录';
    final dates = w.records.keys.toList()..sort();
    final latest = dates.last;
    final e = w.records[latest]!;
    final today = todayStr();
    final label = latest == today ? '今天' : '${int.parse(latest.substring(5, 7))}-${int.parse(latest.substring(8))}';
    final wv = e.weight == e.weight.roundToDouble() ? '${e.weight.round()}' : '${e.weight}';
    final bfStr = (e.bodyFat != null && e.bodyFat! > 0)
        ? ' · 体脂 ${fmtBodyFat(e.bodyFat!)}%'
        : '';
    return '$wv kg$bfStr · $label';
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

  void _copyQQ(BuildContext context, String qq) {
    Clipboard.setData(ClipboardData(text: qq));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 QQ：$qq')));
  }

  void _openBackup(BuildContext context, [String? mode]) {
    Navigator.of(context).push(
      AppRoutes.fade<void>(BackupPage(mode: mode)),
    );
  }

  Future<void> _checkAppUpdate(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 14),
                Text('正在检查 GitHub Release 更新...', style: TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final info = await AppUpdateService.instance.checkUpdate();
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭加载弹窗
      await UpdateDialog.show(context, info);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭加载弹窗
      const releaseUrl = 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases';
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 22),
              SizedBox(width: 8),
              Text('版本更新提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              const Text(
                '暂无法自动获取最新版本信息，您可以前往 Release 页面查看并手动下载最新版本：',
                style: TextStyle(fontSize: 13, color: AppColors.text, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const SelectableText(
                  releaseUrl,
                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: releaseUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制 Release 链接到剪贴板')),
                );
              },
              child: const Text('复制链接'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                AppUpdateService.openBrowser(releaseUrl);
              },
              child: const Text('浏览器打开'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭', style: TextStyle(color: AppColors.textSub)),
            ),
          ],
        ),
      );
    }
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final theme = context.themeConfig;
    final isDark = theme.pageBgColor.computeLuminance() < 0.5;
    final titleColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF2C3238);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3.5,
            height: 13,
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: titleColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
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
    final themeConfig = context.themeConfig;
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: themeConfig.cardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: danger
            ? Border.all(color: AppColors.danger)
            : Border.all(color: Colors.white.withValues(alpha: 0.8), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
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

class _CalorieInfoCard extends StatelessWidget {
  final int tdee;
  final String? profileSummary;
  final VoidCallback onTap;

  const _CalorieInfoCard({
    required this.tdee,
    required this.profileSummary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeConfig = context.themeConfig;
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: themeConfig.cardOpacity),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('每日消耗', style: TextStyle(fontSize: 14)),
                    ),
                    Text(
                      tdee > 0 ? '$tdee kcal' : '未设置',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.textSub),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(
                    height: 1,
                    thickness: 0.6,
                    color: Colors.grey.withValues(alpha: 0.15),
                  ),
                ),
                Row(
                  children: [
                    const Text('基础信息', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        profileSummary ?? '未完善（点击设置）',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSub),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.textSub),
                  ],
                ),
              ],
            ),
          ),
        ),
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
  late final TextEditingController _bodyFatCtrl;
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
    final records = context.read<RecordProvider>().store;
    final effWeight = weightForDate(records, todayStr()) ?? p.weight;
    final effBf = bodyFatForDate(records, todayStr()) ?? p.bodyFat;

    // 历史数据里 TDEE/目标摄入为 0（未设置过）时留空，交估算或手填
    _tdeeCtrl = TextEditingController(text: s.tdee > 0 ? '${s.tdee}' : '');
    _targetCtrl =
        TextEditingController(text: s.dailyCalorieTarget > 0 ? '${s.dailyCalorieTarget}' : '');
    _ageCtrl = TextEditingController(text: p.age?.toString() ?? '');
    _heightCtrl = TextEditingController(text: p.height?.toString() ?? '');
    _weightCtrl =
        TextEditingController(text: effWeight != null ? fmtWeight(effWeight) : '');
    _bodyFatCtrl = TextEditingController(
        text: (effBf != null && effBf > 0) ? fmtBodyFat(effBf) : '');
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
    _bodyFatCtrl.dispose();
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
    final bf = double.tryParse(_bodyFatCtrl.text.trim());
    final macros = calculateFatLossMacroTargets(
      targetCalories: target,
      weight: w,
      bodyFat: bf,
      gender: _gender,
      height: h,
      age: age,
    );
    setState(() {
      _msg = '已估算：BMR = $bmr · 每日消耗 = $tdee · 目标 = $target kcal\n'
          '减脂期每日摄入标准：蛋白质 ${macros.protein}g · 碳水 ${macros.carbs}g · 脂肪 ${macros.fat}g';
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
      final planP = context.read<PlanProvider>();
      final patch = <String, dynamic>{'tdee': tdee, 'dailyCalorieTarget': target};
      if (_lastBmr != null && _lastBmr! > 0) patch['bmr'] = _lastBmr;
      await sp.update(patch);
      // 基础信息随保存一并持久化：三项身体数据都合法才写，避免用空值覆盖已有 profile
      final age = int.tryParse(_ageCtrl.text.trim());
      final h = int.tryParse(_heightCtrl.text.trim());
      final w = double.tryParse(_weightCtrl.text.trim());
      final bf = double.tryParse(_bodyFatCtrl.text.trim());
      if (age != null && age > 0 && h != null && h > 0 && w != null && w > 0) {
        await ob.saveProfile({
          'gender': _gender,
          'age': age,
          'height': h,
          'weight': w,
          'activity': _activity,
          'bodyFat': bf,
        });
      }

      // 计算减脂期适中偏少的每日营养素目标标准，同步更新到计划 meta 中
      final macros = calculateFatLossMacroTargets(
        targetCalories: target,
        weight: w,
        bodyFat: bf,
        gender: _gender,
        height: h,
        age: age,
      );

      await planP.updateMeta(
        dailyCalorieTarget: target,
        tdee: tdee,
        baseWeight: w,
        targetProtein: macros.protein,
        targetCarbs: macros.carbs,
        targetFat: macros.fat,
      );

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
                  _numField(_tdeeCtrl, '每日消耗（TDEE，kcal）'),
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
                  _numField(_bodyFatCtrl, '体脂率%（选填，减脂期宏量标准计算依据）', allowDecimal: true),
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
  final TextEditingController _bodyFatCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final records = context.read<RecordProvider>().store;
    final t = records.weightRecords.records[todayStr()];
    final prevBf = bodyFatForDate(records, todayStr());
    final pBf = context.read<OnboardingProvider>().state.profile.bodyFat;
    final defaultBf = prevBf ?? pBf;

    if (t != null) {
      _weightCtrl.text =
          t.weight == t.weight.roundToDouble() ? '${t.weight.round()}' : '${t.weight}';
      if (t.bodyFat != null && t.bodyFat! > 0) {
        _bodyFatCtrl.text = fmtBodyFat(t.bodyFat!);
      } else if (defaultBf != null && defaultBf > 0) {
        _bodyFatCtrl.text = fmtBodyFat(defaultBf);
      }
    } else {
      if (defaultBf != null && defaultBf > 0) {
        _bodyFatCtrl.text = fmtBodyFat(defaultBf);
      }
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _bodyFatCtrl.dispose();
    super.dispose();
  }

  UserProfile get _profile => context.read<OnboardingProvider>().state.profile;

  /// 基础信息完整 = 性别/年龄/身高齐（体重用新录入值，不依赖 profile.weight）
  bool get _bodyComplete =>
      _profile.gender.isNotEmpty && _profile.age != null && _profile.height != null;

  /// 输入合法体重（30.00–300.00，允许两位小数），否则 null
  double? get _inputWeight {
    final v = double.tryParse(_weightCtrl.text.trim());
    if (v == null || v < 30 || v > 300) return null;
    return double.parse(v.toStringAsFixed(2));
  }

  /// 输入合法体脂率（3.0–70.0，允许一位小数，选填），未输入返回 null，输入但非法返回 -1
  double? get _inputBodyFat {
    final t = _bodyFatCtrl.text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v < 3 || v > 70) return -1;
    return double.parse(v.toStringAsFixed(1));
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
    final bf = _inputBodyFat;
    if (bf == -1) {
      _hint('体脂率需在 3.0% - 70.0% 之间（或留空）');
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
      // ② 写当天记录（BMR 按录入时基础信息快照，记录体脂率）
      await records.setWeightRecord(w, bmr, bodyFat: bf);
      // ③ 同步基础信息体重与体脂率：两处保持一致，供热量估算等功能直接取用
      final profileUpdates = <String, dynamic>{'weight': w};
      if (bf != null && bf > 0) profileUpdates['bodyFat'] = bf;
      await ob.saveProfile(profileUpdates);
      if (_bodyComplete && bmr > 0) {
        // ④ 基础信息完整 → 同步 settings.bmr（update 内部在 bmr 变化前也会再触发一次固化，幂等无副作用）
        await sp.update({'bmr': bmr});
      } else {
        if (!mounted) return;
        _hint('已记录 $w kg${bf != null ? '（体脂 $bf%）' : ''}。提示：完善基础信息后，体重才会参与基础消耗计算');
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
    final bf = _inputBodyFat;
    final previewBmr = w != null && _bodyComplete
        ? estimateBmr(gender: _profile.gender, height: _profile.height!, weight: w, age: _profile.age!)
        : null;
    final validBf = (bf != null && bf > 0);
    final lbm = (w != null && validBf) ? (w * (1.0 - (bf / 100.0))) : null;

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
                const Text('体重与体脂记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            const Text('记录每天体重与体脂率，用于科学测算每日基础消耗与减脂宏量营养目标',
                style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('今天 · ${dateCn(todayStr()).split(' ').first}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '体重 (kg)',
                      hintText: '如 68.5',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _bodyFatCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}(\.\d{0,1})?')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '体脂率 (%) 选填',
                      hintText: '体脂秤参考',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  child: const Text('保存'),
                ),
              ],
            ),
            if (w != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bodyComplete
                          ? '按此体重估算：BMR ≈ $previewBmr kcal · 基础消耗 ≈ ${((previewBmr ?? 0) * 1.2).round()} kcal（BMR×1.2）'
                          : '完善基础信息（性别/年龄/身高，在「热量设置 → 更新数据」中）后，体重才会参与基础消耗计算',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                    ),
                    if (lbm != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '体脂秤参考：去脂体重 ≈ ${lbm.toStringAsFixed(1)} kg · 减脂蛋白质保肌推荐：约 ${(lbm * 2.0).round()}g/天',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
            if (w != null && (w < 30 || w > 300))
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('体重需在 30.0-300.0 kg 之间',
                    style: TextStyle(fontSize: 11, color: AppColors.danger)),
              ),
            if (bf == -1)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('体脂率需在 3.0% - 70.0% 之间',
                    style: TextStyle(fontSize: 11, color: AppColors.danger)),
              ),
            const SizedBox(height: 14),
            const Text('历史记录', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (dates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text('还没有记录，今天开始记一条吧', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
              )
            else
              ...dates.map((date) {
                final e = records.weightRecords.records[date]!;
                final base = baseBurnForDate(settings, records, date);
                final hasBf = e.bodyFat != null && e.bodyFat! > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(fmt(date), style: const TextStyle(fontSize: 13)),
                      ),
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            Text('${wText(e.weight)} kg',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            if (hasBf) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '体脂 ${fmtBodyFat(e.bodyFat!)}%',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('基消 $base kcal',
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
            const Text('一天一条：同一天重复录入会覆盖。体脂率为体脂秤参考值。删除记录只影响后续沿用，不改变已固化的历史缺口。',
                style: TextStyle(fontSize: 10, color: AppColors.textFaint, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
