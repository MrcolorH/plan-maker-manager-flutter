import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jianfei_dazi/models/onboarding.dart';
import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/providers/onboarding_provider.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/providers/usage_provider.dart';
import 'package:jianfei_dazi/services/auto_backup_service.dart';
import 'package:jianfei_dazi/services/backup_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late SettingsProvider settingsP;
  late RecordProvider recordP;
  late PlanProvider planP;
  late OnboardingProvider onboardingP;
  late UsageProvider usageP;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageService.instance.init();
    storage = StorageService.instance;
    settingsP = SettingsProvider(storage);
    recordP = RecordProvider(storage);
    planP = PlanProvider(storage, settingsP, recordP);
    onboardingP = OnboardingProvider(storage, planP, settingsP, recordP);
    usageP = UsageProvider(storage);
  });

  group('备份与云端同步 API Key 安全脱敏测试', () {
    test('AppSettings.toJson 在非敏感导出模式下脱敏 apiKey', () {
      final profile = AiProfile(
        id: 'p1',
        provider: 'deepseek',
        endpoint: 'https://api.deepseek.com',
        apiKey: 'sk-secret-12345678',
        model: 'deepseek-flash',
        createdAt: 123456,
      );
      final settings = AppSettings(
        tdee: 2200,
        aiProfiles: [profile],
        activeAiProfileId: 'p1',
      );

      // 本地持久化模式：保留敏感信息
      final localJson = settings.toJson(includeSensitive: true);
      expect(localJson['ai']['apiKey'], 'sk-secret-12345678');
      expect((localJson['aiProfiles'] as List)[0]['apiKey'], 'sk-secret-12345678');

      // 安全脱敏模式：剔除敏感信息
      final safeJson = settings.toJson(includeSensitive: false);
      expect(safeJson['ai']['apiKey'], '');
      expect((safeJson['aiProfiles'] as List)[0]['apiKey'], '');
      expect(safeJson['ai']['endpoint'], 'https://api.deepseek.com');
      expect(safeJson['ai']['model'], 'deepseek-flash');
    });

    test('encodeBackup 导出的正文中绝不出现真实 API Key', () {
      final realApiKey = 'sk-real-super-secret-key-123';
      final profile = AiProfile(
        id: 'p1',
        provider: 'openai',
        endpoint: 'https://api.openai.com/v1',
        apiKey: realApiKey,
        model: 'gpt-4o',
        createdAt: 1000,
      );
      final backup = BackupData(
        planData: PlanData.empty(),
        checkRecords: {},
        mealAdjust: {},
        tempTasks: {},
        extraFoods: {},
        settings: AppSettings(
          aiProfiles: [profile],
          activeAiProfileId: 'p1',
        ),
        onboardingState: OnboardingState(done: true),
        apiUsage: ApiUsage(calls: 1),
      );

      final encoded = encodeBackup(backup);

      // 强断言：导出的纯文本无论任何角落都绝不包含真实密钥
      expect(encoded.contains(realApiKey), isFalse);

      // 解析回来的数据中 apiKey 为空，但配置元信息保留
      final parsed = BackupService.instance.parseBackupText(encoded);
      expect(parsed.ok, isTrue);
      expect(parsed.data!.settings.ai.apiKey, '');
      expect(parsed.data!.settings.ai.endpoint, 'https://api.openai.com/v1');
      expect(parsed.data!.settings.ai.model, 'gpt-4o');
    });

    test('captureBackupData 会自动剔除 settings 中的敏感 API Key', () {
      final realKey = 'sk-ds-abcdef123456';
      settingsP.settings = AppSettings(
        aiProfiles: [
          AiProfile(
            id: 'prof-ds',
            provider: 'deepseek',
            endpoint: 'https://api.deepseek.com',
            apiKey: realKey,
            model: 'deepseek-flash',
            createdAt: 100,
          ),
        ],
        activeAiProfileId: 'prof-ds',
      );

      final data = captureBackupData(
        plan: planP,
        record: recordP,
        settings: settingsP,
        onboarding: onboardingP,
        usage: usageP,
      );

      expect(data.settings.ai.apiKey, '');
      expect(data.settings.aiProfiles.first.apiKey, '');
      // 但本地 provider 本身依然保留着 key
      expect(settingsP.settings.ai.apiKey, realKey);
    });

    test('覆盖导入/云端恢复时智能保护本地已有的有效 API Key', () async {
      final myLocalKey = 'sk-local-valid-key-999';

      // 假设当前本地已配置好 DeepSeek key
      settingsP.settings = AppSettings(
        tdee: 2000,
        aiProfiles: [
          AiProfile(
            id: 'p-local',
            provider: 'deepseek',
            endpoint: 'https://api.deepseek.com',
            apiKey: myLocalKey,
            model: 'deepseek-flash',
            createdAt: 1,
          ),
        ],
        activeAiProfileId: 'p-local',
      );

      // 模拟从云端或脱敏备份恢复进来的数据（其 apiKey 为空）
      final backupSettings = AppSettings(
        tdee: 1800,
        aiProfiles: [
          AiProfile(
            id: 'p-cloud',
            provider: 'deepseek',
            endpoint: 'https://api.deepseek.com',
            apiKey: '', // 脱敏后的空 key
            model: 'deepseek-flash',
            createdAt: 2,
          ),
        ],
        activeAiProfileId: 'p-cloud',
      );

      // 执行恢复
      await settingsP.replaceSettings(backupSettings);

      // 验证：设置数值已更新为 1800
      expect(settingsP.settings.tdee, 1800);
      // 验证核心保护：本地已有 DeepSeek 的 key 成功继承保护，未被抹为空！
      expect(settingsP.settings.ai.apiKey, myLocalKey);
      expect(settingsP.settings.activeProfile?.apiKey, myLocalKey);
    });

    test('全新设备恢复脱敏备份时，平稳保留服务商与模型配置，apiKey 安全为空', () async {
      final backupSettings = AppSettings(
        tdee: 1900,
        aiProfiles: [
          AiProfile(
            id: 'p-new',
            provider: 'kimi',
            endpoint: 'https://api.moonshot.cn/v1',
            apiKey: '', // 脱敏备份
            model: 'moonshot-v1-8k',
            createdAt: 3,
          ),
        ],
        activeAiProfileId: 'p-new',
      );

      await settingsP.replaceSettings(backupSettings);

      expect(settingsP.settings.tdee, 1900);
      expect(settingsP.settings.activeProfile?.provider, 'kimi');
      expect(settingsP.settings.activeProfile?.endpoint, 'https://api.moonshot.cn/v1');
      expect(settingsP.settings.activeProfile?.apiKey, '');
    });
  });
}
