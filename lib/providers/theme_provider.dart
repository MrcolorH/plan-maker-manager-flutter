/// 主题状态管理 Provider
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/theme_config.dart';
import '../services/storage_service.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _storageKey = 'app_theme_settings_v1';
  final StorageService _storage;

  late ThemeConfig _currentTheme;

  ThemeConfig get currentTheme => _currentTheme;
  ThemeConfig get currentConfig => _currentTheme;

  ThemeProvider([StorageService? storage])
      : _storage = storage ?? StorageService.instance {
    _loadTheme();
  }

  void _loadTheme() {
    final map = _storage.readMap(_storageKey);
    if (map.isNotEmpty) {
      try {
        final id = map['id'] as String? ?? 'forest';
        final preset = kPresetThemes.firstWhere(
          (t) => t.id == id,
          orElse: () => kPresetThemes.first,
        );
        _currentTheme = ThemeConfig.fromJson(map, preset);
        return;
      } catch (_) {}
    }
    // 默认选用森林微风二次元壁纸主题
    _currentTheme = kPresetThemes.first;
  }

  Future<void> _saveTheme() async {
    await _storage.writeMap(_storageKey, _currentTheme.toJson());
    notifyListeners();
  }

  /// 恢复默认主题配置
  Future<void> resetToDefault() async {
    _currentTheme = kPresetThemes.first;
    await _saveTheme();
  }

  /// 切换并应用预设主题
  Future<void> applyPreset(ThemeConfig preset) async {
    _currentTheme = preset.copyWith(
      customBgPath: _currentTheme.customBgPath,
    );
    await _saveTheme();
  }

  /// 切换预设主题（通过 ID）
  Future<void> setPresetTheme(String id) async {
    final preset = kPresetThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => kPresetThemes.first,
    );
    await applyPreset(preset);
  }

  /// 设置自选框选后的全屏壁纸
  Future<void> setCustomBackground(String croppedPath) async {
    _currentTheme = _currentTheme.copyWith(
      customBgPath: croppedPath,
      useGlassmorphism: true,
    );
    await _saveTheme();
  }

  /// 设置自选框选后的打气看板娘头像
  Future<void> setCustomMascot(String croppedPath) async {
    _currentTheme = _currentTheme.copyWith(
      customMascotPath: croppedPath,
    );
    await _saveTheme();
  }

  /// 设置自选框选后的卡片底纹
  Future<void> setCustomCardBg(String croppedPath) async {
    _currentTheme = _currentTheme.copyWith(
      customCardBgPath: croppedPath,
    );
    await _saveTheme();
  }

  /// 从相册选择背景图（兼容直接选图流程）
  Future<bool> pickCustomBackground() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return false;

      final path = result.files.first.path;
      if (path == null) return false;

      // 拷贝到应用持久化目录，防止系统清理临时相册缓存
      final docDir = await getApplicationDocumentsDirectory();
      final ext = path.contains('.') ? path.split('.').last : 'jpg';
      final savedFile = File('${docDir.path}/user_custom_bg_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(path).copy(savedFile.path);

      await setCustomBackground(savedFile.path);
      return true;
    } catch (e) {
      debugPrint('pickCustomBackground error: $e');
      return false;
    }
  }

  /// 移除自定义背景图（恢复当前预设背景）
  Future<void> clearCustomBackground() async {
    _currentTheme = _currentTheme.copyWith(clearCustomBg: true);
    await _saveTheme();
  }

  /// 移除自定义看板娘头像（恢复预设打气娘）
  Future<void> clearCustomMascot() async {
    _currentTheme = _currentTheme.copyWith(clearCustomMascot: true);
    await _saveTheme();
  }

  /// 移除自定义卡片底纹（恢复纯色半透明面板）
  Future<void> clearCustomCardBg() async {
    _currentTheme = _currentTheme.copyWith(clearCustomCardBg: true);
    await _saveTheme();
  }

  /// 设置背景不透明度 (0.0 ~ 1.0)
  Future<void> setBgOpacity(double opacity) async {
    _currentTheme = _currentTheme.copyWith(
      bgOpacity: opacity.clamp(0.0, 1.0),
    );
    await _saveTheme();
  }

  /// 设置卡片不透明度 (0.5 ~ 1.0)
  Future<void> setCardOpacity(double opacity) async {
    _currentTheme = _currentTheme.copyWith(
      cardOpacity: opacity.clamp(0.5, 1.0),
    );
    await _saveTheme();
  }

  /// 切换卡片毛玻璃/半透明质感
  Future<void> setUseGlassmorphism(bool enabled) async {
    _currentTheme = _currentTheme.copyWith(useGlassmorphism: enabled);
    await _saveTheme();
  }

  /// 别名：切换毛玻璃
  Future<void> setGlassmorphism(bool enabled) => setUseGlassmorphism(enabled);

  /// 自定义主色调
  Future<void> setPrimaryColor(Color color, [Color? bgColor]) async {
    _currentTheme = _currentTheme.copyWith(
      primaryColor: color,
      primaryBgColor: bgColor ?? color.withValues(alpha: 0.12),
    );
    await _saveTheme();
  }
}
