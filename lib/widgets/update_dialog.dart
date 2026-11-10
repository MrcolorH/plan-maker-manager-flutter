import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

/// 升级弹窗：展示版本信息、更新说明、镜像加速开关、下载进度与一键安装
class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0.0;
  String _progressText = '';
  String? _errorMessage;
  bool _useMirror = true; // 默认开启国内镜像加速
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  String _resolveDownloadUrl(String originalUrl) {
    if (!_useMirror) return originalUrl;
    // 使用高速稳定的 GitHub Release 加速代理
    return 'https://ghfast.top/$originalUrl';
  }

  Future<void> _startDownload() async {
    final apkUrl = widget.info.apkUrl;
    if (apkUrl == null || apkUrl.isEmpty) {
      setState(() {
        _errorMessage = '未检测到直连安装包，您可以直接前往 Release 发布页下载：';
      });
      return;
    }

    setState(() {
      _downloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _progressText = '正在建立下载连接...';
    });

    final targetUrl = _resolveDownloadUrl(apkUrl);
    _cancelToken = CancelToken();

    try {
      final file = await AppUpdateService.instance.downloadApk(
        targetUrl,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            final p = received / total;
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
            final percent = (p * 100).toInt();
            setState(() {
              _progress = p;
              _progressText = '$recMb MB / $totMb MB ($percent%)';
            });
          } else {
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progressText = '已下载 $recMb MB';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _progressText = '下载完成，正在唤起安装程序...';
      });

      // 调起 Android 安装器
      if (Platform.isAndroid) {
        await AppUpdateService.instance.installApk(file.path);
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _progressText = '已保存到: ${file.path}';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _errorMessage = '自动下载安装包失败，您可以直接前往 Release 发布页下载：';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.hasUpdate ? '发现新版本 v${info.latestVersion}' : '当前为最新版本 v${info.currentVersion}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  info.hasUpdate ? '当前版本：v${info.currentVersion}' : '发布时间：${info.publishedAt}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (info.apkSizeFormatted.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.file_present_rounded, size: 14, color: AppColors.textSub),
                    const SizedBox(width: 4),
                    Text(
                      '安装包大小：${info.apkSizeFormatted}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                    ),
                  ],
                ),
              ),

            // 更新说明区域
            const Text('更新说明：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                child: Text(
                  info.notes,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF374151), height: 1.4),
                ),
              ),
            ),

            if (_downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.grey.shade200,
                  color: AppColors.primary,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _progressText,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              // 国内加速下载开关
              InkWell(
                onTap: () => setState(() => _useMirror = !_useMirror),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _useMirror ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        size: 18,
                        color: _useMirror ? AppColors.primary : AppColors.textSub,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '启用国内镜像高速下载（推荐）',
                        style: TextStyle(fontSize: 12, color: AppColors.textSub),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 15, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.maxFinite,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SelectableText(
                        info.htmlUrl.isNotEmpty
                            ? info.htmlUrl
                            : 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases',
                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: const Text('复制链接', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            final targetUrl = info.htmlUrl.isNotEmpty
                                ? info.htmlUrl
                                : 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases';
                            Clipboard.setData(ClipboardData(text: targetUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制 Release 页面链接')),
                            );
                          },
                        ),
                        const SizedBox(width: 4),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                          label: const Text('浏览器打开', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            final targetUrl = info.htmlUrl.isNotEmpty
                                ? info.htmlUrl
                                : 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases';
                            AppUpdateService.openBrowser(targetUrl);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(info.hasUpdate ? '稍后再说' : '关闭', style: const TextStyle(color: AppColors.textSub)),
          ),
        if (!_downloading && info.apkUrl != null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _startDownload,
            child: Text(
              _errorMessage != null
                  ? '重试自动更新'
                  : (info.hasUpdate ? '立即更新' : '重新安装当前版'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        else if (_downloading)
          TextButton(
            onPressed: () {
              _cancelToken?.cancel();
              setState(() => _downloading = false);
            },
            child: const Text('取消下载', style: TextStyle(color: AppColors.danger)),
          ),
      ],
    );
  }
}
