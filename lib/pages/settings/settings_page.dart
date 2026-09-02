/// 设置页（对应 tabs/settings.vue）
/// 热量 / 到点提醒 / AI 服务 / 数据与计划 / 帮助 / 关于
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
            const SizedBox(height: 12),
            const Center(
              child: Text('减肥搭子 · 单机离线优先，数据仅存本机',
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
    final settings = sp.settings;
    final tdeeCtrl = TextEditingController(text: '${settings.tdee}');
    final targetCtrl = TextEditingController(text: '${settings.dailyCalorieTarget}');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('热量设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _numField(tdeeCtrl, '基础消耗 TDEE（kcal）'),
              const SizedBox(height: 8),
              _numField(targetCtrl, '每日目标摄入（kcal）'),
              const SizedBox(height: 12),
              const Text('或用 Mifflin-St Jeor 公式估算', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              const SizedBox(height: 8),
              _bmrEstimator(ctx, settings, tdeeCtrl, targetCtrl),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () async {
                  final tdee = int.tryParse(tdeeCtrl.text.trim());
                  final target = int.tryParse(targetCtrl.text.trim());
                  if (tdee == null || target == null || tdee <= 0 || target <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入有效的数字')));
                    return;
                  }
                  await sp.update({'tdee': tdee, 'dailyCalorieTarget': target});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bmrEstimator(BuildContext ctx, AppSettings settings,
      TextEditingController tdeeCtrl, TextEditingController targetCtrl) {
    final genderCtrl = ValueNotifier<String>(settings.bmr > 0 ? 'male' : 'male');
    final ageCtrl = TextEditingController();
    final heightCtrl = TextEditingController();
    final weightCtrl = TextEditingController();
    final activityCtrl = ValueNotifier<double>(1.2);
    return ValueListenableBuilder<String>(
      valueListenable: genderCtrl,
      builder: (ctx, gender, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('男'),
                  selected: gender == 'male',
                  onSelected: (_) => genderCtrl.value = 'male',
                  selectedColor: AppColors.primaryBg,
                  labelStyle: TextStyle(color: gender == 'male' ? AppColors.primary : AppColors.textSub, fontSize: 12),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('女'),
                  selected: gender == 'female',
                  onSelected: (_) => genderCtrl.value = 'female',
                  selectedColor: AppColors.primaryBg,
                  labelStyle: TextStyle(color: gender == 'female' ? AppColors.primary : AppColors.textSub, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _numField(ageCtrl, '年龄')),
                const SizedBox(width: 8),
                Expanded(child: _numField(heightCtrl, '身高cm')),
                const SizedBox(width: 8),
                Expanded(child: _numField(weightCtrl, '体重kg')),
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: activityCtrl,
              builder: (ctx, activity, _) {
                return Wrap(
                  spacing: 6,
                  children: [
                    _activityChip(activityCtrl, 1.2, '久坐'),
                    _activityChip(activityCtrl, 1.375, '轻度'),
                    _activityChip(activityCtrl, 1.55, '中度'),
                    _activityChip(activityCtrl, 1.725, '高强度'),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  final age = int.tryParse(ageCtrl.text.trim());
                  final h = int.tryParse(heightCtrl.text.trim());
                  final w = int.tryParse(weightCtrl.text.trim());
                  if (age == null || h == null || w == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请完整填写年龄/身高/体重')));
                    return;
                  }
                  final bmr = estimateBmr(gender: gender, height: h, weight: w, age: age);
                  final tdee = estimateTdee(gender: gender, height: h, weight: w, age: age, activity: activityCtrl.value);
                  final target = recommendTarget(bmr, activityCtrl.value, gender);
                  tdeeCtrl.text = '$tdee';
                  targetCtrl.text = '$target';
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('BMR=$bmr · TDEE=$tdee · 推荐目标=$target')));
                },
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                child: const Text('估算并填入 ↑'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _activityChip(ValueNotifier<double> notifier, double value, String label) {
    return ValueListenableBuilder<double>(
      valueListenable: notifier,
      builder: (ctx, cur, _) {
        return ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: cur == value,
          onSelected: (_) => notifier.value = value,
          selectedColor: AppColors.primaryBg,
          labelStyle: TextStyle(color: cur == value ? AppColors.primary : AppColors.textSub),
        );
      },
    );
  }

  Widget _numField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.bg,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
        isDense: true,
        contentPadding: const EdgeInsets.all(10),
      ),
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
