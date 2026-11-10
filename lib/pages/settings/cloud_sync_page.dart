import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/records.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/preset_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/auto_backup_service.dart';
import '../../services/backup_service.dart';
import '../../services/storage_service.dart';
import '../../services/sync_service.dart';

class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});

  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  final _syncService = SyncService();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  bool _isRegisterMode = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = _syncService.serverUrl;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final inviteCode = _inviteCodeController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showToast('账号和密码不能为空');
      return;
    }

    if (_isRegisterMode && inviteCode.isEmpty) {
      _showToast('注册必须填写邀请码');
      return;
    }

    setState(() => _isLoading = true);

    final res = _isRegisterMode
        ? await _syncService.register(username: username, password: password, inviteCode: inviteCode)
        : await _syncService.login(username: username, password: password);

    setState(() => _isLoading = false);

    if (res['success'] == true) {
      _showToast(_isRegisterMode ? '注册并登录成功！' : '登录成功！');
      _usernameController.clear();
      _passwordController.clear();
      _inviteCodeController.clear();
    } else {
      _showToast(res['message']?.toString() ?? '操作失败');
    }
  }

  Future<void> _showBindQqDialog() async {
    setState(() => _isLoading = true);
    final res = await _syncService.getQqBindCode();
    setState(() => _isLoading = false);

    if (res['success'] != true) {
      _showToast(res['message']?.toString() ?? '获取绑定码失败');
      return;
    }

    final code = res['code']?.toString() ?? '';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.blue),
            SizedBox(width: 8),
            Text('QQ 账号配对'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请在手机 QQ 私聊您的 QQMatrix 机器人发送：', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '绑定 $code',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '绑定 $code'));
                      _showToast('指令已复制到剪贴板');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ 配对码 5 分钟内有效。配对成功后，机器人识别的午餐照片将自动同步至当前账本。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualSync() async {
    setState(() => _isLoading = true);
    final recordProvider = context.read<RecordProvider>();
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();
    final count = await _syncService.syncInboxToLocal(
      recordProvider,
      aiConfig: settings.ai,
      onUsage: usage.addUsage,
    );
    setState(() => _isLoading = false);

    if (count > 0) {
      _showToast('成功同步 $count 条来自 QQ 机器人的打卡记录！');
    } else {
      _showToast('云端收件箱暂无新的待录入记录');
    }
  }

  Future<void> _backupToCloud() async {
    setState(() => _isLoading = true);
    try {
      final data = captureBackupData(
        plan: context.read<PlanProvider>(),
        record: context.read<RecordProvider>(),
        settings: context.read<SettingsProvider>(),
        onboarding: context.read<OnboardingProvider>(),
        usage: context.read<UsageProvider>(),
      );
      final jsonStr = encodeBackup(data);
      final payload = jsonDecode(jsonStr) as Map<String, dynamic>;
      final res = await _syncService.uploadSnapshot(payload: payload);
      if (res['success'] == true) {
        _showToast('全量数据已成功备份到云端！');
      } else {
        _showToast(res['message']?.toString() ?? '备份失败');
      }
    } catch (e) {
      _showToast('备份出错: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreFromCloud() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端恢复数据'),
        content: const Text(
            '从云端拉取全量快照将覆盖本地现有的计划与记录。\n• 为保障资产安全，云端快照不含 API Key 密钥，本地已有密钥将受到保护自动保留。\n• 恢复前本地数据会自动在手机留底保存一份。确定要继续恢复吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认覆盖恢复', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final res = await _syncService.fetchSnapshot();
      if (res['success'] != true || res['payload'] == null) {
        _showToast(res['message']?.toString() ?? '获取云端快照失败');
        return;
      }
      final payload = res['payload'];
      final rawText = payload is String ? payload : jsonEncode(payload);
      final parseRes = BackupService.instance.parseBackupText(rawText);
      if (!parseRes.ok || parseRes.data == null) {
        _showToast('云端快照解析失败: ${parseRes.error}');
        return;
      }

      final data = parseRes.data!;
      // 本地先留底一份
      try {
        final currentData = captureBackupData(
          plan: context.read<PlanProvider>(),
          record: context.read<RecordProvider>(),
          settings: context.read<SettingsProvider>(),
          onboarding: context.read<OnboardingProvider>(),
          usage: context.read<UsageProvider>(),
        );
        await BackupService.instance.exportBackup(currentData);
      } catch (_) {}

      final planP = context.read<PlanProvider>();
      final recordP = context.read<RecordProvider>();
      final settingsP = context.read<SettingsProvider>();
      final obP = context.read<OnboardingProvider>();
      final usageP = context.read<UsageProvider>();

      await planP.replacePlan(data.planData);
      await recordP.replaceRecords(BackupLike(
        checkRecords: data.checkRecords,
        mealAdjust: data.mealAdjust,
        tempTasks: data.tempTasks,
        extraFoods: data.extraFoods,
        dayEntries: data.dayEntries,
        weightRecords: data.weightRecords,
      ));
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

      _showToast('成功从云端恢复全量数据！');
    } catch (e) {
      _showToast('恢复失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _syncService.isLoggedIn;

    return Scaffold(
      appBar: AppBar(
        title: const Text('云端账号与收件箱同步'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 服务端地址配置卡片
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.dns_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('同步服务器地址', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://api.zhiqing.fun',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _syncService.setServerUrl(_serverUrlController.text);
                        _showToast('服务器地址已更新');
                      },
                      child: const Text('保存地址'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 账号状态或登录/注册卡片
          if (isLoggedIn) ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _syncService.currentUsername ?? '已登录',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const Text('云端同步已连接 (单机离线优先)', style: TextStyle(fontSize: 12, color: Colors.green)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _syncService.logout();
                            setState(() {});
                            _showToast('已退出登录');
                          },
                          child: const Text('退出', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('QQ 机器人收件箱', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('绑定手机 QQ 后，机器人识别的餐品热量将自动写入信箱并无感录入打卡。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _showBindQqDialog,
                            icon: const Icon(Icons.link),
                            label: const Text('绑定 QQ 机器人'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _manualSync,
                            icon: const Icon(Icons.sync),
                            label: const Text('立即检查同步'),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    const Text('全量云端备份与恢复', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('将本机计划、历史打卡、基础设置及预设安全备份至云端（已自动排除 API Key 敏感信息）；换机或误删时可一键恢复。', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _backupToCloud,
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: const Text('备份到云端'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange.shade800),
                            onPressed: _isLoading ? null : _restoreFromCloud,
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: const Text('从云端恢复'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isRegisterMode ? '注册知轻云端账号' : '登录知轻云端账号',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _isRegisterMode = !_isRegisterMode),
                          child: Text(_isRegisterMode ? '已有账号？去登录' : '没有账号？使用邀请码注册'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: '用户名', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
                    ),
                    if (_isRegisterMode) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _inviteCodeController,
                        decoration: const InputDecoration(
                          labelText: '邀请码',
                          hintText: '私有部署邀请码 (如 ZQ8888)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleAuth,
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_isRegisterMode ? '立即注册' : '立即登录'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
