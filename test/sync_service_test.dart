import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jianfei_dazi/models/records.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
  });

  group('SyncService 逻辑与数据持久化测试', () {
    test('初始状态与服务器配置', () async {
      final sync = SyncService();
      await sync.init();

      expect(sync.isLoggedIn, isFalse);
      expect(sync.currentUsername, isNull);
      expect(sync.serverUrl, 'https://api.zhiqing.fun');

      await sync.setServerUrl('http://127.0.0.1:3000/');
      expect(sync.serverUrl, 'http://127.0.0.1:3000');
    });

    test('未登录时拉取收件箱与快照返回保护', () async {
      final sync = SyncService();
      await sync.init();

      final recordProvider = RecordProvider(StorageService.instance);
      final count = await sync.syncInboxToLocal(recordProvider);
      expect(count, equals(0));

      final snapshotRes = await sync.fetchSnapshot();
      expect(snapshotRes['success'], isFalse);

      final bindCodeRes = await sync.getQqBindCode();
      expect(bindCodeRes['success'], isFalse);
    });

    test('模拟本地收件箱拉取入库打卡逻辑', () async {
      final recordProvider = RecordProvider(StorageService.instance);
      const testDate = '2026-11-09';

      await recordProvider.addDayEntry(
        testDate,
        kind: 'meal',
        slot: 'lunch',
        content: '午餐打卡 (测试)',
        calories: 520,
        source: 'qq_bot',
        autoCheck: true,
      );

      final entries = recordProvider.store.dayEntries[testDate];
      expect(entries, isNotNull);
      expect(entries!.length, 1);
      expect(entries.first.content, '午餐打卡 (测试)');
      expect(entries.first.calories, 520);
      expect(entries.first.source, 'qq_bot');

      // 验证 autoCheck 已自动记录打卡
      final checkRecords = recordProvider.store.checkRecords[testDate];
      expect(checkRecords, isNotNull);
      expect(checkRecords!.containsKey('temp:${entries.first.id}'), isTrue);
    });
  });
}
