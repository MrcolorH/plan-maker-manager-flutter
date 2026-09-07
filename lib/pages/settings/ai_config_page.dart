/// AI 服务配置管理页（对应 settings/ai-config）。
/// 多服务商档案列表（同时仅启用一个）；已配置项只读不展示明文；改 = 添加新配置或删除重配。
/// 见 spec/ai-profile-design.md
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/onboarding.dart';
import '../../models/settings.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_config_sheet.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  bool _testing = false;
  bool _queryingBalance = false;
  String? _balanceText;
  String? _statusText;

  AiProfile? get _active => context.read<SettingsProvider>().settings.activeProfile;

  String _label(String provider) {
    final hit = kAiProviders.where((x) => x.value == provider).toList();
    return hit.isNotEmpty ? hit.first.label : provider;
  }

  String _p2(int n) => n.toString().padLeft(2, '0');

  String _fmtTime(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
  }

  /// 添加新配置：复用配置弹层（仅新建模式），保存即新增档案并启用
  Future<void> _add() async {
    final r = await showAiConfigSheet(
      context,
      title: '添加 AI 服务商',
      message: '填好 API Key 后保存即启用；同一时刻仅一个服务商生效。',
      confirmText: '保存并启用',
    );
    if (!mounted) return;
    if (r == AiConfigSheetResult.configured) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存并启用新配置（仅存本机，不会上传）')));
    }
  }

  /// 切换到指定档案（只改激活指针，endpoint/key/model 整体跟随）
  Future<void> _activate(AiProfile p) async {
    final current = _active;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换 AI 服务商'),
        content: Text('切换到「${_label(p.provider)}」？\n当前启用：${current == null ? '无' : _label(current.provider)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<SettingsProvider>().activateAiProfile(p.id);
  }

  Future<bool> _confirmRemove(AiProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除此配置'),
        content: const Text('删除后无法恢复，需重新填写 API Key 才能再次使用。确定删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _remove(AiProfile p) async {
    final ok = await _confirmRemove(p);
    if (ok && mounted) await context.read<SettingsProvider>().removeAiProfile(p.id);
  }

  /// 测试连接作用于当前激活档案（不展示明文 key 也能测）
  Future<void> _test() async {
    final active = _active;
    if (active == null) {
      setState(() => _statusText = '请先添加并启用一个 AI 配置');
      return;
    }
    setState(() => _testing = true);
    try {
      final usage = context.read<UsageProvider>();
      await AiService.instance.testAI(active.toAiConfig(), onUsage: usage.addUsage);
      if (!mounted) return;
      setState(() => _statusText = '连接成功 ✓ 测试问答正常返回');
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _queryBalance() async {
    final active = _active;
    if (active == null) {
      setState(() => _statusText = '请先添加并启用一个 AI 配置');
      return;
    }
    setState(() {
      _queryingBalance = true;
      _balanceText = null;
    });
    try {
      final data = await AiService.instance.queryBalance(active.toAiConfig());
      final infos = (data['balance_infos'] as List?) ?? [];
      if (infos.isEmpty) throw Exception('服务未返回余额信息');
      final sb = StringBuffer();
      for (final it in infos) {
        if (it is! Map) continue;
        final cur = it['currency'] ?? '';
        final total = it['total_balance'] ?? '--';
        sb.writeln('$cur：¥$total');
      }
      if (!mounted) return;
      setState(() => _balanceText = sb.toString().trim());
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusText = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _queryingBalance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SettingsProvider>();
    final profiles = sp.settings.aiProfiles;
    final activeId = sp.settings.activeAiProfileId;
    final usage = context.watch<UsageProvider>().usage;
    final cost = context.watch<UsageProvider>().estimateTotalCost();
    final active = sp.settings.activeProfile;

    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text('已配置的服务商（同时仅启用一个）',
                style: TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w600)),
          ),
          if (profiles.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(16),
              child: const Text(
                '还没有配置 AI 服务商。点击下方「添加新配置」即可开始 —— 需要你自己的 API Key（DeepSeek / Kimi 等）。',
                style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.5),
              ),
            )
          else
            ...profiles.map((p) => _profileTile(p, p.id == activeId)),
          const SizedBox(height: 12),
          PrimaryButton('+ 添加新配置', onPressed: _add),
          const SizedBox(height: 16),
          if (_statusText != null) ...[
            Text(_statusText!, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(height: 8),
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('余额查询', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Tag('仅 DeepSeek', color: 'orange'),
                    const Spacer(),
                    if (_queryingBalance)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      GestureDetector(
                        onTap: _queryBalance,
                        child: const Text('查询', style: TextStyle(fontSize: 13, color: AppColors.primary)),
                      ),
                  ],
                ),
                if (_balanceText != null) ...[
                  const SizedBox(height: 8),
                  Text(_balanceText!, style: const TextStyle(fontSize: 14, color: AppColors.primary)),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('本 App 用量', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _confirmResetUsage(),
                      child: const Text('清零统计', style: TextStyle(fontSize: 12, color: AppColors.danger)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('调用 ${usage.calls} 次 · 输入 ${usage.promptTokens} · 输出 ${usage.completionTokens} tokens',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
                const SizedBox(height: 2),
                Text('估算费用 ¥${cost.toStringAsFixed(4)}（按 ${kPrices['inputMiss']}/${kPrices['inputHit']}/${kPrices['output']} 元/百万 tokens）',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                const SizedBox(height: 4),
                Text(active == null ? '模型：未配置' : '模型：${_label(active.provider)} · ${active.model}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                const SizedBox(height: 10),
                PlainButton(
                  _testing ? '测试中…' : '测试连接（实际发一句问答验证）',
                  onPressed: _testing ? null : _test,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTile(AiProfile p, bool isActive) {
    final label = _label(p.provider);
    final time = _fmtTime(p.createdAt);
    final sp = context.read<SettingsProvider>();
    return Dismissible(
      key: ValueKey(p.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: AppColors.danger.withValues(alpha: 0.12),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      confirmDismiss: (_) => _confirmRemove(p),
      onDismissed: (_) => sp.removeAiProfile(p.id),
      child: AppCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isActive ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isActive ? AppColors.primary : AppColors.textSub,
          ),
          title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          subtitle: Text('配置于 $time', style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.textSub),
            onPressed: () => _remove(p),
          ),
          onTap: isActive ? null : () => _activate(p),
        ),
      ),
    );
  }

  Future<void> _confirmResetUsage() async {
    final usageP = context.read<UsageProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('清零本 App 的 AI 用量统计？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清零', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) usageP.resetUsage();
  }
}
