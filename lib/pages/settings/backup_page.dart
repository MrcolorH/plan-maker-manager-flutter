/// 备份页（对应 settings/backup.vue）
/// mode: 'export' 导出备份（.txt 全量快照 → 手机存储根目录 Download 目录）
///       'import' 导入备份（自动备份一键恢复 / 选文件 → 概要 → 增量合并 / 覆盖导入）
/// 自动备份 = Download/zhiqing-backup-auto.txt 单文件滚动覆盖（见 auto_backup_service.dart）
/// 增量导入不触碰 settings/onboardingState/apiUsage；覆盖导入全量替换（强确认 + 导入前自动留底）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/auto_backup_service.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';

class BackupPage extends StatefulWidget {
  final String mode; // export | import
  const BackupPage({super.key, required this.mode});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  BackupData? _parsed;
  String? _exportedAt;
  late final Future<ParseResult?> _autoParsed = _loadAutoBackup();

  bool get _isExport => widget.mode == 'export';

  /// 读取自动备份文件并解析；无备份或内容损坏时返回 null（页面显示为「暂无」）
  Future<ParseResult?> _loadAutoBackup() async {
    try {
      final text = await BackupService.instance.readAutoBackupText();
      if (text == null || text.isEmpty) return null;
      final r = BackupService.instance.parseBackupText(text);
      return r.ok ? r : null;
    } catch (_) {
      return null;
    }
  }

