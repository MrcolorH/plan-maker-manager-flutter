/// AppSettings 自动备份开关专项测试：
/// 默认关（新装 + 老版本存储无字段都回落 false）；开启后序列化持久化，除非手动关否则保持。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/settings.dart';

void main() {
  group('autoBackupEnabled 默认关', () {
    test('新装默认关（defaults / 构造函数）', () {
      expect(AppSettings.defaults().autoBackupEnabled, false);
      expect(AppSettings().autoBackupEnabled, false);
    });

    test('老版本存储 JSON 无该字段 → 回落 false（升级不自启）', () {
      final s = AppSettings.fromJson({'tdee': 2000, 'reminderEnabled': true});
      expect(s.autoBackupEnabled, false);
    });

    test('显式 false 也回落 false', () {
      expect(AppSettings.fromJson({'autoBackupEnabled': false}).autoBackupEnabled, false);
    });
  });

  group('开启后持久化（除非手动关闭否则保持）', () {
    test('fromJson true → 保持开启', () {
      expect(AppSettings.fromJson({'autoBackupEnabled': true}).autoBackupEnabled, true);
    });

    test('toJson → fromJson 往返保留开启状态（写回存储不丢）', () {
      final on = AppSettings.fromJson({'autoBackupEnabled': true});
      final restored = AppSettings.fromJson(on.toJson());
      expect(restored.autoBackupEnabled, true);
    });

    test('关闭后往返保留 false', () {
      final off = AppSettings.fromJson({'autoBackupEnabled': true});
      off.autoBackupEnabled = false; // 手动关闭
      final restored = AppSettings.fromJson(off.toJson());
      expect(restored.autoBackupEnabled, false);
    });
  });
}
