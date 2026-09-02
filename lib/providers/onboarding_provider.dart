/// 首次使用引导状态层（对应旧版 onboarding.js）
/// 独立存储键 onboardingState：不往 settings 加字段
library;

import 'package:flutter/foundation.dart';

import '../models/onboarding.dart';
import '../services/storage_service.dart';
import 'plan_provider.dart';
import 'record_provider.dart';
import 'settings_provider.dart';

class OnboardingProvider extends ChangeNotifier {
  final StorageService _storage;
  final PlanProvider _plan;
  final SettingsProvider _settings;
  final RecordProvider _records;

  OnboardingState state;

  /// 本次进程内「退出引导不再跳」标记（内存态）：
  /// 用户在引导首页主动退出时置位，下次冷启动仍会弹出（语义 = 「下次还会出现」）
  bool _dismissedOnce = false;

  OnboardingProvider(this._storage, this._plan, this._settings, this._records)
      : state = OnboardingState.defaults() {
    _load();
  }

  void _load() {
    final d = _storage.readMap(StorageService.kOnboarding);
    state = d.isEmpty ? OnboardingState.defaults() : OnboardingState.fromJson(d);
  }

  Future<void> _persist() async {
    await _storage.writeMap(StorageService.kOnboarding, state.toJson());
  }

  /// 老用户升级豁免检测：以下任一命中即视为老用户（升级安装不弹引导）
  bool isLegacyUser() {
    if (_plan.hasPlan) return true;
    if (_settings.settings.bmr > 0) return true;
    if (_settings.settings.ai.apiKey.isNotEmpty) return true;
    if (_records.store.checkRecords.isNotEmpty) return true;
    return false;
  }

  /// 首启判断（首页 onShow 调用）；内部做一次性老用户迁移
  bool shouldOnboard() {
    if (!state.done) {
      if (isLegacyUser()) {
        state.done = true;
        _persist();
      } else if (_dismissedOnce) {
        return false;
      }
    }
    return !state.done;
  }

  /// 主动退出引导（不置 done，下次冷启动还会出现）
  void dismissOnboarding() {
    _dismissedOnce = true;
  }

  /// 保存引导收集的基础信息
  Future<void> saveProfile(Map<String, dynamic> patch) async {
    if (patch['gender'] is String) state.profile.gender = patch['gender'] as String;
    if (patch['age'] is num) state.profile.age = (patch['age'] as num).round();
    if (patch['height'] is num) state.profile.height = (patch['height'] as num).round();
    if (patch['weight'] is num) state.profile.weight = (patch['weight'] as num).round();
    if (patch['activity'] is num) state.profile.activity = (patch['activity'] as num).toDouble();
    notifyListeners();
    await _persist();
  }

  /// 引导最终完成
  Future<void> finishOnboarding() async {
    state.done = true;
    notifyListeners();
    await _persist();
  }

  /// 跳过引导（不再自动出现）
  Future<void> skipOnboarding() async {
    state.done = true;
    notifyListeners();
    await _persist();
  }

  /// 重新体验引导（使用指引页入口用；仅重跑，不清任何数据）
  Future<void> rerunOnboarding() async {
    state.done = false;
    _dismissedOnce = false;
    notifyListeners();
    await _persist();
  }

  /// 覆盖替换整个引导状态（历史备份「覆盖导入」使用）
  Future<void> replaceOnboarding(OnboardingState data) async {
    state = OnboardingState(done: data.done, profile: data.profile);
    notifyListeners();
    await _persist();
  }
}
