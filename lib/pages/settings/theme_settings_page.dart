/// 主题与个性化设置页面
/// 支持预设二次元主题、手机相册选图换背景、透明度与毛玻璃微调
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/theme_config.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import 'image_crop_page.dart';

class ThemeSettingsPage extends StatelessWidget {
  final ui.Image? overrideBgImage;
  final Map<String, ui.Image>? overrideThumbnails;

  const ThemeSettingsPage({
    super.key,
    this.overrideBgImage,
    this.overrideThumbnails,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final config = themeProvider.currentConfig;

    return ThemedBackgroundContainer(
      overrideBgImage: overrideBgImage,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('主题与个性化', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                themeProvider.resetToDefault();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已恢复默认主题设置')),
                );
              },
              child: const Text('恢复默认', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 1. 实时效果预览区域
            const _SectionHeader(title: '实时效果预览', icon: '✨'),
            const SizedBox(height: 8),
            _LiveThemePreview(config: config, overrideBgImage: overrideBgImage),

            const SizedBox(height: 20),

            // 2. 预设二次元与经典主题
            const _SectionHeader(title: '精选预设主题', icon: '🎨'),
            const SizedBox(height: 8),
            _PresetThemeGrid(
              currentId: config.id,
              overrideThumbnails: overrideThumbnails,
              onSelect: (preset) {
                themeProvider.applyPreset(preset);
              },
            ),

            const SizedBox(height: 20),

            // 3. 模块自选与原图框选
            const _SectionHeader(title: '各模块相册自选（原图等比框选）', icon: '🖼️'),
            const SizedBox(height: 8),
            _ModuleCustomSlotsCard(config: config),

            const SizedBox(height: 20),

            // 4. 视觉精细调节（透明度与毛玻璃）
            const _SectionHeader(title: '视觉微调', icon: '🎛️'),
            const SizedBox(height: 8),
            _VisualAdjustmentsCard(
              config: config,
              onBgOpacityChanged: (val) {
                themeProvider.setBgOpacity(val);
              },
              onCardOpacityChanged: (val) {
                themeProvider.setCardOpacity(val);
              },
              onGlassmorphismToggled: (val) {
                themeProvider.setGlassmorphism(val);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
        ),
      ],
    );
  }
}

/// 实时预览卡片
class _LiveThemePreview extends StatelessWidget {
  final ThemeConfig config;
  final ui.Image? overrideBgImage;
  const _LiveThemePreview({required this.config, this.overrideBgImage});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 底图
            Positioned.fill(
              child: _buildBgImage(),
            ),
            // 微透毛玻璃卡片模拟
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: config.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                config.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: config.primaryColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '今日 85%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: config.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '早餐：全麦三明治 + 低脂黑咖啡',
                        style: TextStyle(fontSize: 12, color: AppColors.text),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('已摄入 380 kcal',
                              style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                          ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: config.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            child: const Text('已完成', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBgImage() {
    if (overrideBgImage != null) {
      return RawImage(image: overrideBgImage, fit: BoxFit.cover);
    }
    if (config.customBgPath != null && config.customBgPath!.isNotEmpty) {
      final f = File(config.customBgPath!);
      if (f.existsSync()) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }
    if (config.bgImagePath != null && config.bgImagePath!.isNotEmpty) {
      return Image.asset(config.bgImagePath!, fit: BoxFit.cover);
    }
    return Container(color: config.bgColor);
  }
}

/// 预设主题网格
class _PresetThemeGrid extends StatelessWidget {
  final String currentId;
  final ValueChanged<ThemeConfig> onSelect;
  final Map<String, ui.Image>? overrideThumbnails;

  const _PresetThemeGrid({
    required this.currentId,
    required this.onSelect,
    this.overrideThumbnails,
  });

  @override
  Widget build(BuildContext context) {
    final presets = ThemeConfig.presets;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final preset = presets[index];
        final isSelected = preset.id == currentId;

        return GestureDetector(
          onTap: () => onSelect(preset),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? preset.primaryColor : Colors.white.withValues(alpha: 0.8),
                width: isSelected ? 2.2 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? preset.primaryColor.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: isSelected ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  // 背景图/底色
                  Positioned.fill(
                    child: overrideThumbnails != null && overrideThumbnails![preset.id] != null
                        ? RawImage(image: overrideThumbnails![preset.id], fit: BoxFit.cover)
                        : (preset.bgImagePath != null
                            ? Image.asset(preset.bgImagePath!, fit: BoxFit.cover)
                            : Container(color: preset.bgColor)),
                  ),
                  // 半透渐变遮罩，保证文字清晰
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 内容
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: preset.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: preset.primaryColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '使用中',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          preset.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 模块独立自选与原图框选卡片
class _ModuleCustomSlotsCard extends StatelessWidget {
  final ThemeConfig config;

  const _ModuleCustomSlotsCard({required this.config});

  Future<void> _pickAndCrop({
    required BuildContext context,
    required String moduleTitle,
    required String moduleKey,
    required double targetAspectRatio,
    bool isCircle = false,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;

      if (!context.mounted) return;
      final croppedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => ImageCropPage(
            originalImageFile: File(path),
            targetAspectRatio: targetAspectRatio,
            moduleTitle: moduleTitle,
            moduleKey: moduleKey,
            isCircle: isCircle,
          ),
        ),
      );

      if (croppedPath != null && context.mounted) {
        final tp = context.read<ThemeProvider>();
        if (moduleKey == 'bg') {
          await tp.setCustomBackground(croppedPath);
        } else if (moduleKey == 'mascot') {
          await tp.setCustomMascot(croppedPath);
        } else if (moduleKey == 'card') {
          await tp.setCustomCardBg(croppedPath);
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已完成「$moduleTitle」原图等比框选并应用！')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择或框选失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.read<ThemeProvider>();
    final screenSize = MediaQuery.of(context).size;
    final screenRatio =
        screenSize.height > 0 ? (screenSize.width / screenSize.height) : (9 / 19.5);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('每个模块自选相册原图框选',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: config.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '锁定模块原生比例',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: config.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '各模块强制锁定自身在 App 内的原生比例取景框。双指缩放拖动原图，精准取景不拉伸变形。',
            style: TextStyle(fontSize: 11, color: AppColors.textSub, height: 1.4),
          ),
          const SizedBox(height: 14),

          // 1. 全屏壁纸框
          _SlotItemRow(
            icon: '📱',
            title: '全屏应用壁纸',
            ratioDesc: '比例：全屏纵向锁定 (${(1 / screenRatio).toStringAsFixed(1)}:1)',
            customPath: config.customBgPath,
            defaultLabel: '预设：${config.name}',
            primaryColor: config.primaryColor,
            onPick: () => _pickAndCrop(
              context: context,
              moduleTitle: '全屏壁纸',
              moduleKey: 'bg',
              targetAspectRatio: screenRatio,
            ),
            onClear: () {
              tp.clearCustomBackground();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已恢复预设全局壁纸')),
              );
            },
          ),
          const Divider(height: 20, thickness: 0.5),

          // 2. 打气看板娘头像框
          _SlotItemRow(
            icon: '🌸',
            title: '打气看板娘头像',
            ratioDesc: '比例：1:1 正方形 / 圆形微缩锁定',
            customPath: config.customMascotPath,
            defaultLabel: '预设：便当打气娘',
            primaryColor: config.primaryColor,
            isCircle: true,
            onPick: () => _pickAndCrop(
              context: context,
              moduleTitle: '打气看板娘',
              moduleKey: 'mascot',
              targetAspectRatio: 1.0,
              isCircle: true,
            ),
            onClear: () {
              tp.clearCustomMascot();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已恢复预设便当打气娘')),
              );
            },
          ),
          const Divider(height: 20, thickness: 0.5),

          // 3. 卡片专属底纹框
          _SlotItemRow(
            icon: '🍱',
            title: '核心卡片专属底纹',
            ratioDesc: '比例：横幅卡片锁定 (约 2.2:1)',
            customPath: config.customCardBgPath,
            defaultLabel: '默认：纯净毛玻璃微白面板',
            primaryColor: config.primaryColor,
            onPick: () => _pickAndCrop(
              context: context,
              moduleTitle: '卡片专属底纹',
              moduleKey: 'card',
              targetAspectRatio: 358.0 / 160.0,
            ),
            onClear: () {
              tp.clearCustomCardBg();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已恢复纯净毛玻璃面板')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 模块槽位行组件
class _SlotItemRow extends StatelessWidget {
  final String icon;
  final String title;
  final String ratioDesc;
  final String? customPath;
  final String defaultLabel;
  final Color primaryColor;
  final bool isCircle;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _SlotItemRow({
    required this.icon,
    required this.title,
    required this.ratioDesc,
    required this.customPath,
    required this.defaultLabel,
    required this.primaryColor,
    this.isCircle = false,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasCustom = customPath != null &&
        customPath!.isNotEmpty &&
        File(customPath!).existsSync();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 缩略图框
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(8),
            color: primaryColor.withValues(alpha: 0.08),
            border: Border.all(
              color: hasCustom ? primaryColor : Colors.grey.withValues(alpha: 0.25),
              width: hasCustom ? 1.8 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasCustom
              ? Image.file(File(customPath!), fit: BoxFit.cover)
              : Center(
                  child: Text(icon, style: const TextStyle(fontSize: 20)),
                ),
        ),
        const SizedBox(width: 10),
        // 模块说明
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 6),
                  if (hasCustom)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已框选',
                        style: TextStyle(fontSize: 9, color: primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                ratioDesc,
                style: const TextStyle(fontSize: 10, color: AppColors.textSub),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // 操作按钮
        ElevatedButton(
          onPressed: onPick,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: Text(hasCustom ? '重新框选' : '相册框选',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        if (hasCustom) ...[
          const SizedBox(width: 6),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSub),
            tooltip: '恢复默认',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ],
    );
  }
}

/// 视觉精细调节卡片（透明度、毛玻璃）
class _VisualAdjustmentsCard extends StatelessWidget {
  final ThemeConfig config;
  final ValueChanged<double> onBgOpacityChanged;
  final ValueChanged<double> onCardOpacityChanged;
  final ValueChanged<bool> onGlassmorphismToggled;

  const _VisualAdjustmentsCard({
    required this.config,
    required this.onBgOpacityChanged,
    required this.onCardOpacityChanged,
    required this.onGlassmorphismToggled,
  });

  @override
  Widget build(BuildContext context) {
    final bgPct = (config.bgOpacity * 100).round();
    final cardPct = (config.cardOpacity * 100).round();

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 背景透明度调节
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('背景图可见度',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('$bgPct%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: config.primaryColor)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: config.primaryColor,
              thumbColor: config.primaryColor,
              overlayColor: config.primaryColor.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: config.bgOpacity,
              min: 0.05,
              max: 0.45,
              divisions: 40,
              onChanged: onBgOpacityChanged,
            ),
          ),
          const Text(
            '推荐 15%~25%：在保证二次元氛围感的同时，避免背景过度喧宾夺主影响文字阅读',
            style: TextStyle(fontSize: 10, color: AppColors.textFaint),
          ),

          const Divider(height: 24, thickness: 0.5),

          // 卡片毛玻璃透明度调节
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('卡片面板不透明度',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('$cardPct%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: config.primaryColor)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: config.primaryColor,
              thumbColor: config.primaryColor,
              overlayColor: config.primaryColor.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: config.cardOpacity,
              min: 0.60,
              max: 1.0,
              divisions: 40,
              onChanged: onCardOpacityChanged,
            ),
          ),
          const Text(
            '数值越小越通透有质感；数值越高文字越清晰易辨识（默认 92%）',
            style: TextStyle(fontSize: 10, color: AppColors.textFaint),
          ),

          const Divider(height: 24, thickness: 0.5),

          // 毛玻璃微光边框开关
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('毛玻璃微光边缘',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('为半透明卡片增加高光微白边缘与柔和弥散阴影',
                      style: TextStyle(fontSize: 10, color: AppColors.textSub)),
                ],
              ),
              Switch(
                value: config.useGlassmorphism,
                activeTrackColor: config.primaryColor.withValues(alpha: 0.5),
                activeThumbColor: config.primaryColor,
                onChanged: onGlassmorphismToggled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
