/// 主题配置与预设模型
library;

import 'package:flutter/material.dart';

class ThemeConfig {
  final String id;
  final String name;
  final String description;
  final Color primaryColor;
  final Color primaryBgColor;
  final Color orangeColor;
  final Color orangeBgColor;
  final Color pageBgColor;
  final String? assetBgPath; // 内置二次元素材背景路径
  final String? customBgPath; // 用户从相册选取的全局壁纸绝对路径
  final String? customMascotPath; // 用户自选看板娘头像绝对路径
  final String? customCardBgPath; // 用户自选卡片底纹绝对路径
  final double bgOpacity; // 背景图不透明度 0.0 ~ 1.0 (推荐 0.15~0.3)
  final double cardOpacity; // 卡片不透明度 0.5 ~ 1.0
  final bool useGlassmorphism; // 是否开启卡片半透明质感

  const ThemeConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.primaryColor,
    required this.primaryBgColor,
    required this.orangeColor,
    required this.orangeBgColor,
    this.pageBgColor = const Color(0xFFF6F6F3),
    this.assetBgPath,
    this.customBgPath,
    this.customMascotPath,
    this.customCardBgPath,
    this.bgOpacity = 0.22,
    this.cardOpacity = 0.92,
    this.useGlassmorphism = true,
  });

  ThemeConfig copyWith({
    String? id,
    String? name,
    String? description,
    Color? primaryColor,
    Color? primaryBgColor,
    Color? orangeColor,
    Color? orangeBgColor,
    Color? pageBgColor,
    String? assetBgPath,
    String? customBgPath,
    String? customMascotPath,
    String? customCardBgPath,
    bool clearCustomBg = false,
    bool clearCustomMascot = false,
    bool clearCustomCardBg = false,
    double? bgOpacity,
    double? cardOpacity,
    bool? useGlassmorphism,
  }) {
    return ThemeConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      primaryColor: primaryColor ?? this.primaryColor,
      primaryBgColor: primaryBgColor ?? this.primaryBgColor,
      orangeColor: orangeColor ?? this.orangeColor,
      orangeBgColor: orangeBgColor ?? this.orangeBgColor,
      pageBgColor: pageBgColor ?? this.pageBgColor,
      assetBgPath: assetBgPath ?? this.assetBgPath,
      customBgPath: clearCustomBg ? null : (customBgPath ?? this.customBgPath),
      customMascotPath:
          clearCustomMascot ? null : (customMascotPath ?? this.customMascotPath),
      customCardBgPath:
          clearCustomCardBg ? null : (customCardBgPath ?? this.customCardBgPath),
      bgOpacity: bgOpacity ?? this.bgOpacity,
      cardOpacity: cardOpacity ?? this.cardOpacity,
      useGlassmorphism: useGlassmorphism ?? this.useGlassmorphism,
    );
  }

  static List<ThemeConfig> get presets => kPresetThemes;

  String? get bgImagePath => assetBgPath;
  Color get bgColor => pageBgColor;
  bool get hasBackground =>
      (customBgPath != null && customBgPath!.isNotEmpty) ||
      (assetBgPath != null && assetBgPath!.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'customBgPath': customBgPath,
        'customMascotPath': customMascotPath,
        'customCardBgPath': customCardBgPath,
        'bgOpacity': bgOpacity,
        'cardOpacity': cardOpacity,
        'useGlassmorphism': useGlassmorphism,
        'primaryColor': primaryColor.toARGB32(),
        'primaryBgColor': primaryBgColor.toARGB32(),
      };

  factory ThemeConfig.fromJson(Map<String, dynamic> json, ThemeConfig preset) {
    return preset.copyWith(
      customBgPath: json['customBgPath'] as String?,
      customMascotPath: json['customMascotPath'] as String?,
      customCardBgPath: json['customCardBgPath'] as String?,
      bgOpacity: (json['bgOpacity'] as num?)?.toDouble(),
      cardOpacity: (json['cardOpacity'] as num?)?.toDouble(),
      useGlassmorphism: json['useGlassmorphism'] as bool?,
      primaryColor: json['primaryColor'] != null ? Color(json['primaryColor'] as int) : null,
      primaryBgColor: json['primaryBgColor'] != null ? Color(json['primaryBgColor'] as int) : null,
    );
  }
}

