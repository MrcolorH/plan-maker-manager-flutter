/// 减肥搭子 — Flutter 重构版入口
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
import 'services/reminder_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    final storage = StorageService.instance;
    final reminder = ReminderService.instance;
    appProvider = AppProvider();
    usageProvider = UsageProvider(storage);
    recordProvider = RecordProvider(storage);
    settingsProvider = SettingsProvider(storage, reminder, getPlan: () => planProvider.plan);
    planProvider = PlanProvider(storage, reminder, settingsProvider, recordProvider);
    onboardingProvider = OnboardingProvider(storage, planProvider, settingsProvider, recordProvider);
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
        title: '减肥搭子',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const MainShell(),
      ),
    );
  }
}
