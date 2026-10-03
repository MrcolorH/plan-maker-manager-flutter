/// 主题视觉与设置页渲染截图测试（导出真实中文字体与二次元壁纸用于验收）
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jianfei_dazi/models/plan_data.dart';
import 'package:jianfei_dazi/models/settings.dart';
import 'package:jianfei_dazi/models/theme_config.dart';
import 'package:jianfei_dazi/pages/main_shell.dart';
import 'package:jianfei_dazi/pages/settings/image_crop_page.dart';
import 'package:jianfei_dazi/pages/settings/theme_settings_page.dart';
import 'package:jianfei_dazi/providers/app_provider.dart';
import 'package:jianfei_dazi/providers/onboarding_provider.dart';
import 'package:jianfei_dazi/providers/plan_provider.dart';
import 'package:jianfei_dazi/providers/preset_provider.dart';
import 'package:jianfei_dazi/providers/record_provider.dart';
import 'package:jianfei_dazi/providers/settings_provider.dart';
import 'package:jianfei_dazi/providers/theme_provider.dart';
import 'package:jianfei_dazi/providers/usage_provider.dart';
import 'package:jianfei_dazi/services/reminder_service.dart';
import 'package:jianfei_dazi/services/storage_service.dart';
import 'package:jianfei_dazi/theme/app_theme.dart';
import 'package:provider/provider.dart';

class _FakeReminderService extends ReminderService {
  _FakeReminderService() : super.forTesting();
  @override
  Future<void> fullReschedule(PlanData plan, AppSettings settings) async {}
  @override
  Future<void> ensureScheduled(PlanData plan, AppSettings settings) async {}
}