/// 内置预设主题库
const List<ThemeConfig> kPresetThemes = [
  ThemeConfig(
    id: 'forest',
    name: '森林微风',
    description: '吉卜力唯美原野 · 治愈草本绿',
    primaryColor: Color(0xFF5BA47C),
    primaryBgColor: Color(0xFFE9F3ED),
    orangeColor: Color(0xFFDB9558),
    orangeBgColor: Color(0xFFFAF1E7),
    pageBgColor: Color(0xFFF5F7F5),
    assetBgPath: 'assets/themes/forest_breeze.jpg',
    bgOpacity: 0.18,
    cardOpacity: 0.92,
  ),
  ThemeConfig(
    id: 'sakura',
    name: '粉樱梦境',
    description: '二次元漫天飞樱 · 甜美浪漫粉',
    primaryColor: Color(0xFFFF6584),
    primaryBgColor: Color(0xFFFFEFF2),
    orangeColor: Color(0xFFFF9233),
    orangeBgColor: Color(0xFFFFF4EB),
    pageBgColor: Color(0xFFFAF5F6),
    assetBgPath: 'assets/themes/sakura_dream.jpg',
    bgOpacity: 0.22,
    cardOpacity: 0.90,
  ),
  ThemeConfig(
    id: 'starry',
    name: '星海幻夜',
    description: '二次元流星天台 · 梦幻深空紫',
    primaryColor: Color(0xFF8B5CF6),
    primaryBgColor: Color(0xFFF3E8FF),
    orangeColor: Color(0xFFF43F5E),
    orangeBgColor: Color(0xFFFFE4E6),
    pageBgColor: Color(0xFFF5F3FF),
    assetBgPath: 'assets/themes/starry_night.jpg',
    bgOpacity: 0.22,
    cardOpacity: 0.90,
  ),
  ThemeConfig(
    id: 'miku',
    name: '电音初音',
    description: '元气虚拟歌姬 · 清澈葱青色',
    primaryColor: Color(0xFF00B4D8),
    primaryBgColor: Color(0xFFE0F7FA),
    orangeColor: Color(0xFFF59E0B),
    orangeBgColor: Color(0xFFFEF3C7),
    pageBgColor: Color(0xFFF0F9FF),
    assetBgPath: 'assets/themes/forest_breeze.jpg',
    bgOpacity: 0.18,
    cardOpacity: 0.92,
  ),
  ThemeConfig(
    id: 'sunset',
    name: '元气落日',
    description: '热血动漫夕阳 · 活力温暖橙',
    primaryColor: Color(0xFFF97316),
    primaryBgColor: Color(0xFFFFF7ED),
    orangeColor: Color(0xFF10B981),
    orangeBgColor: Color(0xFFECFDF5),
    pageBgColor: Color(0xFFFFFBF7),
    assetBgPath: 'assets/themes/sakura_dream.jpg',
    bgOpacity: 0.18,
    cardOpacity: 0.92,
  ),
  ThemeConfig(
    id: 'clean',
    name: '原版简约',
    description: '无壁纸背景 · 极致纯净纸质感',
    primaryColor: Color(0xFF5BA47C),
    primaryBgColor: Color(0xFFE9F3ED),
    orangeColor: Color(0xFFDB9558),
    orangeBgColor: Color(0xFFFAF1E7),
    pageBgColor: Color(0xFFF6F6F3),
    assetBgPath: null,
    bgOpacity: 0.0,
    cardOpacity: 1.0,
    useGlassmorphism: false,
  ),
];
