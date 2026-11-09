import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 更新信息实体
class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String title;
  final String notes;
  final String publishedAt;
  final String? apkUrl;
  final String? apkName;
  final int? apkSize;
  final String htmlUrl;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    required this.title,
    required this.notes,
    required this.publishedAt,
    this.apkUrl,
    this.apkName,
    this.apkSize,
    required this.htmlUrl,
  });

  String get apkSizeFormatted {
    if (apkSize == null || apkSize! <= 0) return '';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String currentVersion = '1.5.0';
  static const String defaultRepo = 'MrcolorH/plan-maker-manager-flutter';
  static const MethodChannel _channel = MethodChannel('com.colorh.jianfei_dazi/backup');

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'jianfei-dazi-updater',
      },
    ),
  );

  /// 检查 GitHub Release 更新
  Future<AppUpdateInfo> checkUpdate({String? repo}) async {
    final targetRepo = (repo != null && repo.trim().isNotEmpty) ? repo.trim() : defaultRepo;
    final apiUrl = 'https://api.github.com/repos/$targetRepo/releases/latest';

    try {
      final response = await _dio.get<Map<String, dynamic>>(apiUrl);
      final data = response.data;
      if (data == null) {
        throw Exception('未能获取到有效的 Release 数据');
      }

      final tagName = (data['tag_name'] as String? ?? '').trim();
      final cleanLatestVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '');
      final title = (data['name'] as String? ?? tagName).trim();
      final body = (data['body'] as String? ?? '').trim();
      final publishedAt = (data['published_at'] as String? ?? '').split('T').first;
      final htmlUrl = (data['html_url'] as String? ?? 'https://github.com/$targetRepo/releases');

      // 寻找 APK 资产
      String? apkUrl;
      String? apkName;
      int? apkSize;

      final assets = data['assets'] as List<dynamic>?;
      if (assets != null) {
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset['name'] as String? ?? '').toLowerCase();
            if (name.endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] as String?;
              apkName = asset['name'] as String?;
              apkSize = asset['size'] as int?;
              break;
            }
          }
        }
      }

      final isNewer = compareVersions(cleanLatestVersion, currentVersion) > 0;

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: cleanLatestVersion.isNotEmpty ? cleanLatestVersion : currentVersion,
        hasUpdate: isNewer,
        title: title,
        notes: body.isNotEmpty ? body : '暂无详细更新说明',
        publishedAt: publishedAt,
        apkUrl: apkUrl,
        apkName: apkName,
        apkSize: apkSize,
        htmlUrl: htmlUrl,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception('未找到 GitHub Release 发布版本（可能是仓库无发布或为私有仓库）');
      }
      throw Exception('网络连接超时或无法访问 GitHub: ${e.message ?? e.type.name}');
    } catch (e) {
      throw Exception('检查更新失败: $e');
    }
  }

  /// 比较两个版本号（形如 1.4.1 vs 1.4.0）
  /// 返回值 > 0 说明 v1 > v2，< 0 说明 v1 < v2，0 说明相等
  static int compareVersions(String v1, String v2) {
    final clean1 = v1.replaceFirst(RegExp(r'^[vV]'), '');
    final clean2 = v2.replaceFirst(RegExp(r'^[vV]'), '');

    final parts1 = clean1.split('.').map((s) => int.tryParse(RegExp(r'\d+').stringMatch(s) ?? '0') ?? 0).toList();
    final parts2 = clean2.split('.').map((s) => int.tryParse(RegExp(r'\d+').stringMatch(s) ?? '0') ?? 0).toList();

    final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < maxLen; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 != p2) {
        return p1.compareTo(p2);
      }
    }
    return 0;
  }

  /// 下载 APK 安装包到临时目录
  Future<File> downloadApk(
    String url, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final savePath = '${tempDir.path}/zhiqing_update.apk';
    final file = File(savePath);

    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final downloadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    await downloadDio.download(
      url,
      savePath,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );

    return File(savePath);
  }

  /// 唤起系统安装器安装 APK
  Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('当前平台暂不支持在应用内唤起 APK 安装');
    }
    try {
      final ok = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return ok ?? false;
    } on PlatformException catch (e) {
      throw Exception('调起安装程序失败: ${e.message}');
    }
  }
}
