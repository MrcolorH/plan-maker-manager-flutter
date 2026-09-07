/// AI 配置弹层：未配置 AI 服务时，任意 AI 能力入口统一弹出
/// 页内填写服务商 / 接口地址 / API Key / 模型 → 可测试连接 → 保存后立即继续原操作
/// 仅「新建」模式：填服务商 / 接口地址 / API Key / 模型 → 测试连接 → 保存即新增一条档案并启用。
/// 切换服务商 chip 只更新本地表单（不持久化），保存时才整体落库（SettingsProvider.addAiProfile），杜绝半成品配置。
/// 已配置项不可编辑（改 = 删了重配），见 spec/ai-profile-design.md。
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
  late String _selectedProvider; // 当前表单选中的服务商（仅本地，不持久化）

  @override
  void initState() {
    super.initState();
    // 新建模式：以当前激活档案（或默认 deepseek）的预设预填 endpoint/model，key 始终清空
    final sp = context.read<SettingsProvider>();
    _selectedProvider = sp.settings.activeProfile?.provider ?? kAiProviders.first.value;
    final preset = kAiProviders.where((x) => x.value == _selectedProvider).toList();
    final e = preset.isNotEmpty ? preset.first.endpoint : '';
    final m = preset.isNotEmpty ? preset.first.model : '';
    _endpointCtrl = TextEditingController(text: e);
    _keyCtrl = TextEditingController(text: ''); // 新配置必须重新填 key，不预填/不泄露
    _modelCtrl = TextEditingController(text: m);
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  /// 回调里使用（不建立订阅）：provider 取本地选中，endpoint/key/model 取表单
  AiConfig _currentConfig() => AiConfig(
        provider: _selectedProvider,
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

  /// 仅更新本地表单（按预设预填 endpoint/model、清空 key），**不持久化**——
  /// 半成品配置问题从源头消除；保存时才整体落库为一条新档案
  void _onProviderPicked(String value) {
    final preset = kAiProviders.where((x) => x.value == value).toList();
    setState(() {
      _selectedProvider = value;
      if (preset.isNotEmpty) {
        _endpointCtrl.text = preset.first.endpoint;
        _modelCtrl.text = preset.first.model;
      }
      _keyCtrl.text = ''; // 切换服务商必须重新填 key
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
    final cfg = _currentConfig();
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      // 保存即新增一条档案并立即启用（上限校验 / 必填校验在 provider 内）
      await context.read<SettingsProvider>().addAiProfile(cfg);
      if (!mounted) return;
      Navigator.pop(context, AiConfigSheetResult.configured);
    } catch (e) {
      if (!mounted) return;
      _setStatus(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final provider = _selectedProvider;
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
                  onSelected: (_) => _onProviderPicked(p.value),
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
