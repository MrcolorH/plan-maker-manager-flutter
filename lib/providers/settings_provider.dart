/// 设置状态层（对应旧版 settings.js）
library;

import 'package:flutter/foundation.dart';

import '../models/plan_data.dart';
import '../models/settings.dart';
import '../services/reminder_service.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  final ReminderService _reminder;
  AppSettings settings;
  final PlanData Function()? _getPlan;

  SettingsProvider(this._storage, this._reminder, {this._getPlan})
      : settings = AppSettings.defaults() {
    _load();
  }

  void _load() {
    var d = _storage.readMap(StorageService.kSettings);
    if (d.isEmpty) {
      settings = AppSettings.defaults();
      return;
    }
    final merged = AppSettings.fromJson(d);
    // 本地存储的值优先于 DEFAULTS，所以新默认值无法覆盖老用户的旧模型名，必须显式迁移
    final m = merged.ai.model.trim();
    if (kRetiredModelMap.containsKey(m)) {
      merged.ai.model = kRetiredModelMap[m]!;
      // 回写存储，避免每次启动重复映射
      _persist();
    }
    settings = merged;
  }

  Future<void> _persist() async {
    await _storage.writeMap(StorageService.kSettings, settings.toJson());
  }

  /// 通用更新；涉及提醒配置时自动重调度
  Future<void> update(Map<String, dynamic> patch) async {
    const remindKeys = ['reminderEnabled', 'reminderAdvance'];
    final touchRemind = remindKeys.any((k) => patch.containsKey(k));
    if (patch['tdee'] is num) settings.tdee = (patch['tdee'] as num).round();
    if (patch['bmr'] is num) settings.bmr = (patch['bmr'] as num).round();
    if (patch['dailyCalorieTarget'] is num) {
      settings.dailyCalorieTarget = (patch['dailyCalorieTarget'] as num).round();
    }
    if (patch['reminderEnabled'] is bool) settings.reminderEnabled = patch['reminderEnabled'] as bool;
    if (patch['reminderAdvance'] is num) settings.reminderAdvance = (patch['reminderAdvance'] as num).round();
    notifyListeners();
    await _persist();
    if (touchRemind) {
      final plan = _getPlan?.call();
      if (plan != null) await _reminder.fullReschedule(plan, settings);
    }
  }

  Future<void> updateAI(Map<String, dynamic> patch) async {
    if (patch['provider'] is String) settings.ai.provider = patch['provider'] as String;
    if (patch['endpoint'] is String) settings.ai.endpoint = patch['endpoint'] as String;
    if (patch['apiKey'] is String) settings.ai.apiKey = patch['apiKey'] as String;
    if (patch['model'] is String) settings.ai.model = patch['model'] as String;
    notifyListeners();
    await _persist();
  }

  /// 切换服务商时预填 endpoint/model（用户可再改）
  Future<void> switchProvider(String provider) async {
    final p = kAiProviders.where((x) => x.value == provider).toList();
    settings.ai.provider = provider;
    if (p.isNotEmpty) {
      settings.ai.endpoint = p.first.endpoint;
      settings.ai.model = p.first.model;
    }
    notifyListeners();
    await _persist();
  }

  /// 导入计划时吸收 meta（仅覆盖显式提供的值）
  Future<void> applyMeta(PlanMeta? meta) async {
    if (meta == null) return;
    var dirty = false;
    if (meta.tdee != null && meta.tdee! > 0) {
      settings.tdee = meta.tdee!.round();
      dirty = true;
    }
    if (meta.dailyCalorieTarget != null && meta.dailyCalorieTarget! > 0) {
      settings.dailyCalorieTarget = meta.dailyCalorieTarget!.round();
      dirty = true;
    }
    if (dirty) {
      notifyListeners();
      await _persist();
    }
  }

  /// 清空全部数据（计划/记录/设置），回到首启状态
  Future<void> clearAll() async {
    settings = AppSettings.defaults();
    notifyListeners();
    await _persist();
    final plan = _getPlan?.call();
    if (plan != null) await _reminder.fullReschedule(plan, settings);
  }

  /// 覆盖替换整个设置（历史备份「覆盖导入」使用；默认值深度合并补缺）
  Future<void> replaceSettings(AppSettings data) async {
    final merged = AppSettings(
      tdee: data.tdee,
      bmr: data.bmr,
      dailyCalorieTarget: data.dailyCalorieTarget,
      reminderEnabled: data.reminderEnabled,
      reminderAdvance: data.reminderAdvance,
      ai: AiConfig(
        provider: data.ai.provider,
        endpoint: data.ai.endpoint,
        apiKey: data.ai.apiKey,
        model: data.ai.model,
      ),
    );
    settings = merged;
    notifyListeners();
    await _persist();
    final plan = _getPlan?.call();
    if (plan != null) await _reminder.fullReschedule(plan, settings);
  }
}
