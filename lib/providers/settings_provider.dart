/// 设置状态层（对应旧版 settings.js）
library;

import 'package:flutter/foundation.dart';

import '../models/plan_data.dart';
import '../models/settings.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  AppSettings settings;

  /// F10 固化钩子：bmr/tdee 即将变化前回调（用于把当前基础消耗固化为历史基准，防历史缺口漂移）
  /// 由 main.dart 装配为 recordProvider.ensureBaseline(baseBurn(settings))
  final Future<void> Function()? _onBurnChange;

  SettingsProvider(this._storage, {this._onBurnChange})
      : settings = AppSettings.defaults() {
    _load();
  }

  /// 基础消耗口径即将变化（bmr/tdee 会被改写）→ 先固化当前值（若需）
  Future<void> _freezeIfBurnChanging(Map<String, dynamic> patch) async {
    final burnChanging = (patch['bmr'] is num && (patch['bmr'] as num).round() != settings.bmr) ||
        (patch['tdee'] is num && (patch['tdee'] as num).round() != settings.tdee);
    if (burnChanging) await _onBurnChange?.call();
  }

  void _load() {
    var d = _storage.readMap(StorageService.kSettings);
    if (d.isEmpty) {
      settings = AppSettings.defaults();
      return;
    }
    final merged = AppSettings.fromJson(d);
    // 本地存储的值优先于 DEFAULTS，老用户的旧模型名需显式迁移（逐条 profile）
    var dirty = false;
    for (var i = 0; i < merged.aiProfiles.length; i++) {
      final p = merged.aiProfiles[i];
      final m = p.model.trim();
      if (kRetiredModelMap.containsKey(m)) {
        merged.aiProfiles[i] = p.copyWithModel(kRetiredModelMap[m]!);
        dirty = true;
      }
    }
    settings = merged;
    if (dirty) _persist(); // 回写存储，避免每次启动重复映射
  }

  Future<void> _persist() async {
    await _storage.writeMap(StorageService.kSettings, settings.toJson());
  }

  /// 通用更新；bmr/tdee 将变时先固化历史基准
  Future<void> update(Map<String, dynamic> patch) async {
    await _freezeIfBurnChanging(patch);
    if (patch['tdee'] is num) settings.tdee = (patch['tdee'] as num).round();
    if (patch['bmr'] is num) settings.bmr = (patch['bmr'] as num).round();
    if (patch['dailyCalorieTarget'] is num) {
      settings.dailyCalorieTarget = (patch['dailyCalorieTarget'] as num).round();
    }
    if (patch['reminderEnabled'] is bool) settings.reminderEnabled = patch['reminderEnabled'] as bool;
    if (patch['reminderAdvance'] is num) settings.reminderAdvance = (patch['reminderAdvance'] as num).round();
    if (patch['autoBackupEnabled'] is bool) {
      settings.autoBackupEnabled = patch['autoBackupEnabled'] as bool;
    }
    notifyListeners();
    await _persist();
  }

  /// 新增一条服务商配置档案并立即启用（上限 kMaxAiProfiles 条）。
  /// 校验 endpoint/key 非空；生成 id/createdAt；保存即激活。
  /// 见 spec/ai-profile-design.md（替换旧 updateAI/switchProvider）。
  static const int kMaxAiProfiles = 5;

  Future<AiProfile> addAiProfile(AiConfig cfg) async {
    final endpoint = cfg.endpoint.trim();
    final apiKey = cfg.apiKey.trim();
    if (endpoint.isEmpty || apiKey.isEmpty) {
      throw Exception('请填写接口地址与 API Key');
    }
    if (settings.aiProfiles.length >= kMaxAiProfiles) {
      throw Exception('最多保存 $kMaxAiProfiles 个服务商配置，请先删除旧配置');
    }
    final profile = AiProfile.create(cfg);
    settings.aiProfiles.add(profile);
    settings.activeAiProfileId = profile.id;
    notifyListeners();
    await _persist();
    return profile;
  }

  /// 仅切换启用指针（不触碰任何档案内容）；endpoint/key/model 随激活档案整体生效
  Future<void> activateAiProfile(String id) async {
    if (!settings.aiProfiles.any((p) => p.id == id)) return;
    settings.activeAiProfileId = id;
    notifyListeners();
    await _persist();
  }

  /// 删除一条档案；若删除的是启用项，自动启用剩余第一条；无剩余则清空指针
  Future<void> removeAiProfile(String id) async {
    settings.aiProfiles.removeWhere((p) => p.id == id);
    if (settings.activeAiProfileId == id) {
      settings.activeAiProfileId =
          settings.aiProfiles.isNotEmpty ? settings.aiProfiles.first.id : '';
    }
    notifyListeners();
    await _persist();
  }

  /// 导入计划时吸收 meta（仅覆盖显式提供的值）；tdee 将变时先固化历史基准
  Future<void> applyMeta(PlanMeta? meta) async {
    if (meta == null) return;
    var dirty = false;
    if (meta.tdee != null && meta.tdee! > 0 && meta.tdee!.round() != settings.tdee) {
      await _onBurnChange?.call();
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
  }

  /// 覆盖替换整个设置（历史备份「覆盖导入」或云端快照恢复使用；默认值深度合并补缺）
  Future<void> replaceSettings(AppSettings data) async {
    // data 来自备份解析（AppSettings.fromJson），其 aiProfiles 已含旧单 ai 迁移与 activeId 校验
    final profiles = List<AiProfile>.from(data.aiProfiles);
    // 老备份可能残留已退役模型名 → 一并映射
    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      final m = p.model.trim();
      if (kRetiredModelMap.containsKey(m)) profiles[i] = p.copyWithModel(kRetiredModelMap[m]!);
    }

    // 安全保护：若导入的 profile 缺少 apiKey（安全脱敏备份），智能继承当前本地已有的有效 Key
    final localKeyById = {
      for (final p in settings.aiProfiles)
        if (p.apiKey.trim().isNotEmpty) p.id: p.apiKey.trim()
    };
    final localKeyByProvider = {
      for (final p in settings.aiProfiles)
        if (p.apiKey.trim().isNotEmpty) p.provider: p.apiKey.trim()
    };

    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      if (p.apiKey.trim().isEmpty) {
        final existingKey = localKeyById[p.id] ?? localKeyByProvider[p.provider];
        if (existingKey != null && existingKey.isNotEmpty) {
          profiles[i] = AiProfile(
            id: p.id,
            provider: p.provider,
            endpoint: p.endpoint,
            apiKey: existingKey,
            model: p.model,
            createdAt: p.createdAt,
          );
        }
      }
    }

    var activeId = data.activeAiProfileId;
    if (activeId.isNotEmpty && !profiles.any((p) => p.id == activeId)) activeId = '';
    if (activeId.isEmpty && profiles.isNotEmpty) activeId = profiles.first.id;
    final merged = AppSettings(
      tdee: data.tdee,
      bmr: data.bmr,
      dailyCalorieTarget: data.dailyCalorieTarget,
      reminderEnabled: data.reminderEnabled,
      reminderAdvance: data.reminderAdvance,
      autoBackupEnabled: data.autoBackupEnabled,
      aiProfiles: profiles,
      activeAiProfileId: activeId,
    );
    settings = merged;
    notifyListeners();
    await _persist();
  }
}