  BackupData _snapshot() => captureBackupData(
        plan: context.read<PlanProvider>(),
        record: context.read<RecordProvider>(),
        settings: context.read<SettingsProvider>(),
        onboarding: context.read<OnboardingProvider>(),
        usage: context.read<UsageProvider>(),
      );

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final r = await BackupService.instance.exportBackup(_snapshot());
      if (!mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(r.fallback ? '导出成功（已改用备用位置）' : '导出成功',
              style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('文件名：${r.fileName}'),
              const SizedBox(height: 6),
              Text('保存位置：${r.savedPath}'),
              const SizedBox(height: 10),
              Text(
                r.fallback
                    ? '未能写入 Download 目录，已保存到应用目录，可通过「分享」发送到微信/网盘保存。'
                    : '已保存到手机存储的 Download 目录，可用「文件管理」查看，也可分享到微信/网盘备份。',
                style: const TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('关闭', style: TextStyle(color: AppColors.textSub))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('分享', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (share == true) {
        await BackupService.instance.shareBackup(r.path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _parsed = null;
      _exportedAt = null;
    });
    try {
      final text = await BackupService.instance.pickBackupFile();
      final r = BackupService.instance.parseBackupText(text);
      if (!r.ok) throw Exception(r.error ?? '解析失败');
      if (!mounted) return;
      setState(() {
        _parsed = r.data;
        _exportedAt = r.exportedAt;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  BackupLike _recordsOf(BackupData data) => BackupLike(
        checkRecords: data.checkRecords,
        mealAdjust: data.mealAdjust,
        tempTasks: data.tempTasks,
        extraFoods: data.extraFoods,
        dayEntries: data.dayEntries,
        weightRecords: data.weightRecords,
      );

  /// 增量合并：计划/记录合并，不触碰设置/引导/用量
  Future<void> _mergeImport() async {
    final data = _parsed!;
    final planP = context.read<PlanProvider>();
    final recordP = context.read<RecordProvider>();
    setState(() => _busy = true);
    try {
      await planP.importPlan(data.planData.toJson());
      await recordP.mergeRecords(_recordsOf(data));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已增量合并：相同 id 覆盖更新，历史记录保留')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 覆盖导入：全量替换（含 AI 配置），强确认
  Future<void> _replaceImport() async {
    final data = _parsed!;
    final planP = context.read<PlanProvider>();
    final recordP = context.read<RecordProvider>();
    final settingsP = context.read<SettingsProvider>();
    final obP = context.read<OnboardingProvider>();
    final usageP = context.read<UsageProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 覆盖导入', style: TextStyle(fontSize: 16)),
        content: const Text(
            '将用备份数据整体替换当前：计划、打卡记录、设置（含 AI 配置）、引导状态、用量统计。\n替换前会自动把当前数据另存一份带时间戳的备份到 Download 目录，导错了还能找回来。确定继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖导入', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    String? safetyTip;
    try {
      // 替换前先把当前数据留底（带时间戳，不覆盖自动备份），失败不阻断导入
      await BackupService.instance.exportBackup(_snapshot());
    } catch (_) {
      safetyTip = '提示：导入前自动留底失败（如未授予存储权限），当前数据未被另行保存。';
    }
    try {
      await planP.replacePlan(data.planData);
      await recordP.replaceRecords(_recordsOf(data));
      await settingsP.replaceSettings(data.settings);
      await obP.replaceOnboarding(data.onboardingState);
      usageP.replaceUsage(data.apiUsage);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(safetyTip ?? '已覆盖导入，数据已替换')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败：${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isExport ? '导出备份' : '导入备份')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _isExport ? _exportBody() : _importBody(),
      ),
    );
  }

  List<Widget> _exportBody() {
    final autoOn = context.watch<SettingsProvider>().settings.autoBackupEnabled;
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('导出内容（.txt 全量快照）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('• 减脂计划（餐食 + 运动）\n• 全部打卡 / 加餐 / 调整记录\n• 热量设置与 AI 配置\n• 引导状态与用量统计',
                style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.7)),
            const SizedBox(height: 10),
            const Text('导出为 .txt 文件，保存到手机存储的 Download 目录，可用「文件管理」直接查看或分享到网盘。',
                style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.6)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(autoOn ? '自动备份已开启' : '自动备份未开启',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              autoOn
                  ? '数据变更后 / 每次退出应用，都会自动覆盖更新系统 Download 目录里的\nzhiqing-backup-auto.txt（永远只有一份，含 AI 配置）。可在「设置 → 自动备份」随时关闭。\n手动导出仅用于主动留档或把备份发到其他设备。'
                  : '在「设置 → 数据与计划 → 自动备份」开启后，数据变更 / 每次退出应用会自动保存到\n系统 Download 目录的 zhiqing-backup-auto.txt（单文件覆盖，永远只有一份，含 AI 配置）。\n手动导出仅用于主动留档或把备份发到其他设备。',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.6),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      PrimaryButton(_busy ? '导出中…' : '导出备份', onPressed: _busy ? null : _export),
      const SizedBox(height: 10),
      const Center(
        child: Text('换机/重装后，在导入页选择 Download 目录里的 .txt 备份文件即可恢复',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ),
    ];
  }

  List<Widget> _importBody() {
    final autoOn = context.watch<SettingsProvider>().settings.autoBackupEnabled;
    return [
      FutureBuilder<ParseResult?>(
        future: _autoParsed,
        builder: (ctx, snap) {
          final r = snap.data;
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('正在读取自动备份…', style: TextStyle(fontSize: 12, color: AppColors.textSub))));
          }
          final at = r == null ? '' : BackupService.instance.fmtTime(r.exportedAt);
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('自动备份', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (at.isNotEmpty)
                    Text('更新于 $at', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                ]),
                const SizedBox(height: 8),
                Text(
                  r == null
                      ? autoOn
                          ? '暂无自动备份。数据变更后 / 退出应用会自动生成 Download/zhiqing-backup-auto.txt（单文件滚动覆盖）。'
                          : '暂无自动备份。自动备份当前未开启：到「设置 → 数据与计划」打开后，数据变更 / 退出应用会自动保存到 Download 目录（单文件覆盖）。'
                      : 'Download/zhiqing-backup-auto.txt（单文件滚动覆盖，含 AI 配置）',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.6),
                ),
                if (r != null) ...[
                  const SizedBox(height: 10),
                  PrimaryButton(_busy ? '处理中…' : '从自动备份恢复', onPressed: _busy ? null : () {
                    setState(() {
                      _parsed = r.data;
                      _exportedAt = r.exportedAt;
                    });
                  }),
                ],
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 16),
      PrimaryButton(_busy ? '处理中…' : '选择备份文件（Download 目录 .txt）',
          onPressed: _busy ? null : _pick),
      const SizedBox(height: 14),
      if (_parsed == null)
        const Center(
          child: Text('自动备份可一键恢复；也可在「文件」应用的 Download 目录选择其他 .txt 备份文件',
              style: TextStyle(fontSize: 11, color: AppColors.textSub)),
        )
      else
        ..._summaryBody(),
    ];
  }

  List<Widget> _summaryBody() {
    final data = _parsed!;
    final s = BackupService.instance.buildBackupSummary(data);
    final at = BackupService.instance.fmtTime(_exportedAt);
    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('备份内容', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (at.isNotEmpty) Text(at, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
            const SizedBox(height: 10),
            _row('餐食计划', '${s.meals} 条'),
            _row('运动计划', '${s.exercises} 条'),
            _row('打卡天数', '${s.checkDays} 天 / ${s.checkCount} 次'),
            _row('临时任务', '${s.tempCount} 条'),
            if (s.entryCount > 0) _row('当日记录', '${s.entryCount} 条'),
            if (s.weightCount > 0) _row('体重记录', '${s.weightCount} 条'),
            _row('AI 配置', s.hasAiKey ? '包含 Key' : '无 Key'),
            if (data.planData.meta.planName.isNotEmpty) _row('计划名', data.planData.meta.planName),
            if (data.legacy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('⚠️ 旧格式备份（v1）：导入时将自动转换为快照格式，历史记录仍完整可用',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.5)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      PrimaryButton(_busy ? '合并中…' : '增量合并（推荐）', onPressed: _busy ? null : _mergeImport),
      const SizedBox(height: 8),
      const Center(
        child: Text('增量合并保留现有记录，按 id 合并，不覆盖设置/引导/用量',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ),
      const SizedBox(height: 16),
      DangerButton(_busy ? '覆盖中…' : '覆盖导入（全量替换）', onPressed: _busy ? null : _replaceImport),
    ];
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
