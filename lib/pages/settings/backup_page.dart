/// 本地数据与备份页（子页面）
/// 集合本地三大同类能力：
/// 1. 自动备份（开启/关闭开关、状态展示、一键载入恢复）
/// 2. 导出备份（.txt 全量快照 → 手机存储根目录 Download 目录，支持分享）
/// 3. 导入备份（选择本地 .txt 备份文件，支持增量合并与覆盖导入）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/auto_backup_service.dart';
import '../../services/backup_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class BackupPage extends StatefulWidget {
  final String? mode; // 'export' | 'import' | null
  const BackupPage({super.key, this.mode});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  BackupData? _parsed;
  String? _exportedAt;
  late Future<ParseResult?> _autoParsed = _loadAutoBackup();

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

  void _reloadAutoBackup() {
    setState(() {
      _autoParsed = _loadAutoBackup();
    });
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
      _reloadAutoBackup();
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('关闭', style: TextStyle(color: AppColors.textSub)),
            ),
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
        SnackBar(content: Text('导出失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('备份解析成功，请在下方确认内容并选择恢复方式')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
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
      if (data.userPresets.isNotEmpty) {
        final cur = StorageService.instance.readMap(StorageService.kUserPresets);
        cur.addAll(data.userPresets);
        await StorageService.instance.writeMap(StorageService.kUserPresets, cur);
      }
      if (data.userFoods.isNotEmpty) {
        final curF = StorageService.instance.readMap(StorageService.kUserFoods);
        curF.addAll(data.userFoods);
        await StorageService.instance.writeMap(StorageService.kUserFoods, curF);
      }
      if (mounted) context.read<PresetProvider>().refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已增量合并：相同 id 覆盖更新，历史记录保留')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
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
            '将用备份数据整体替换当前：计划、打卡记录、基础设置、引导状态、用量统计。\n• 为保障资产安全，备份文件已排除 API Key（本地若已有配置好的密钥将自动保留）。\n• 替换前会自动把当前数据另存一份带时间戳的备份到 Download 目录，导错了还能找回来。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
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
      if (data.userPresets.isNotEmpty) {
        await StorageService.instance.writeMap(StorageService.kUserPresets, data.userPresets);
      }
      if (data.userFoods.isNotEmpty) {
        await StorageService.instance.writeMap(StorageService.kUserFoods, data.userFoods);
      }
      if (mounted) context.read<PresetProvider>().refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(safetyTip ?? '已覆盖导入，数据已替换')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmClearAll() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text(
            '⚠️ 清空全部数据（计划/记录/设置）前，会先把当前数据另存一份带时间戳的备份到 Download 目录，之后仍可在此处重新恢复。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _busy = true);
              final planP = context.read<PlanProvider>();
              final recordP = context.read<RecordProvider>();
              final settingsP = context.read<SettingsProvider>();
              try {
                await BackupService.instance.exportBackup(_snapshot());
              } catch (_) {}
              await planP.clearPlan();
              await recordP.clearRecords();
              await settingsP.clearAll();
              if (mounted) {
                setState(() => _busy = false);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已清空全部数据；清空前数据已自动留底备份到 Download 目录')));
                Navigator.pop(context);
              }
            },
            child: const Text('全部清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地备份与恢复')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildBody(),
      ),
    );
  }

  List<Widget> _buildBody() {
    final autoOn = context.watch<SettingsProvider>().settings.autoBackupEnabled;
    return [
      // 1. 自动备份
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew_rounded, size: 20, color: context.primaryColor),
                const SizedBox(width: 8),
                const Text('自动备份', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                Switch(
                  value: autoOn,
                  activeThumbColor: context.primaryColor,
                  onChanged: (v) =>
                      context.read<SettingsProvider>().update({'autoBackupEnabled': v}),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              autoOn
                  ? '已开启：数据变更后或每次退出应用，都会自动覆盖更新系统 Download 目录里的 zhiqing-backup-auto.txt（单文件滚动留存，含计划、打卡与设置配置）。'
                  : '已关闭：开启后，每次数据变更或退出应用会自动保存最新备份到系统 Download 目录。',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, thickness: 0.6, color: Color(0xFFEEEEEE)),
            ),
            FutureBuilder<ParseResult?>(
              future: _autoParsed,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Text('正在读取自动备份…',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub));
                }
                final r = snap.data;
                final at = r == null ? '' : BackupService.instance.fmtTime(r.exportedAt);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('自动备份状态',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        if (at.isNotEmpty)
                          Text('更新于 $at',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r == null
                          ? (autoOn
                              ? '暂无自动备份文件（数据变更或退出应用时将自动生成）。'
                              : '暂无自动备份文件。')
                          : 'Download/zhiqing-backup-auto.txt（单文件滚动覆盖，已安全排除 API Key）',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
                    ),
                    if (r != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _parsed = r.data;
                                  _exportedAt = r.exportedAt;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已载入自动备份数据，请在下方选择恢复方式')),
                                );
                              },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('从自动备份恢复', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // 2. 导出备份
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.file_upload_outlined, size: 20, color: context.primaryColor),
                const SizedBox(width: 8),
                const Text('导出备份', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '• 减脂计划（餐食 + 运动）\n• 全部打卡 / 加餐 / 调整记录\n• 热量设置与模型配置（已排除 API Key）\n• 引导状态与用量统计',
              style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.7),
            ),
            const SizedBox(height: 8),
            const Text(
              '导出为 .txt 全量快照文件，保存到手机存储的 Download 目录，可用「文件管理」查看或分享到微信/网盘留档。',
              style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
            ),
            const SizedBox(height: 12),
            PrimaryButton(_busy ? '导出中…' : '导出备份到本地 / 分享', onPressed: _busy ? null : _export),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // 3. 导入备份
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.file_download_outlined, size: 20, color: context.primaryColor),
                const SizedBox(width: 8),
                const Text('导入备份', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '从手机存储的 Download 目录或其他应用接收的 .txt 备份文件中恢复数据。可选择「增量合并」保留历史，或「覆盖导入」完整替换。',
              style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              _busy ? '处理中…' : '选择备份文件（Download 目录 .txt）',
              onPressed: _busy ? null : _pick,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // 4. 解析结果展示（如果有载入或选择的文件）
      if (_parsed != null) ..._summaryBody(),

      const SizedBox(height: 24),
      Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.delete_forever_outlined, size: 16),
          label: const Text('清空全部数据并重置', style: TextStyle(fontSize: 13)),
          onPressed: _busy ? null : _confirmClearAll,
        ),
      ),
      const SizedBox(height: 8),
      const Center(
        child: Text('知轻 · 单机离线优先，数据仅存本机',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ),
      const SizedBox(height: 16),
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
                const Text('待恢复备份概要', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (at.isNotEmpty)
                  Text(at, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() {
                    _parsed = null;
                    _exportedAt = null;
                  }),
                  child: const Icon(Icons.close, size: 18, color: AppColors.textSub),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _row('餐食计划', '${s.meals} 条'),
            _row('运动计划', '${s.exercises} 条'),
            _row('打卡天数', '${s.checkDays} 天 / ${s.checkCount} 次'),
            _row('临时任务', '${s.tempCount} 条'),
            if (s.entryCount > 0) _row('当日记录', '${s.entryCount} 条'),
            if (s.weightCount > 0) _row('体重记录', '${s.weightCount} 条'),
            _row('AI 配置', s.hasAiKey ? '包含 Key (旧版备份)' : (s.hasAiConfig ? '已安全脱敏 (不含 Key)' : '未配置')),
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
      const SizedBox(height: 14),
      PrimaryButton(_busy ? '合并中…' : '增量合并（推荐）', onPressed: _busy ? null : _mergeImport),
      const SizedBox(height: 6),
      const Center(
        child: Text('增量合并保留现有记录，按 id 合并，不覆盖设置/引导/用量',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ),
      const SizedBox(height: 12),
      DangerButton(_busy ? '覆盖中…' : '覆盖导入（全量替换）', onPressed: _busy ? null : _replaceImport),
      const SizedBox(height: 6),
      const Center(
        child: Text('覆盖导入将全量替换当前数据（替换前会自动安全留底到 Download 目录）',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      ),
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
