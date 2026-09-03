/// 本地存储服务：封装 shared_preferences，7 个存储键与旧版 uni storage 完全一致
/// planData / checkRecords / mealAdjust / tempTasks / extraFoods / settings / apiUsage / onboardingState
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String kPlan = 'planData';
  static const String kCheckRecords = 'checkRecords';
  static const String kMealAdjust = 'mealAdjust';
  static const String kTempTasks = 'tempTasks';
  static const String kExtraFoods = 'extraFoods';
  static const String kSettings = 'settings';
  static const String kApiUsage = 'apiUsage';
  static const String kOnboarding = 'onboardingState';
  static const String kDayEntries = 'dayEntries';
  static const String kWeightRecords = 'weightRecords';

  late SharedPreferences _prefs;
  bool _ready = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _ready = true;
  }

  Map<String, dynamic> readMap(String key) {
    if (!_ready) return {};
    final s = _prefs.getString(key);
    if (s == null || s.isEmpty) return {};
    try {
      final v = jsonDecode(s);
      return (v is Map) ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  String? readString(String key) => _ready ? _prefs.getString(key) : null;

  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    if (!_ready) return;
    await _prefs.setString(key, jsonEncode(value));
  }

  Future<void> remove(String key) async {
    if (!_ready) return;
    await _prefs.remove(key);
  }
}