Future<ui.Image> _decodeLocalImage(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('渲染并导出二次元主题与设置页视觉验收截图', (tester) async {
    const outputDir = '/Users/colorh/.gemini/antigravity/brain/fd5fadb2-7cd2-403a-b203-38dfe3f0612f';
    const projectRoot = '/Users/colorh/Project/AICODING/plan-maker-manager-flutter';

    late ui.Image sakuraImg;
    late ui.Image starryImg;
    late ui.Image forestImg;
    late ui.Image mascotImg;

    await tester.runAsync(() async {
      // 1. 将系统真实中文字体注册为测试环境默认的 Ahem 字体，从而彻底替换掉所有方块豆腐块
      const fontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
      if (File(fontPath).existsSync()) {
        final fontData = await File(fontPath).readAsBytes();
        final fontLoader = FontLoader('Ahem');
        fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
        await fontLoader.load();
      }

      // 2. 解码真实的二次元插画和看板娘立绘
      sakuraImg = await _decodeLocalImage('$projectRoot/assets/themes/sakura_dream.jpg');
      starryImg = await _decodeLocalImage('$projectRoot/assets/themes/starry_night.jpg');
      forestImg = await _decodeLocalImage('$projectRoot/assets/themes/forest_breeze.jpg');
      mascotImg = await _decodeLocalImage('$projectRoot/assets/themes/mascot_chibi.jpg');
    });

    final thumbnailMap = <String, ui.Image>{
      'sakura': sakuraImg,
      'starry': starryImg,
      'forest': forestImg,
      'miku': forestImg,
      'sunset': sakuraImg,
    };

    SharedPreferences.setMockInitialValues({});
    final storage = StorageService.instance;
    await storage.init();

    // 适配现代手机常见分辨率 (412 x 892 逻辑尺寸，2.0 像素比)
    tester.view.physicalSize = const Size(412 * 2, 892 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sakuraPreset = kPresetThemes.firstWhere((t) => t.id == 'sakura');
    final starryPreset = kPresetThemes.firstWhere((t) => t.id == 'starry');
    final forestPreset = kPresetThemes.firstWhere((t) => t.id == 'forest');

    Future<void> captureWidget({
      required Widget widget,
      required String filename,
    }) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: widget,
        ),
      );
      // 多 pump 确保布局完成
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      expect(boundary, isNotNull);

      await tester.runAsync(() async {
        final image = await boundary!.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(byteData, isNotNull);
        final pngBytes = byteData!.buffer.asUint8List();

        final file = File('$outputDir/$filename');
        await file.writeAsBytes(pngBytes);
        debugPrint('已成功保存高清截图: ${file.path} (${pngBytes.length} bytes)');
      });
    }

    Widget buildAppWithTheme(
      ThemeConfig config, {
      bool showThemeSettings = false,
      ui.Image? overrideBg,
      String activeTab = 'today',
    }) {
      final appP = AppProvider();
      appP.setActiveTab(activeTab);
      final reminder = _FakeReminderService();
      final recP = RecordProvider(storage);
      late final PlanProvider planP;
      final setP = SettingsProvider(
        storage,
        reminder,
        getPlan: () => planP.plan,
      );
      planP = PlanProvider(storage, reminder, setP, recP);
      final onbP = OnboardingProvider(storage, planP, setP, recP);
      onbP.state.done = true;
      final useP = UsageProvider(storage);
      final preP = PresetProvider();
      final themeP = ThemeProvider(storage);
      themeP.applyPreset(config);

      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appP),
          ChangeNotifierProvider.value(value: planP),
          ChangeNotifierProvider.value(value: recP),
          ChangeNotifierProvider.value(value: setP),
          ChangeNotifierProvider.value(value: onbP),
          ChangeNotifierProvider.value(value: useP),
          ChangeNotifierProvider.value(value: preP),
          ChangeNotifierProvider.value(value: themeP),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, currentTp, _) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.createTheme(currentTp.currentConfig),
              home: showThemeSettings
                  ? ThemeSettingsPage(
                      overrideBgImage: overrideBg,
                      overrideThumbnails: thumbnailMap,
                    )
                  : MainShell(overrideBgImage: overrideBg),
            );
          },
        ),
      );
    }

    // 截图 1: 主题与背景设置页面（展示实时预览、预设列表、相册选图与滑块调节）
    await captureWidget(
      filename: 'screenshot_theme_settings.png',
      widget: buildAppWithTheme(
        sakuraPreset,
        showThemeSettings: true,
        overrideBg: sakuraImg,
      ),
    );

    // 截图 2: 今日打卡页 - 粉樱梦境主题 + 底部栏毛玻璃无缝穿透
    await captureWidget(
      filename: 'screenshot_today_sakura.png',
      widget: buildAppWithTheme(
        sakuraPreset,
        showThemeSettings: false,
        overrideBg: sakuraImg,
      ),
    );

    // 截图 3: 今日打卡页 - 星海幻夜主题 + 底部栏毛玻璃无缝穿透
    await captureWidget(
      filename: 'screenshot_today_starry.png',
      widget: buildAppWithTheme(
        starryPreset,
        showThemeSettings: false,
        overrideBg: starryImg,
      ),
    );

    // 截图 4: 今日打卡页 - 森林微风吉卜力草本主题 + 底部栏毛玻璃无缝穿透
    await captureWidget(
      filename: 'screenshot_today_forest.png',
      widget: buildAppWithTheme(
        forestPreset,
        showThemeSettings: false,
        overrideBg: forestImg,
      ),
    );

    // 截图 5: 设置页 - 展示高清晰度带主题色指示标的各设置区块标题
    await captureWidget(
      filename: 'screenshot_settings_page.png',
      widget: buildAppWithTheme(
        sakuraPreset,
        showThemeSettings: false,
        overrideBg: sakuraImg,
        activeTab: 'settings',
      ),
    );

    // 截图 6: 原图等比框选器 - 全屏壁纸框选（强制锁定全屏纵向比例 + 放大缩小重置工具）
    await captureWidget(
      filename: 'screenshot_crop_wallpaper.png',
      widget: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ImageCropPage(
          originalImageFile: File('$projectRoot/assets/themes/sakura_dream.jpg'),
          targetAspectRatio: 412 / 892,
          moduleTitle: '全屏壁纸',
          moduleKey: 'bg',
          overrideImage: sakuraImg,
        ),
      ),
    );

    // 截图 6: 原图等比框选器 - 打气看板娘头像框选（强制锁定 1:1 圆形/正方形）
    await captureWidget(
      filename: 'screenshot_crop_mascot.png',
      widget: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ImageCropPage(
          originalImageFile: File('$projectRoot/assets/themes/mascot_chibi.jpg'),
          targetAspectRatio: 1.0,
          moduleTitle: '打气看板娘头像',
          moduleKey: 'mascot',
          isCircle: true,
          overrideImage: mascotImg,
        ),
      ),
    );
  });

  testWidgets('ImageCropPage 支持单指平移拖拽与缩放调节', (tester) async {
    const projectRoot = '/Users/colorh/Project/AICODING/plan-maker-manager-flutter';
    final imageFile = File('$projectRoot/assets/themes/sakura_dream.jpg');
    late ui.Image testImg;

    await tester.runAsync(() async {
      testImg = await _decodeLocalImage(imageFile.path);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ImageCropPage(
          originalImageFile: imageFile,
          targetAspectRatio: 1.0,
          moduleTitle: '打气看板娘头像',
          moduleKey: 'mascot',
          isCircle: true,
          overrideImage: testImg,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 验证放大缩小按钮
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    expect(find.byIcon(Icons.zoom_out), findsOneWidget);
    expect(find.textContaining('重置'), findsOneWidget);

    // 1. 点击放大按钮，缩放倍数变为 1.3x
    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.3x'), findsOneWidget);

    // 2. 单指拖拽测试：在屏幕中央拖动 60 像素
    final center = tester.getCenter(find.byType(ImageCropPage));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 3. 点击重置按钮，恢复 1.0x
    await tester.tap(find.textContaining('重置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.0x'), findsOneWidget);
  });
}
