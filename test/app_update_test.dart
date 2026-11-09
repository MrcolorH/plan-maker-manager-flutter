import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/services/app_update_service.dart';

void main() {
  group('AppUpdateService 语义化版本比对测试', () {
    test('小版本升级正确识别', () {
      expect(AppUpdateService.compareVersions('1.4.1', '1.4.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('v1.4.1', '1.4.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('V1.4.1', 'v1.4.0'), greaterThan(0));
    });

    test('跨两位数版本号（1.10.0 vs 1.4.0）正确识别', () {
      expect(AppUpdateService.compareVersions('1.10.0', '1.4.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('1.4.0', '1.10.0'), lessThan(0));
    });

    test('主版本与次版本升级', () {
      expect(AppUpdateService.compareVersions('2.0.0', '1.4.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('1.5.0', '1.4.9'), greaterThan(0));
      expect(AppUpdateService.compareVersions('1.3.9', '1.4.0'), lessThan(0));
    });

    test('相同版本返回 0', () {
      expect(AppUpdateService.compareVersions('1.4.0', '1.4.0'), 0);
      expect(AppUpdateService.compareVersions('v1.4.0', '1.4.0'), 0);
      expect(AppUpdateService.compareVersions('1.4.0+1', '1.4.0'), 0);
    });
  });

  group('AppUpdateInfo 模型格式化测试', () {
    test('apkSizeFormatted 正确格式化为 MB', () {
      const info = AppUpdateInfo(
        currentVersion: '1.4.0',
        latestVersion: '1.4.1',
        hasUpdate: true,
        title: '知轻 1.4.1 更新',
        notes: '优化设置页并支持在线更新',
        publishedAt: '2026-11-06',
        apkUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/download/v1.4.1/app-release.apk',
        apkName: 'app-release.apk',
        apkSize: 26109542, // ~24.9 MB
        htmlUrl: 'https://github.com/MrcolorH/plan-maker-manager-flutter/releases/tag/v1.4.1',
      );

      expect(info.apkSizeFormatted, '24.9 MB');
      expect(info.hasUpdate, true);
      expect(info.latestVersion, '1.4.1');
    });
  });
}
