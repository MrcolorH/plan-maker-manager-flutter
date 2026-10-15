/// 周度减脂复盘报告页
/// 本地硬核数据秒开呈现 + AI 营养师复盘建议（真实异步无假等待）+ 长图分享/文本复制/外部Prompt双轨导出
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/onboarding.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/plan_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/weekly_report_utils.dart';
import '../../widgets/weekly_report_poster.dart';
import '../settings/ai_config_page.dart';

class WeeklyReportPage extends StatefulWidget {
  final int initialWeekOffset; // 0 = 本周，-1 = 上周
  const WeeklyReportPage({super.key, this.initialWeekOffset = 0});

  @override
  State<WeeklyReportPage> createState() => _WeeklyReportPageState();
}

class _WeeklyReportPageState extends State<WeeklyReportPage> {
  late int _weekOffset;
  WeeklyAdviceResult? _advice;
  bool _isGenerating = false;
  bool _isCapturing = false;
  String? _errorMessage;

  // 动态思考与小贴士轮播状态（真实在途时伴读，AI一返回立即销毁）
  int _elapsedSeconds = 0;
  int _tipIndex = 0;
  Timer? _timer;
  Timer? _tipTimer;

  final GlobalKey _posterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _weekOffset = widget.initialWeekOffset;
    _loadCachedAdvice();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tipTimer?.cancel();
    super.dispose();
  }

  String _cacheKey(WeeklyReportStats stats) => '${stats.startDate}_${stats.endDate}';

  void _loadCachedAdvice() {
    final plan = context.read<PlanProvider>().plan;
    final settings = context.read<SettingsProvider>().settings;
    final records = context.read<RecordProvider>().store;
    final profile = context.read<OnboardingProvider>().state.profile;

    final stats = calculateWeeklyReportStats(
      plan: plan,
      settings: settings,
      records: records,
      profile: profile,
      weekOffset: _weekOffset,
    );

    final cache = StorageService.instance.readMap(StorageService.kWeeklyReportCache);
    final key = _cacheKey(stats);
    if (cache.containsKey(key) && cache[key] is Map) {
      setState(() {
        _advice = WeeklyAdviceResult.fromJson(Map<String, dynamic>.from(cache[key] as Map));
        _errorMessage = null;
      });
    } else {
      setState(() {
        _advice = null;
        _errorMessage = null;
      });
    }
  }

  void _switchWeek(int offset) {
    if (_weekOffset == offset) return;
    setState(() {
      _weekOffset = offset;
      _errorMessage = null;
    });
    _loadCachedAdvice();
  }

  // ---------- 触发 AI 生成（纯真异步，绝不人为等待） ----------
  Future<void> _generateAdvice({bool force = false}) async {
    final settings = context.read<SettingsProvider>().settings;
    final plan = context.read<PlanProvider>().plan;
    final records = context.read<RecordProvider>().store;
    final profile = context.read<OnboardingProvider>().state.profile;

    final stats = calculateWeeklyReportStats(
      plan: plan,
      settings: settings,
      records: records,
      profile: profile,
      weekOffset: _weekOffset,
    );

    if (settings.ai.apiKey.trim().isEmpty) {
      _showNoApiKeyDialog(stats, profile);
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _elapsedSeconds = 0;
      _tipIndex = 0;
    });

    // 开启秒数计时器与小知识轮播伴读
    _timer?.cancel();
    _tipTimer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    _tipTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted) {
        setState(() {
          _tipIndex = (_tipIndex + 1) % kFatLossTips.length;
        });
      }
    });

    try {
      final summary = buildWeeklyStatsSummaryForAi(stats, profile: profile);
      // 发送真实 HTTP 请求
      final result = await AiService.instance.generateWeeklyAdvice(
        settings.ai,
        summary,
        onUsage: (u) => context.read<UsageProvider>().addUsage(u),
      );

      // AI 一返回，瞬间终止计时，立即呈现结果
      _timer?.cancel();
      _tipTimer?.cancel();

      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _advice = result;
      });

      // 写入本地持久缓存
      final cache = StorageService.instance.readMap(StorageService.kWeeklyReportCache);
      cache[_cacheKey(stats)] = result.toJson();
      await StorageService.instance.writeMap(StorageService.kWeeklyReportCache, cache);
    } catch (e) {
      _timer?.cancel();
      _tipTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ---------- 未配置 API Key 时的贴心弹窗 ----------
  void _showNoApiKeyDialog(WeeklyReportStats stats, UserProfile? profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.orangeBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('💡', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 10),
                const Text(
                  '尚未配置 AI 服务',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '知轻支持单机直接调用 AI 生成周报点评，也支持随时免费复制完整 Prompt 粘贴到外部大模型（如 DeepSeek、ChatGPT、Kimi 等）。',
              style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copyExternalPrompt(stats, profile);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      side: const BorderSide(color: AppColors.chartGray),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('复制 Prompt 去外部'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AiConfigPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('前往配置 API'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 复制外部提问 Prompt ----------
  void _copyExternalPrompt(WeeklyReportStats stats, UserProfile? profile) {
    final prompt = buildExternalAiPrompt(stats, profile: profile);
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 已复制 7 天数据与提问 Prompt，可直接粘贴给外部 AI 提问'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ---------- 导出并分享高清长图（系统原生分享） ----------
  Future<void> _exportAndShareImage(WeeklyReportStats stats) async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      // 留微小等待让布局完全静止
      await Future.delayed(const Duration(milliseconds: 60));
      final bytes = await captureBoundaryToPng(_posterKey, pixelRatio: 3.0);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('渲染周报长图失败，请重试');
      }

      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/zhiqing_weekly_report_${stats.startDate}.png');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '知轻 · 减脂周度复盘报告（${stats.weekLabel}）',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出图片失败：${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ---------- 复制 Markdown 完整文本 ----------
  void _copyMarkdownReport(WeeklyReportStats stats, UserProfile? profile) {
    final md = buildFullMarkdownReport(
      stats: stats,
      headline: _advice?.headline ?? '',
      review: _advice?.review ?? '',
      suggestions: _advice?.suggestions ?? [],
      encouragement: _advice?.encouragement ?? '',
      profile: profile,
    );
    Clipboard.setData(ClipboardData(text: md));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ 报告文本已复制到剪贴板，可粘贴至备忘录或外部对话'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ---------- 预览与复制 Prompt 弹窗 ----------
  void _showPromptPreviewModal(WeeklyReportStats stats, UserProfile? profile) {
    final prompt = buildExternalAiPrompt(stats, profile: profile);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '外部 AI 提问提示词',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.text),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copyExternalPrompt(stats, profile);
                    },
                    icon: const Icon(Icons.copy, size: 14, color: AppColors.primary),
                    label: const Text('一键复制', style: TextStyle(fontSize: 13, color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '包含过去 7 天的客观统计与角色指令，可粘贴至任意 AI（ChatGPT、DeepSeek、Kimi 等）提问追问：',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.tagBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.chartGray.withValues(alpha: 0.5)),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    child: SelectableText(
                      prompt,
                      style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.5, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _copyExternalPrompt(stats, profile);
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制并关闭', style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanProvider>().plan;
    final settings = context.watch<SettingsProvider>().settings;
    final records = context.watch<RecordProvider>().store;
    final profile = context.watch<OnboardingProvider>().state.profile;

    final stats = calculateWeeklyReportStats(
      plan: plan,
      settings: settings,
      records: records,
      profile: profile,
      weekOffset: _weekOffset,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('减脂周度复盘'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '复制外部提问 Prompt',
            icon: const Icon(Icons.chat_outlined, size: 20),
            onPressed: () => _showPromptPreviewModal(stats, profile),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 周期切换（本周 / 上周）
            _buildWeekToggleBar(),

            // 滚动海报主体
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  children: [
                    // 被 RepaintBoundary 包裹的海报本体，保证完整长图导出
                    RepaintBoundary(
                      key: _posterKey,
                      child: WeeklyReportPoster(
                        stats: stats,
                        advice: _advice,
                        isScreenshotMode: false,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // AI 点评触发区（若未生成或生成中）
                    _buildAiTriggerCard(stats, profile),
                  ],
                ),
              ),
            ),

            // 底部悬浮操作栏（长图分享 + 复制文本）
            _buildBottomActionBar(stats, profile),
          ],
        ),
      ),
    );
  }

  // ---------- 周期切换药丸 ----------
  Widget _buildWeekToggleBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.tagBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toggleItem(
              title: '本周',
              active: _weekOffset == 0,
              onTap: () => _switchWeek(0),
            ),
          ),
          Expanded(
            child: _toggleItem(
              title: '上周',
              active: _weekOffset == -1,
              onTap: () => _switchWeek(-1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleItem({
    required String title,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))]
            : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? AppColors.primary : AppColors.textSub,
          ),
        ),
      ),
    );
  }

  // ---------- AI 触发或正在生成状态卡片 ----------
  Widget _buildAiTriggerCard(WeeklyReportStats stats, UserProfile? profile) {
    // 正在生成中（真实异步等待，带计时器与小知识轮播）
    if (_isGenerating) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              'AI 营养师正在深度思考 (${_elapsedSeconds}s)...',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
            const SizedBox(height: 4),
            const Text(
              '结合您的 7 天数据，推演下周行动建议，完成后立即呈现',
              style: TextStyle(fontSize: 11, color: AppColors.textSub),
            ),
            const SizedBox(height: 16),
            // 减脂小知识伴读轮播
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Container(
                key: ValueKey(_tipIndex),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.tagBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kFatLossTips[_tipIndex],
                        style: const TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 生成失败报错卡片
    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
                const SizedBox(width: 6),
                const Text(
                  'AI 服务响应异常',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.danger),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_errorMessage!, style: const TextStyle(fontSize: 11, color: AppColors.text, height: 1.4)),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _generateAdvice(force: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('重试', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _copyExternalPrompt(stats, profile),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.chartGray),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('复制 Prompt 去网页版', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 尚未生成过建议时的吸睛生成入口卡片
    if (_advice == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          children: [
            const Text(
              '✨ 获取 AI 营养师复盘与下周减脂建议',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text),
            ),
            const SizedBox(height: 6),
            const Text(
              '基于以上 7 天真实硬核数据，智能分析饮食优缺点并制定下周针对性微习惯改善方案。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.45),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _generateAdvice(),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('生成 AI 点评与下周建议', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 已有建议时，提供重新生成微小入口
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: () => _generateAdvice(force: true),
          icon: const Icon(Icons.refresh, size: 14, color: AppColors.textSub),
          label: const Text('重新生成本周建议', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        ),
      ],
    );
  }

  // ---------- 底部悬浮操作栏（长图分享 + 复制文本） ----------
  Widget _buildBottomActionBar(WeeklyReportStats stats, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.chartGray.withValues(alpha: 0.5))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          // 备选操作：复制文本
          OutlinedButton.icon(
            onPressed: () => _copyMarkdownReport(stats, profile),
            icon: const Icon(Icons.copy, size: 15, color: AppColors.text),
            label: const Text('复制文本', style: TextStyle(fontSize: 13, color: AppColors.text)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.chartGray),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 10),

          // 主操作：保存/分享完整长图
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isCapturing ? null : () => _exportAndShareImage(stats),
              icon: _isCapturing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.share_outlined, size: 16),
              label: Text(
                _isCapturing ? '正在生成长图...' : '📸 保存 / 分享完整长图',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
