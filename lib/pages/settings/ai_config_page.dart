/// AI 服务配置页（对应 settings/ai-config.vue）
/// 服务商预设 / 接口地址 / 模型 / API Key / 测试连接 / 余额查询 / 用量统计
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/onboarding.dart';
import '../../models/settings.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  late TextEditingController _endpointCtrl;
  late TextEditingController _keyCtrl;
  late TextEditingController _modelCtrl;
  bool _testing = false;
  bool _queryingBalance = false;
  String? _balanceText;

  @override
  void initState() {
    super.initState();
    final ai = context.read<SettingsProvider>().settings.ai;
    _endpointCtrl = TextEditingController(text: ai.endpoint);
    _keyCtrl = TextEditingController(text: ai.apiKey);
    _modelCtrl = TextEditingController(text: ai.model);
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  String get _provider => context.read<SettingsProvider>().settings.ai.provider;

  AiConfig _currentConfig() => AiConfig(
        provider: _provider,
        endpoint: _endpointCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
      );

  Future<void> _save() async {
    await context.read<SettingsProvider>().updateAI({
      'endpoint': _endpointCtrl.text.trim(),
      'apiKey': _keyCtrl.text.trim(),
      'model': _modelCtrl.text.trim(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('AI 配置已保存（仅存本机，不会上传）')));
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final usage = context.read<UsageProvider>();
      await AiService.instance.testAI(_currentConfig(), onUsage: usage.addUsage);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('连接成功 ✓ 测试问答正常返回')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _queryBalance() async {
    setState(() {
      _queryingBalance = true;
      _balanceText = null;
    });
    try {
      final data = await AiService.instance.queryBalance(_currentConfig());
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _queryingBalance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<SettingsProvider>().settings.ai;
    final usage = context.watch<UsageProvider>().usage;
    final cost = context.watch<UsageProvider>().estimateTotalCost();
    return Scaffold(
      appBar: AppBar(title: const Text('AI 服务')),
      backgroundColor: AppColors.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _Label('服务商'),
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAiProviders.map((p) {
                final selected = _provider == p.value;
                return ChoiceChip(
                  label: Text(p.label, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => context.read<SettingsProvider>().switchProvider(p.value),
                  selectedColor: AppColors.primaryBg,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textSub,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          const _Label('接口地址（OpenAI 兼容）'),
          _field(_endpointCtrl, 'https://api.deepseek.com'),
          const _Label('API Key（仅存本机）'),
          _field(_keyCtrl, 'sk-...', obscure: true),
          const _Label('模型名'),
          _field(_modelCtrl, 'deepseek-v4-flash'),
          const SizedBox(height: 12),
          PrimaryButton('保存配置', onPressed: _save),
          const SizedBox(height: 10),
          PlainButton(
            _testing ? '测试中…' : '测试连接（实际发一句问答验证）',
            onPressed: _testing ? null : _test,
          ),
          const SizedBox(height: 16),
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
                Text('模型：${ai.provider} · ${ai.model}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
        ],
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
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清零', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) usageP.resetUsage();
  }

  Widget _field(TextEditingController ctrl, String hint, {bool obscure = false}) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          isDense: true,
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.chartGray),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w600)),
    );
  }
}
