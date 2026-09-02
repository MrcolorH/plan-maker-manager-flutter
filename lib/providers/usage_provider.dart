/// API 用量统计：本 App 累计调用次数与 tokens（费用按牌价估算展示）
library;

import 'package:flutter/foundation.dart';

import '../models/onboarding.dart';
import '../services/storage_service.dart';

class UsageProvider extends ChangeNotifier {
  final StorageService _storage;
  ApiUsage usage;

  UsageProvider(this._storage) : usage = ApiUsage.defaults() {
    _load();
  }

  void _load() {
    final d = _storage.readMap(StorageService.kApiUsage);
    usage = ApiUsage.fromJson(d);
  }

  Future<void> _persist() async {
    await _storage.writeMap(StorageService.kApiUsage, usage.toJson());
  }

  /// 从 chat/completions 响应的 usage 字段累计
  Future<void> addUsage(Map<String, dynamic>? u) async {
    if (u == null) return;
    usage.calls += 1;
    usage.promptTokens += _num(u['prompt_tokens']);
    usage.completionTokens += _num(u['completion_tokens']);
    // DeepSeek 专有字段；其他兼容服务没有就按 0
    usage.cacheHitTokens += _num(u['prompt_cache_hit_tokens']);
    notifyListeners();
    await _persist();
  }

  int _num(dynamic v) => v is num ? v.round() : 0;

  /// 估算费用（元）——注意：与 models/onboarding.dart 顶层函数 estimateCost(ApiUsage) 同名会递归，故命名 estimateTotalCost
  double estimateTotalCost() => estimateCost(usage);

  void resetUsage() {
    usage = ApiUsage.defaults();
    notifyListeners();
    _persist();
  }

  /// 覆盖替换整个用量统计（历史备份「覆盖导入」使用）
  void replaceUsage(ApiUsage data) {
    usage = data;
    notifyListeners();
    _persist();
  }
}
