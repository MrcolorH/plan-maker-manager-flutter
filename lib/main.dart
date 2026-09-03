/// 知轻 — Flutter 重构版入口（卡路里 / 饮食记录 / 单机离线）
/// 与原 uni-app 版 1:1 兼容数据格式与交互
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/main_shell.dart';
import 'providers/app_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/plan_provider.dart';
import 'providers/record_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/usage_provider.dart';
import 'services/auto_backup_service.dart';
import 'services/reminder_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/calorie_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.instance.init();
  await ReminderService.instance.init();
  runApp(const JianfeiDaziApp());
}

class JianfeiDaziApp extends StatefulWidget {
  const JianfeiDaziApp({super.key});

  @override
  State<JianfeiDaziApp> createState() => _JianfeiDaziAppState();
}

class _JianfeiDaziAppState extends State<JianfeiDaziApp> {
  late final AppProvider appProvider;
  late final UsageProvider usageProvider;
  late final SettingsProvider settingsProvider;
  late final RecordProvider recordProvider;
  late final PlanProvider planProvider;
  late final OnboardingProvider onboardingProvider;
  late final AutoBackupService autoBackup;

  @override
  void initState() {
    super.initState();
    final storage = StorageService.instance;
    final reminder = ReminderService.instance;
    appProvider = AppProvider();
    usageProvider = UsageProvider(storage);
    recordProvider = RecordProvider(storage);
    settingsProvider = SettingsProvider(
      storage,
      reminder,
      getPlan: () => planProvider.plan,
      // F10：基础消耗口径变化前固化历史基准（recordProvider.ensureBaseline 内部幂等 + 有历史才固化）
      onBurnChange: () => recordProvider.ensureBaseline(baseBurn(settingsProvider.settings)),
    );
    planProvider = PlanProvider(storage, reminder, settingsProvider, recordProvider);
    onboardingProvider = OnboardingProvider(storage, planProvider, settingsProvider, recordProvider);
    // 本地自动备份：单文件滚动覆盖，数据变更防抖写入 + 退后台立即写入
    autoBackup = AutoBackupService(
      plan: planProvider,
      record: recordProvider,
      settings: settingsProvider,
      onboarding: onboardingProvider,
      usage: usageProvider,
    )..attach();
    // 启动时兜底重算提醒调度（重启后系统级调度自动恢复，这里补齐当天/次日）
    reminder.onLaunch(planProvider.plan, settingsProvider.settings);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appProvider),
        ChangeNotifierProvider.value(value: usageProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: recordProvider),
        ChangeNotifierProvider.value(value: planProvider),
        ChangeNotifierProvider.value(value: onboardingProvider),
      ],
      child: MaterialApp(
        title: '知轻',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const MainShell(),
      ),
    );
  }
}
