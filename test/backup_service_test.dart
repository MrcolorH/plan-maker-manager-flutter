/// 备份服务单元测试：文件名 / 编码格式 / 解析校验 / 容错归一 / 概要统计 / 降级导出
/// 覆盖 backup_service.dart（.txt 备份导出到 Download 目录相关逻辑）
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/services/backup_service.dart';

BackupData buildData({String aiKey = ''}) => BackupData(
      planData: PlanData(
        version: '1.0',
        meta: PlanMeta(startedAt: '2026-09-01', planName: '测试计划'),
        meals: [
          MealItem(id: 'm1', type: 'breakfast', name: '早餐', time: '07:30', calories: 300, days: [3]),
          MealItem(id: 'm2', type: 'lunch', name: '午餐', time: '12:00', calories: 400, days: [3]),
        ],
        exercises: [
          ExerciseItem(id: 'e1', name: '慢跑', time: '18:30', duration: 30, caloriesBurned: 300, days: [3]),
        ],
        deletedIds: const [],
      ),
      checkRecords: {
        '2026-09-02': {
          'meal:m1': {'checkedAt': 1},
          'exercise:e1': {'checkedAt': 2},
        },
        '2026-09-01': {
          'meal:m2': {'checkedAt': 3},
        },
      },
      mealAdjust: {},
      tempTasks: {
        '2026-09-02': [
          {'id': 't1', 'type': 'snack', 'name': '奶茶', 'time': '15:00', 'calories': 400},
        ],
      },
      extraFoods: const {},
      settings: AppSettings(
        tdee: 2000,
        bmr: 1500,
        aiProfiles: [
          AiProfile(
            id: 'legacy-1',
            provider: 'deepseek',
            endpoint: 'https://api.deepseek.com',
            apiKey: aiKey,
            model: 'deepseek-v4-flash',
            createdAt: 0,
          ),
        ],
        activeAiProfileId: 'legacy-1',
      ),
      onboardingState: OnboardingState(done: true),
      apiUsage: ApiUsage(calls: 2, promptTokens: 100),
    );

