/// AI 配置弹层：未配置 AI 服务时，任意 AI 能力入口统一弹出
/// 页内填写服务商 / 接口地址 / API Key / 模型 → 可测试连接 → 保存后立即继续原操作
/// 复用现有 SettingsProvider（switchProvider / updateAI）与 AiService.testAI，不改设置页
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../providers/usage_provider.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';

/// 弹层关闭结果：已配置 / 取消 / 跳过（仅引导页 allowSkip 时出现）
enum AiConfigSheetResult { configured, cancelled, skipped }

/// 弹出 AI 配置弹层，返回用户的选择结果
Future<AiConfigSheetResult> showAiConfigSheet(
  BuildContext context, {
  String title = '未配置 AI 服务',
  String? message,
  String confirmText = '保存并使用',
  bool allowSkip = false,
  String skipText = '暂不，手动模式',
}) {
  return showModalBottomSheet<AiConfigSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AiConfigSheet(
      title: title,
      message: message,
      confirmText: confirmText,
      allowSkip: allowSkip,
      skipText: skipText,
    ),
  ).then((v) => v ?? AiConfigSheetResult.cancelled);
}

/// AI 能力统一前置校验：未配置时弹配置层，配置成功后返回 true（调用方继续原操作）
Future<bool> ensureAiConfigured(
  BuildContext context, {
  String title = '未配置 AI 服务',
  String? message = 'AI 能力需要你自己的 API Key（DeepSeek 等），配置后立即继续。',
  String confirmText = '保存并使用',
}) async {
  final configured = context.read<SettingsProvider>().settings.ai.hasConfig;
  if (configured) return true;
  if (!context.mounted) return false;
  final r = await showAiConfigSheet(
    context,
    title: title,
    message: message,
    confirmText: confirmText,
  );
  return r == AiConfigSheetResult.configured;
}

class _AiConfigSheet extends StatefulWidget {
  final String title;
  final String? message;
  final String confirmText;
  final bool allowSkip;
  final String skipText;

  const _AiConfigSheet({
    required this.title,
    this.message,
    required this.confirmText,
    required this.allowSkip,
    required this.skipText,
  });

  @override
  State<_AiConfigSheet> createState() => _AiConfigSheetState();
}

class _AiConfigSheetState extends State<_AiConfigSheet> {
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  bool _testing = false;
  bool _saving = false;
  String? _status;
  bool _statusOk = false;

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

  /// 仅用于 build 中读取（会订阅变化）
  AiConfig get _ai => context.watch<SettingsProvider>().settings.ai;

  /// 回调里使用（不建立订阅）
  AiConfig _currentConfig() => AiConfig(
        provider: context.read<SettingsProvider>().settings.ai.provider,
        endpoint: _endpointCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
        model: _modelCtrl.text.trim(),
      );

  void _setStatus(String text, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _status = text;
      _statusOk = ok;
    });
  }

  Future<void> _switchProvider(String value) async {
    final sp = context.read<SettingsProvider>();
    await sp.switchProvider(value);
    if (!mounted) return;
    final ai = sp.settings.ai;
    setState(() {
      _endpointCtrl.text = ai.endpoint;
      _modelCtrl.text = ai.model;
      _status = null;
    });
  }

  Future<void> _test() async {
    final cfg = _currentConfig();
    if (cfg.apiKey.isEmpty || cfg.endpoint.isEmpty) {
      _setStatus('请先填写接口地址与 API Key');
      return;
    }
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      final usage = context.read<UsageProvider>();
      await AiService.instance.testAI(cfg, onUsage: usage.addUsage);
      _setStatus('连接成功 ✓ 测试问答正常返回', ok: true);
    } catch (e) {
      _setStatus(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final endpoint = _endpointCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (endpoint.isEmpty || key.isEmpty) {
      _setStatus('请填写接口地址与 API Key');
      return;
    }
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await context.read<SettingsProvider>().updateAI({
        'endpoint': endpoint,
        'apiKey': key,
        'model': model,
      });
      if (!mounted) return;
      Navigator.pop(context, AiConfigSheetResult.configured);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final provider = _ai.provider;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.chartGray,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, AiConfigSheetResult.cancelled),
                  child: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                ),
              ],
            ),
            if (widget.message != null) ...[
              const SizedBox(height: 6),
              Text(widget.message!,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5)),
            ],
            const SizedBox(height: 8),
            const _FieldLabel('服务商'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kAiProviders.map((p) {
                final selected = provider == p.value;
                return ChoiceChip(
                  label: Text(p.label, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => _switchProvider(p.value),
                  selectedColor: AppColors.primaryBg,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textSub,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
            const _FieldLabel('接口地址（OpenAI 兼容）'),
            _field(_endpointCtrl, 'https://api.deepseek.com'),
            const _FieldLabel('API Key（仅存本机）'),
            _field(_keyCtrl, 'sk-...', obscure: true),
            const _FieldLabel('模型名'),
            _field(_modelCtrl, 'deepseek-v4-flash'),
            if (_status != null) ...[
              const SizedBox(height: 6),
              Text(_status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusOk ? AppColors.primary : AppColors.danger,
                  )),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              _saving ? '保存中…' : widget.confirmText,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 8),
            PlainButton(
              _testing ? '测试中…' : '测试连接（实际发一句问答验证）',
              onPressed: _testing ? null : _test,
            ),
            if (widget.allowSkip) ...[
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context, AiConfigSheetResult.skipped),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(widget.skipText,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {bool obscure = false}) {
    return AppCard(
      margin: EdgeInsets.zero,
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSub, fontWeight: FontWeight.w600)),
    );
  }
}
