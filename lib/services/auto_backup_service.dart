/// 本地自动备份（单文件滚动覆盖，用户零操作）
/// 设计依据：spec/backup-design.md v1.1 —— Download/zhiqing-backup-auto.txt 永远只有一份
///
/// 触发时机：
/// 1. 任意数据变更后防抖 15 秒写一次（连续操作只落一次盘）
/// 2. 应用退到后台 / 被杀前（lifecycle paused）立即写
/// 3. 启动后 10 秒兜底写一次（老版本升级 / 首次安装自愈）
///
/// 两道保护：
/// - 内容没变不重复写（内存比对上次写入正文）
/// - 空数据保护：当前快照无实质内容（无计划/打卡/调整/临时任务/加餐）时**永不落盘**，
///   防止清库/误操作后退出把唯一的好备份冲成空文件（不依赖能否读回旧文件）
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../providers/onboarding_provider.dart';
import '../providers/plan_provider.dart';
import '../providers/record_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/usage_provider.dart';
import 'backup_service.dart';
import 'storage_service.dart';

/// 从各 Provider 当前状态聚合全量快照（备份页与自动备份共用同一口径）
BackupData captureBackupData({
  required PlanProvider plan,
  required RecordProvider record,
  required SettingsProvider settings,
  required OnboardingProvider onboarding,
  required UsageProvider usage,
}) {
  final rec = record.store;
  final storage = StorageService.instance;
  return BackupData(
    planData: plan.plan,
    checkRecords:
        rec.checkRecords.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))),
    mealAdjust:
        rec.mealAdjust.map((d, m) => MapEntry(d, m.map((k, v) => MapEntry(k, v.toJson())))),
    tempTasks: rec.tempTasks.map((d, l) => MapEntry(d, l.map((e) => e.toJson()).toList())),
    extraFoods: rec.extraFoods,
    dayEntries: rec.dayEntries.map((d, l) => MapEntry(d, l.map((e) => e.toJson()).toList())),
    weightRecords: rec.weightRecords.toJson(),
    userPresets: storage.readMap(StorageService.kUserPresets),
    userFoods: storage.readMap(StorageService.kUserFoods),
    settings: settings.settings.copyWithSanitizedApiKeys(),
    onboardingState: onboarding.state,
    apiUsage: usage.usage,
  );
}

class AutoBackupService with WidgetsBindingObserver {
  AutoBackupService({
    required this.plan,
    required this.record,
    required this.settings,
    required this.onboarding,
    required this.usage,
  });

  final PlanProvider plan;
  final RecordProvider record;
  final SettingsProvider settings;
  final OnboardingProvider onboarding;
  final UsageProvider usage;

  /// 数据变更后的防抖窗口：连续打卡/编辑只触发一次写盘
  static const _debounce = Duration(seconds: 15);

  Timer? _timer;
  String? _lastWritten;
  bool _running = false;
  bool _attached = false;

  /// 注册监听与生命周期观察，并在启动后兜底写一次
  void attach() {
    if (_attached) return;
    _attached = true;
    plan.addListener(_schedule);
    record.addListener(_schedule);
    settings.addListener(_schedule);
    onboarding.addListener(_schedule);
    usage.addListener(_schedule);
    WidgetsBinding.instance.addObserver(this);
    // 延迟首个备份：等启动期一次性初始化（引导回填/迁移等）全部落定
    _schedule(delay: const Duration(seconds: 10));
  }

  /// 数据变更 → 重置防抖计时
  void _schedule({Duration? delay}) {
    _timer?.cancel();
    _timer = Timer(delay ?? _debounce, _run);
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      // 开关门禁：默认关，用户开启（settings.autoBackupEnabled）后才落盘；
      // 开启状态随 settings 持久化，除非手动关闭否则每次启动都保持开启
      if (!settings.settings.autoBackupEnabled) return;
      final data = captureBackupData(
        plan: plan,
        record: record,
        settings: settings,
        onboarding: onboarding,
        usage: usage,
      );
      final text = encodeBackup(data);
      if (text == _lastWritten) return; // 内容没变不重复写

      // 空数据保护（永不写空快照）：无实质内容（无计划/打卡/调整/临时任务/加餐）直接跳过。
      // 不依赖能否读回旧文件（MediaStore 瞬时异常/跨设备拷贝读不到也不会误写），
      // 从根上杜绝「用户清空数据后退出 → 唯一好备份被空快照冲掉」。空备份本身无恢复价值；
      // 破坏性操作前的带时间戳留底（清空全部/覆盖导入）仍负责主动留痕。
      if (!hasBackupContent(data)) return;

      await BackupService.instance.exportBackup(data, fileName: autoBackupFileName);
      _lastWritten = text;
    } catch (_) {
      // 自动备份静默失败，不打扰用户；下次变更 / 退后台会自动重试
    } finally {
      _running = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 退到后台立即落盘（进程可能随后被杀，等不得防抖）
      _timer?.cancel();
      unawaited(_run());
    }
  }
}