void main() {
  group('backupFileName', () {
    test('扩展名为 .txt 且时间戳补齐', () {
      final name = backupFileName(DateTime(2026, 9, 2, 16, 5, 8));
      expect(name, 'zhiqing-backup-20260902-160508.txt');
    });

    test('纯 ASCII（中文名在传输端易被截断/乱码）', () {
      expect(RegExp(r'^[\x00-\x7F]+$').hasMatch(backupFileName()), true);
    });
  });

  group('encodeBackup（备份正文结构）', () {
    test('顶层字段与数据段完整（formatVersion 2）', () {
      final obj = jsonDecode(encodeBackup(buildData())) as Map<String, dynamic>;
      expect(obj['app'], 'jianfeidazi');
      expect(obj['type'], 'backup');
      expect(obj['formatVersion'], 2);
      expect(obj['exportedAt'], isNotNull);
      final d = obj['data'] as Map<String, dynamic>;
      expect(d.keys.toSet(), {
        'planData',
        'checkRecords',
        'mealAdjust',
        'tempTasks',
        'extraFoods',
        'dayEntries',
        'weightRecords',
        'userPresets',
        'userFoods',
        'settings',
        'onboardingState',
        'apiUsage',
      });
    });

    test('exportedAt 用传入时间（可复现）', () {
      final now = DateTime(2026, 9, 2, 16, 5, 8);
      final obj = jsonDecode(encodeBackup(buildData(), now: now)) as Map<String, dynamic>;
      expect(obj['exportedAt'], now.toIso8601String());
    });

    test('缩进 2 空格（便于人工查看）', () {
      expect(encodeBackup(buildData()).contains('\n  "app"'), true);
    });
  });

  group('parseBackupText（校验）', () {
    test('正常往返：编码 → 解析 → 数据一致（敏感 apiKey 已脱敏）', () {
      final src = buildData(aiKey: 'sk-test');
      final r = BackupService.instance.parseBackupText(encodeBackup(src));
      expect(r.ok, true);
      final d = r.data!;
      expect(d.planData.meals.length, 2);
      expect(d.planData.exercises.single.name, '慢跑');
      expect(d.planData.meta.planName, '测试计划');
      expect(d.checkRecords.keys.toSet(), {'2026-09-01', '2026-09-02'});
      expect(d.settings.tdee, 2000);
      expect(d.settings.ai.apiKey, ''); // 备份编码已安全脱敏，不输出明文密钥
      expect(d.onboardingState.done, true);
      expect(d.apiUsage.calls, 2);
      expect(r.exportedAt, isNotNull);
    });

    test('空内容被拒', () {
      expect(BackupService.instance.parseBackupText('   ').ok, false);
    });

    test('非 JSON 被拒并给出可读提示', () {
      final r = BackupService.instance.parseBackupText('这不是备份');
      expect(r.ok, false);
      expect(r.error, contains('JSON'));
    });

    test('非本 app 文件被拒', () {
      final r = BackupService.instance.parseBackupText(
          jsonEncode({'app': 'other', 'type': 'backup', 'formatVersion': 1, 'data': {}}));
      expect(r.ok, false);
      expect(r.error, contains('知轻'));
    });

    test('formatVersion 不支持被拒', () {
      final r = BackupService.instance.parseBackupText(
          jsonEncode({'app': 'jianfeidazi', 'type': 'backup', 'formatVersion': 99, 'data': {}}));
      expect(r.ok, false);
      expect(r.error, contains('formatVersion'));
    });

    test('v2 备份 dayEntries 直读（含当日快照往返）', () {
      final src = buildData();
      final json = jsonDecode(encodeBackup(src)) as Map<String, dynamic>;
      (json['data'] as Map<String, dynamic>)['dayEntries'] = {
        '2026-09-02': [
          {
            'id': 'm1',
            'kind': 'meal',
            'slot': 'breakfast',
            'time': '07:30',
            'content': '早餐',
            'calories': 300,
            'note': '',
            'source': 'plan',
            'planItemId': 'm1',
            'detached': false,
            'caloriesDirty': false,
          },
        ],
      };
      final r = BackupService.instance.parseBackupText(jsonEncode(json));
      expect(r.ok, true);
      expect(r.data!.legacy, false);
      final entries = r.data!.dayEntries['2026-09-02'] as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['content'], '早餐');
    });

    test('v1 旧备份导入自动转换为快照（F11：历史数据不因格式升级而不可用）', () {
      // 手工构造 v1 备份（formatVersion 1、无 dayEntries、含旧键）
      final v1 = {
        'app': 'jianfeidazi',
        'type': 'backup',
        'formatVersion': 1,
        'data': {
          'planData': {
            'version': '1.0',
            'meta': {'startedAt': '2026-09-01'},
            'meals': [
              {'id': 'm1', 'type': 'breakfast', 'name': '早餐', 'time': '07:30', 'calories': 300, 'days': [3]},
              {'id': 'm2', 'type': 'lunch', 'name': '午餐', 'time': '12:00', 'calories': 400, 'days': [3]},
            ],
            'exercises': [
              {'id': 'e1', 'name': '慢跑', 'time': '18:30', 'duration': 30, 'caloriesBurned': 300, 'days': [3]},
            ],
          },
          'checkRecords': {
            '2026-09-02': {'meal:m1': {'checkedAt': 1}},
          },
          'mealAdjust': {
            '2026-09-02': {'meal:m1': {'calories': 350, 'note': '少了个蛋'}},
          },
          'tempTasks': {
            '2026-09-02': [
              {'id': 't1', 'type': 'snack', 'name': '奶茶', 'time': '15:00', 'calories': 400, 'source': 'ai'},
            ],
          },
          'extraFoods': {},
          'settings': {},
          'onboardingState': {},
          'apiUsage': {},
        },
      };
      final r = BackupService.instance.parseBackupText(jsonEncode(v1));
      expect(r.ok, true);
      final d = r.data!;
      expect(d.legacy, true);
      // 2026-09-02 是周三（days [3] 命中）→ 转换出 计划餐 m1(覆盖 350) + m2 + 计划运动 e1 + 加餐 t1
      final day = (d.dayEntries['2026-09-02'] as List).cast<Map>();
      expect(day.length, 4);
      final m1 = day.firstWhere((e) => e['id'] == 'm1');
      expect(m1['kind'], 'meal');
      expect(m1['calories'], 350); // mealAdjust 覆盖值生效
      expect(m1['note'], '少了个蛋');
      expect(m1['caloriesDirty'], true);
      final t1 = day.firstWhere((e) => e['id'] == 't1');
      expect(t1['source'], 'ai');
      expect(t1['slot'], 'snack');
      // 2026-09-01 是周二，days[3] 不命中 → 无计划条目，无快照
      expect(d.dayEntries.containsKey('2026-09-01'), false);
    });

    test('缺少 data 段被拒', () {
      final r = BackupService.instance.parseBackupText(
          jsonEncode({'app': 'jianfeidazi', 'type': 'backup', 'formatVersion': 1}));
      expect(r.ok, false);
      expect(r.error, contains('data'));
    });

    test('根节点为数组被拒', () {
      expect(BackupService.instance.parseBackupText('[]').ok, false);
    });
  });

  group('容错归一（手工编辑 / 老版本缺字段）', () {
    test('data 为空对象不崩，回落到默认值', () {
      final r = BackupService.instance.parseBackupText(jsonEncode({
        'app': 'jianfeidazi',
        'type': 'backup',
        'formatVersion': 1,
        'data': {},
      }));
      expect(r.ok, true);
      expect(r.data!.planData.meals, isEmpty);
      expect(r.data!.checkRecords, isEmpty);
      expect(r.data!.settings.tdee, 2000); // AppSettings 默认值
      expect(r.data!.settings.ai.apiKey, '');
    });

    test('字段类型错误被纠正而非抛异常', () {
      final r = BackupService.instance.parseBackupText(jsonEncode({
        'app': 'jianfeidazi',
        'type': 'backup',
        'formatVersion': 1,
        'data': {
          'planData': 'oops',
          'checkRecords': [1, 2],
          'tempTasks': 'oops',
          'settings': null,
        },
      }));
      expect(r.ok, true);
      expect(r.data!.planData.meals, isEmpty);
      expect(r.data!.checkRecords, isEmpty);
    });

    test('planData 内列表含脏元素时跳过', () {
      final r = BackupService.instance.parseBackupText(jsonEncode({
        'app': 'jianfeidazi',
        'type': 'backup',
        'formatVersion': 1,
        'data': {
          'planData': {
            'version': 1.0,
            'meals': [
              null,
              {'id': 'm1', 'name': '早餐', 'time': '07:30', 'type': 'breakfast', 'calories': 300, 'days': [3]},
            ],
          },
        },
      }));
      expect(r.ok, true);
      expect(r.data!.planData.meals.length, 1);
      expect(r.data!.planData.version, '1.0'); // 非字符串 version 回落
      expect(r.data!.planData.deletedIds, isEmpty);
    });
  });

  group('autoBackupFileName / hasBackupContent（自动备份单文件方案）', () {
    test('固定文件名 ASCII 且不含时间戳', () {
      expect(autoBackupFileName, 'zhiqing-backup-auto.txt');
      expect(RegExp(r'^[\x00-\x7F]+$').hasMatch(autoBackupFileName), true);
      expect(autoBackupFileName.contains(backupStamp()), false);
    });

    test('有计划/记录时含实质内容', () {
      expect(hasBackupContent(buildData()), true);
    });

    test('空计划 + 无记录 = 无实质内容（设置/引导/用量不算）', () {
      final empty = BackupData(
        planData: PlanData(version: '1.0', meta: PlanMeta(startedAt: '2026-09-01')),
        checkRecords: const {},
        mealAdjust: const {},
        tempTasks: const {},
        extraFoods: const {},
        settings: AppSettings(tdee: 2000, bmr: 1500),
        onboardingState: OnboardingState(done: true),
        apiUsage: ApiUsage(calls: 3, promptTokens: 10),
      );
      expect(hasBackupContent(empty), false);
    });

    test('仅打卡记录也视为有内容', () {
      final d = buildData();
      final onlyRecords = BackupData(
        planData: PlanData(version: '1.0', meta: PlanMeta(startedAt: '2026-09-01')),
        checkRecords: d.checkRecords,
        mealAdjust: const {},
        tempTasks: const {},
        extraFoods: const {},
        settings: d.settings,
        onboardingState: d.onboardingState,
        apiUsage: d.apiUsage,
      );
      expect(hasBackupContent(onlyRecords), true);
    });
  });

  group('buildBackupSummary / fmtTime', () {
    test('统计打卡天数与次数、临时任务数、AI Key', () {
      final s = BackupService.instance.buildBackupSummary(buildData(aiKey: 'sk'));
      expect(s.meals, 2);
      expect(s.exercises, 1);
      expect(s.checkDays, 2);
      expect(s.checkCount, 3); // 2 + 1
      expect(s.tempCount, 1);
      expect(s.hasAiKey, true);
    });

    test('无 Key 时 hasAiKey=false', () {
      expect(BackupService.instance.buildBackupSummary(buildData()).hasAiKey, false);
    });

    test('fmtTime 转本地可读时间，异常输入原样返回', () {
      expect(BackupService.instance.fmtTime('2026-09-02T16:05:08.000'), '2026-09-02 16:05');
      expect(BackupService.instance.fmtTime(null), '');
      expect(BackupService.instance.fmtTime('not-a-date'), 'not-a-date');
    });
  });

  group('exportBackup 降级路径（非 Android / 通道不可用）', () {
    late Directory tempDir;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    const ppChannel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_test_');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(ppChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return tempDir.path;
        return null;
      });
    });

    tearDown(() async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(ppChannel, null);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('写入成功：文件名 .txt、内容可解析、fallback 标记正确', () async {
      final r = await BackupService.instance.exportBackup(buildData());
      expect(r.fileName.endsWith('.txt'), true);
      expect(r.fallback, true); // 测试环境非 Android，走降级
      expect(r.path.startsWith('file://'), true);

      final file = File(r.savedPath);
      expect(await file.exists(), true);
      final text = await file.readAsString();
      expect(BackupService.instance.parseBackupText(text).ok, true);
      // 落盘内容 = 编码结果（去掉动态时间戳后应一致）
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded['app'], 'jianfeidazi');
      expect((decoded['data'] as Map)['planData']['meta']['planName'], '测试计划');
    });

    test('downloadsPath 在非 Android 返回 null', () async {
      expect(await BackupService.instance.downloadsPath(), isNull);
    });

    test('固定文件名导出：落盘文件名 = autoBackupFileName，可读回并解析', () async {
      final r = await BackupService.instance
          .exportBackup(buildData(), fileName: autoBackupFileName);
      expect(r.fileName, 'zhiqing-backup-auto.txt');
      expect(r.fallback, true);

      final file = File(r.savedPath);
      expect(await file.exists(), true);
      final text = await file.readAsString();
      final parsed = BackupService.instance.parseBackupText(text);
      expect(parsed.ok, true);
      expect(parsed.data!.planData.meta.planName, '测试计划');

      // 降级路径读回：readAutoBackupText 应读到同一份内容
      final auto = await BackupService.instance.readAutoBackupText();
      expect(auto, text);
    });

    test('固定文件名二次导出覆盖同一文件（不产生多个备份）', () async {
      await BackupService.instance
          .exportBackup(buildData(), fileName: autoBackupFileName);
      final r2 = await BackupService.instance
          .exportBackup(buildData(), fileName: autoBackupFileName);
      final dir = File(r2.savedPath).parent;
      final autos = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('zhiqing-backup-auto'))
          .toList();
      expect(autos.length, 1);
    });
  });
}
