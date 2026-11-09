/// 袋装食品营养成分表与配料表拍照/图文识别与一键克数换算页面
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/nutrition_scan.dart';
import '../../models/records.dart';
import '../../providers/preset_provider.dart';
import '../../providers/record_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../widgets/ai_config_sheet.dart';

class FoodNutritionScanPage extends StatefulWidget {
  /// 默认推荐餐次（早餐/午餐/晚餐/加餐），若不传则按当前时间智能预选
  final String? initialSlot;

  const FoodNutritionScanPage({super.key, this.initialSlot});

  @override
  State<FoodNutritionScanPage> createState() => _FoodNutritionScanPageState();
}

class _FoodNutritionScanPageState extends State<FoodNutritionScanPage> {
  final ImagePicker _picker = ImagePicker();

  // 图片数据
  Uint8List? _imageBytes;
  String? _imageFileName;

  // 识别状态
  bool _isAnalyzing = false;
  String? _errorMessage;

  // 识别出的食品基准结果
  FoodPackageScanResult? _scanResult;

  // 可编辑控制器（食品名称、基准量）
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _servingSizeCtrl = TextEditingController(text: '100');
  final TextEditingController _baseCalCtrl = TextEditingController();
  final TextEditingController _baseProtCtrl = TextEditingController();
  final TextEditingController _baseFatCtrl = TextEditingController();
  final TextEditingController _baseCarbsCtrl = TextEditingController();
  final TextEditingController _baseSodiumCtrl = TextEditingController();
  final TextEditingController _ingredientsCtrl = TextEditingController();

  // 核心：用户手输实际摄入克数
  final TextEditingController _intakeGramsCtrl = TextEditingController(text: '100');

  // 计算结果
  CalculatedNutrition? _calculated;

  // 目标记录餐次
  late String _selectedSlot;

  // 是否展开基准值微调
  bool _showBaseEditor = false;

  @override
  void initState() {
    super.initState();
    _selectedSlot = widget.initialSlot ?? _guessCurrentSlot();
    _intakeGramsCtrl.addListener(_onIntakeChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _servingSizeCtrl.dispose();
    _baseCalCtrl.dispose();
    _baseProtCtrl.dispose();
    _baseFatCtrl.dispose();
    _baseCarbsCtrl.dispose();
    _baseSodiumCtrl.dispose();
    _ingredientsCtrl.dispose();
    _intakeGramsCtrl.removeListener(_onIntakeChanged);
    _intakeGramsCtrl.dispose();
    super.dispose();
  }

  String _guessCurrentSlot() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 10) return 'breakfast';
    if (hour >= 11 && hour < 14) return 'lunch';
    if (hour >= 17 && hour < 20) return 'dinner';
    return 'snack';
  }

  void _onIntakeChanged() {
    _recalculate();
  }

  void _applyScanResult(FoodPackageScanResult res) {
    setState(() {
      _scanResult = res;
      _nameCtrl.text = res.foodName;
      _servingSizeCtrl.text = res.servingSize.toStringAsFixed(res.servingSize.truncateToDouble() == res.servingSize ? 0 : 1);
      _baseCalCtrl.text = res.calories.toStringAsFixed(0);
      _baseProtCtrl.text = res.protein.toStringAsFixed(1);
      _baseFatCtrl.text = res.fat.toStringAsFixed(1);
      _baseCarbsCtrl.text = res.carbs.toStringAsFixed(1);
      _baseSodiumCtrl.text = res.sodium.toStringAsFixed(0);
      _ingredientsCtrl.text = res.ingredients;
      _errorMessage = null;

      // 默认将摄入克数置为基准克数，方便直接查看基准或输入实重
      if (_intakeGramsCtrl.text.trim().isEmpty || _intakeGramsCtrl.text == '100') {
        _intakeGramsCtrl.text = res.servingSize.toStringAsFixed(res.servingSize.truncateToDouble() == res.servingSize ? 0 : 1);
      }
    });
    _recalculate();
  }

  void _recalculate() {
    if (_scanResult == null) {
      setState(() => _calculated = null);
      return;
    }

    final intake = double.tryParse(_intakeGramsCtrl.text.trim()) ?? 0.0;
    if (intake <= 0) {
      setState(() => _calculated = null);
      return;
    }

    // 从当前可能编辑过的基准值重新组装
    final currentBase = _scanResult!.copyWith(
      foodName: _nameCtrl.text.trim().isEmpty ? _scanResult!.foodName : _nameCtrl.text.trim(),
      servingSize: double.tryParse(_servingSizeCtrl.text) ?? _scanResult!.servingSize,
      calories: double.tryParse(_baseCalCtrl.text) ?? _scanResult!.calories,
      protein: double.tryParse(_baseProtCtrl.text) ?? _scanResult!.protein,
      fat: double.tryParse(_baseFatCtrl.text) ?? _scanResult!.fat,
      carbs: double.tryParse(_baseCarbsCtrl.text) ?? _scanResult!.carbs,
      sodium: double.tryParse(_baseSodiumCtrl.text) ?? _scanResult!.sodium,
      ingredients: _ingredientsCtrl.text.trim(),
    );

    setState(() {
      _scanResult = currentBase;
      _calculated = currentBase.calculate(intake);
    });
  }

  // ---------- 拍照 / 选取图片 (支持 Telegram 风格相机主打与相册并选) ----------
  Future<void> _pickFromCamera() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imageFileName = file.name;
        });
        await _analyzeImage(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('调用相机失败：$e，你可尝试从相册选取或直接输入文本')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _imageFileName = file.name;
        });
        await _analyzeImage(bytes);
      }
    } catch (e) {
      // 桌面端或无相册权限时自动降级使用 FilePicker
      try {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (res != null && res.files.isNotEmpty) {
          final file = res.files.first;
          if (file.bytes != null) {
            setState(() {
              _imageBytes = file.bytes;
              _imageFileName = file.name;
            });
            await _analyzeImage(file.bytes!);
          }
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('选择图片失败：$err')),
          );
        }
      }
    }
  }

  /// 呼出 Telegram 风格媒体选取底栏（拍照主推 + 相册选图 + 文本提取）
  void _showTelegramStyleMediaPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.document_scanner, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 8),
                const Text('选取包装成分表照片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSub),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '拍照为主 · 对准包装背面的「营养成分表」和「配料表」即可精确折算',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 14),

            // Telegram 风格媒体选取并排卡片
            Row(
              children: [
                // 1. 拍照主卡片 (Telegram 暗调相机取景框风格，大圆形快门按钮)
                Expanded(
                  flex: 5,
                  child: Material(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickFromCamera();
                      },
                      child: Container(
                        height: 132,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(color: Colors.white70, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 22),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '即时拍照 (主推)',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              '直接对准包装拍照',
                              style: TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 2. 相册选图与手输文本卡片并列
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      // 相册选图
                      Material(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(ctx);
                            _pickFromGallery();
                          },
                          child: Container(
                            height: 61,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Row(
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Colors.white,
                                  child: Icon(Icons.photo_library, color: AppColors.primary, size: 19),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('相册选图', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      Text('选取手机相册图片', style: TextStyle(fontSize: 10, color: AppColors.textSub)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // 手输文本 / OCR 粘贴 (极省 Token)
                      Material(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showTextInputDialog();
                          },
                          child: Container(
                            height: 61,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Row(
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Colors.white,
                                  child: Icon(Icons.edit_note, color: Color(0xFF059669), size: 21),
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('输入文本', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      Text('省 Token · 支持粘贴', style: TextStyle(fontSize: 10, color: Color(0xFF059669))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Token 节能说明
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt, color: Color(0xFF16A34A), size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已自动应用 1280px 边缘优化与压缩，降低 70% 视觉 Token；如直接粘贴文字则几乎 0 视觉 Token。',
                      style: TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    _showTelegramStyleMediaPicker();
  }

  // ---------- 运行 AI 识别 ----------
  Future<void> _analyzeImage(Uint8List bytes) async {
    final ok = await ensureAiConfigured(
      context,
      message: '拍照识别营养成分表与配料表需要 AI 模型支持，请先配置 API Key。',
    );
    if (!ok || !mounted) return;

    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final res = await AiService.instance.analyzeFoodNutritionPackage(
        settings.ai,
        imageBytes: bytes,
        onUsage: usage.addUsage,
      );
      if (!mounted) return;
      _applyScanResult(res);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别成功：${res.foodName}（每${res.servingSize.toStringAsFixed(0)}${res.servingUnit}含${res.calories.round()}kcal）')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 识别未完成：$_errorMessage，你可点击手动输入成分表')),
      );
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ---------- 手动输入 / 粘贴成分表文本 ----------
  void _showTextInputDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴/输入成分表文本', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持从照片 OCR 复制的文本，或直接手输（如：能量 1850kJ，蛋白质 7.5g，脂肪 16g，碳水 62g，钠 450mg，配料：小麦粉...）：',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 6,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴营养成分表与配料表文字...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              await _analyzeText(text);
            },
            child: const Text('智能识别'),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeText(String text) async {
    final settings = context.read<SettingsProvider>().settings;
    final usage = context.read<UsageProvider>();

    // 优先尝试 AI 深度提取
    if (settings.ai.apiKey.isNotEmpty) {
      setState(() {
        _isAnalyzing = true;
        _errorMessage = null;
      });
      try {
        final res = await AiService.instance.analyzeFoodNutritionPackage(
          settings.ai,
          rawText: text,
          onUsage: usage.addUsage,
        );
        if (!mounted) return;
        _applyScanResult(res);
        return;
      } catch (_) {
        // AI 异常时自动降级到本地正则提取
      } finally {
        if (mounted) setState(() => _isAnalyzing = false);
      }
    }

    // 本地离线秒级提取
    final fallback = FoodPackageScanResult.extractFromText(text);
    _applyScanResult(fallback);
  }

  // ---------- 常见预设示例（方便快速体验） ----------
  void _applyDemoPreset(String name) {
    FoodPackageScanResult sample;
    switch (name) {
      case '欧包':
        sample = const FoodPackageScanResult(
          foodName: '全麦黑麦无糖吐司',
          servingSize: 100,
          servingUnit: 'g',
          calories: 215,
          energyKj: 900,
          protein: 9.2,
          fat: 2.3,
          carbs: 38.5,
          sodium: 260,
          fiber: 6.8,
          ingredients: '全麦粉、黑麦粉、生活饮用水、食用盐、鲜酵母',
          healthTips: ['🟢 高膳食纤维', '🟢 低脂控糖', '🟢 配料表干净无蔗糖'],
        );
        break;
      case '牛奶':
        sample = const FoodPackageScanResult(
          foodName: '高钙脱脂纯牛奶',
          servingSize: 100,
          servingUnit: 'ml',
          calories: 36,
          energyKj: 151,
          protein: 3.4,
          fat: 0.0,
          carbs: 5.0,
          sodium: 60,
          ingredients: '生牛乳',
          healthTips: ['🟢 0脂肪无负担', '🟢 优质乳蛋白', '🟢 纯生牛乳无添加'],
        );
        break;
      case '薯片':
        sample = const FoodPackageScanResult(
          foodName: '原味非油炸薯片',
          servingSize: 40,
          servingUnit: 'g',
          calories: 185,
          energyKj: 775,
          protein: 2.8,
          fat: 8.5,
          carbs: 24.2,
          sodium: 190,
          ingredients: '脱水马铃薯、精炼植物油、食用淀粉、食用盐、白砂糖',
          healthTips: ['🔴 脂肪占比偏高', '🟡 含有少量白砂糖', '💡 建议每次控制在半包(20g)以内'],
        );
        break;
      case '能量棒':
      default:
        sample = const FoodPackageScanResult(
          foodName: '坚果蛋白能量棒',
          servingSize: 35,
          servingUnit: 'g',
          calories: 145,
          energyKj: 608,
          protein: 10.5,
          fat: 5.2,
          carbs: 12.0,
          sodium: 95,
          fiber: 4.5,
          sugar: 1.5,
          ingredients: '浓缩大豆分离蛋白、杏仁碎、燕麦片、低聚异麦芽糖、奇亚籽',
          healthTips: ['🟢 高蛋白饱腹', '🟢 低GI慢碳', '🟢 优质不饱和脂肪酸'],
        );
        break;
    }
    _applyScanResult(sample);
  }

  // ---------- 快捷摄入克数微调 ----------
  void _adjustIntake(double delta) {
    final cur = double.tryParse(_intakeGramsCtrl.text.trim()) ?? 0.0;
    final next = (cur + delta).clamp(1.0, 2000.0);
    _intakeGramsCtrl.text = next.toStringAsFixed(next.truncateToDouble() == next ? 0 : 1);
  }

  void _setIntake(double val) {
    _intakeGramsCtrl.text = val.toStringAsFixed(val.truncateToDouble() == val ? 0 : 1);
  }

  // ---------- 一键记入今日饮食 ----------
  Future<void> _recordToToday() async {
    if (_calculated == null || _scanResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先输入摄入克数并计算')));
      return;
    }

    final calc = _calculated!;
    final foodName = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : _scanResult!.foodName;
    final intakeDesc = '${calc.intakeAmount.toStringAsFixed(calc.intakeAmount.truncateToDouble() == calc.intakeAmount ? 0 : 1)}${calc.unit}';
    final displayName = '$foodName ($intakeDesc)';
    final detailStr = '摄入$intakeDesc，按标称每${_scanResult!.servingSize.toStringAsFixed(0)}${_scanResult!.servingUnit}(${_scanResult!.calories.round()}kcal)精确折算';

    // 拆解项
    final breakdownItem = FoodBreakdownItem(
      name: foodName,
      portion: intakeDesc,
      calories: calc.calories,
    );

    await context.read<RecordProvider>().addDayEntry(
          todayStr(),
          kind: 'meal',
          slot: _selectedSlot,
          content: displayName,
          calories: calc.calories,
          protein: calc.protein.round(),
          carbs: calc.carbs.round(),
          fat: calc.fat.round(),
          source: '袋装食品成分换算',
          detail: detailStr,
          items: [breakdownItem],
        );

    if (!mounted) return;
    final slotName = _getSlotName(_selectedSlot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已记入今日$slotName：$displayName（${calc.calories} kcal）')),
    );
    Navigator.of(context).pop();
  }

  // ---------- 存入常用食物库 ----------
  Future<void> _saveAsPreset() async {
    if (_scanResult == null) return;
    final foodName = _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : _scanResult!.foodName;
    final unitDesc = '${_scanResult!.servingSize.toStringAsFixed(0)}${_scanResult!.servingUnit}';

    await context.read<PresetProvider>().savePreset(
          name: foodName,
          calories: _scanResult!.calories.round(),
          protein: _scanResult!.protein.round(),
          carbs: _scanResult!.carbs.round(),
          fat: _scanResult!.fat.round(),
          unit: unitDesc,
          amount: 1.0,
          note: _ingredientsCtrl.text.trim().isNotEmpty ? '配料：${_ingredientsCtrl.text.trim()}' : '袋装食品营养标签',
          syncToFoodDb: true,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已存入常用食物库：$foodName（每$unitDesc ${_scanResult!.calories.round()}kcal）')),
    );
  }

  String _getSlotName(String slot) {
    switch (slot) {
      case 'breakfast':
        return '早餐';
      case 'lunch':
        return '午餐';
      case 'dinner':
        return '晚餐';
      case 'snack':
      default:
        return '加餐';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('包装配料与营养成分换算'),
        actions: [
          IconButton(
            tooltip: '常见示例',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('快速体验袋装食品成分换算', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                        ListTile(
                          leading: const Text('🍞', style: TextStyle(fontSize: 22)),
                          title: const Text('全麦黑麦吐司（每100g 215kcal）'),
                          subtitle: const Text('低脂控糖 · 高膳食纤维'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _applyDemoPreset('欧包');
                          },
                        ),
                        ListTile(
                          leading: const Text('🥛', style: TextStyle(fontSize: 22)),
                          title: const Text('高钙脱脂纯牛奶（每100ml 36kcal）'),
                          subtitle: const Text('0脂肪 · 优质蛋白质'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _applyDemoPreset('牛奶');
                          },
                        ),
                        ListTile(
                          leading: const Text('🍫', style: TextStyle(fontSize: 22)),
                          title: const Text('坚果蛋白能量棒（每根35g 145kcal）'),
                          subtitle: const Text('高蛋白 · 优质坚果油脂'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _applyDemoPreset('能量棒');
                          },
                        ),
                        ListTile(
                          leading: const Text('🥔', style: TextStyle(fontSize: 22)),
                          title: const Text('非油炸原味薯片（每份40g 185kcal）'),
                          subtitle: const Text('袋装零食分食换算典型示例'),
                          onTap: () {
                            Navigator.pop(ctx);
                            _applyDemoPreset('薯片');
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          // 1. 顶部操作栏：拍照、选图、文本输入
          _buildActionBanner(),
          const SizedBox(height: 14),

          // 2. 识别中加载态 / 错误提示
          if (_isAnalyzing) _buildAnalyzingCard(),
          if (_errorMessage != null) _buildErrorCard(),

          // 3. 识别结果展示（输入食用克数与记录餐次置于上方，食物介绍与各项说明置于最下方）
          if (_scanResult != null) ...[
            // 核心：手输摄入克数与一键精准换算
            _buildIntakeAndCalculationCard(),
            const SizedBox(height: 12),

            // 记录到今日餐次与一键入账
            _buildBottomActionCard(),
            const SizedBox(height: 14),

            // 最下方：食物介绍与各项包装标称/配料说明卡片
            _buildBaseNutritionCard(),
          ],
        ],
      ),
    );
  }

  /// 顶部获取包装入口栏（以拍照为主，同时支持相册与 Telegram 风格媒体并选）
  Widget _buildActionBanner() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.document_scanner, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('袋装食品拍照/图文识别', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('拍照为主 · 对准成分表，输入食用克数一键换算', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 拍照为主，Telegram 风格快速并选
          Row(
            children: [
              // 1. 拍照主推大按钮
              Expanded(
                flex: 5,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('拍照识别 (主推)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: _isAnalyzing ? null : _pickFromCamera,
                ),
              ),
              const SizedBox(width: 8),
              // 2. 相册选图
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: Color(0xFFDCDCD5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  icon: const Icon(Icons.photo_library, size: 16, color: AppColors.primary),
                  label: const Text('相册', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onPressed: _isAnalyzing ? null : _pickFromGallery,
                ),
              ),
              const SizedBox(width: 8),
              // 3. Telegram 风格多选底栏 / 文本弹窗
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDCDCD5)),
                ),
                child: IconButton(
                  tooltip: 'Telegram 媒体全览面板',
                  icon: const Icon(Icons.dashboard_customize_outlined, color: AppColors.textSub, size: 19),
                  onPressed: _isAnalyzing ? null : _showTelegramStyleMediaPicker,
                ),
              ),
            ],
          ),
          if (_imageBytes != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    _imageBytes!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _imageFileName ?? '包装照片已就绪',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 13),
                  label: const Text('重拍', style: TextStyle(fontSize: 12)),
                  onPressed: _isAnalyzing ? null : _pickFromCamera,
                ),
                TextButton(
                  onPressed: _isAnalyzing ? null : () => _analyzeImage(_imageBytes!),
                  child: const Text('重识', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// AI 识别中动画卡片
  Widget _buildAnalyzingCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 正在深度解析营养标签与配料表...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('核验千焦千卡换算、三大营养素及减脂避坑分析', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 错误提示
  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD4D4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFDC3545), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC3545)),
            ),
          ),
        ],
      ),
    );
  }

  /// 标称基准卡片（识别出的包装标称数据 + 配料洞察，置于结果最下方）
  Widget _buildBaseNutritionCard() {
    final res = _scanResult!;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标头：简明标题 + 醒目且易点击的微调按钮
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.textSub.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.description_outlined, size: 15, color: AppColors.textSub),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '包装标称与配料说明',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textSub),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _showBaseEditor = !_showBaseEditor),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tune, size: 13, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          _showBaseEditor ? '收起微调' : '微调基准',
                          style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          _showBaseEditor ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 食品名称可编辑行
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: '食品名称',
                  ),
                  onChanged: (_) => _recalculate(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 标称标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '包装标称基准：每 ${_servingSizeCtrl.text} ${res.servingUnit} 含 ${_baseCalCtrl.text} kcal${res.energyKj != null ? ' (${res.energyKj!.round()} kJ)' : ''}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSub, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),

          // 基准营养素网格展示
          Row(
            children: [
              _buildMiniMacro('能量', '${_baseCalCtrl.text}k', '千卡', const Color(0xFFD97706)),
              _buildMiniMacro('蛋白质', '${_baseProtCtrl.text}g', 'P', const Color(0xFF059669)),
              _buildMiniMacro('脂肪', '${_baseFatCtrl.text}g', 'F', const Color(0xFFDC2626)),
              _buildMiniMacro('碳水', '${_baseCarbsCtrl.text}g', 'C', const Color(0xFF2563EB)),
              _buildMiniMacro('钠', '${_baseSodiumCtrl.text}mg', 'Na', const Color(0xFF7C3AED)),
            ],
          ),

          // 若展开基准微调
          if (_showBaseEditor) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text('修改包装标称参数（若拍照反光个别数字有误可直接改）：', style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildParamInput('基准克数', _servingSizeCtrl, 'g')),
                const SizedBox(width: 8),
                Expanded(child: _buildParamInput('标称热量', _baseCalCtrl, 'kcal')),
                const SizedBox(width: 8),
                Expanded(child: _buildParamInput('蛋白质', _baseProtCtrl, 'g')),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _buildParamInput('脂肪', _baseFatCtrl, 'g')),
                const SizedBox(width: 8),
                Expanded(child: _buildParamInput('碳水', _baseCarbsCtrl, 'g')),
                const SizedBox(width: 8),
                Expanded(child: _buildParamInput('钠含量', _baseSodiumCtrl, 'mg')),
              ],
            ),
          ],

          // 配料表与健康标签
          if (res.healthTips.isNotEmpty || _ingredientsCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (res.healthTips.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: res.healthTips.map((tip) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(tip, style: const TextStyle(fontSize: 11, color: Color(0xFF374151))),
                  );
                }).toList(),
              ),
            if (_ingredientsCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '配料表：${_ingredientsCtrl.text}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildParamInput(String label, TextEditingController ctrl, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textSub)),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onChanged: (_) => _recalculate(),
                ),
              ),
              Text(unit, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMacro(String name, String value, String tag, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(name, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  /// 核心计算区：手输摄入克数与一键换算清单
  Widget _buildIntakeAndCalculationCard() {
    final calc = _calculated;
    final unit = _scanResult?.servingUnit ?? 'g';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题与提示
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.calculate, color: AppColors.primary, size: 20),
                  SizedBox(width: 6),
                  Text('输入食用克数 · 一键换算清单', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              if (calc != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '比例 ${(calc.ratio * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 顶部简明食品信息条（方便用户核对识别名称与基准）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_nameCtrl.text.isNotEmpty ? _nameCtrl.text : (_scanResult?.foodName ?? "食品")} · 标称每${_servingSizeCtrl.text}$unit ${_baseCalCtrl.text}kcal',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 摄入克数大号输入框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E2DC)),
            ),
            child: Row(
              children: [
                const Text('实际摄入量：', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Expanded(
                  child: TextField(
                    controller: _intakeGramsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: '0',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(unit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 快捷克数调节 Chip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickChip('+10$unit', () => _adjustIntake(10)),
                _buildQuickChip('+20$unit', () => _adjustIntake(20)),
                _buildQuickChip('+50$unit', () => _adjustIntake(50)),
                _buildQuickChip('30$unit', () => _setIntake(30)),
                _buildQuickChip('50$unit', () => _setIntake(50)),
                _buildQuickChip('100$unit', () => _setIntake(100)),
                if (_scanResult != null && _scanResult!.servingSize != 100)
                  _buildQuickChip('1整份(${_scanResult!.servingSize.toStringAsFixed(0)}$unit)', () => _setIntake(_scanResult!.servingSize)),
                _buildQuickChip('半份/半袋', () {
                  if (_scanResult != null) _setIntake(_scanResult!.servingSize / 2);
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // 一键换算得到的实际营养清单
          if (calc != null) ...[
            // 实际总热量超大展示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF7ED), Color(0xFFFEF3C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('实际摄入总热量', style: TextStyle(fontSize: 12, color: Color(0xFF9A3412), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${calc.calories} kcal',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('基准系数：${calc.ratio.toStringAsFixed(2)}x', style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                        const SizedBox(height: 2),
                        Text('按${calc.intakeAmount.toStringAsFixed(0)}$unit准确折算', style: const TextStyle(fontSize: 10, color: Color(0xFFC2410C), fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 宏量营养素清单表格
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildCalculatedRow('🥩 蛋白质 (Protein)', '${calc.protein} g', '供能比 ${(calc.proteinRatio * 100).toStringAsFixed(0)}%', const Color(0xFF059669)),
                  const SizedBox(height: 6),
                  _buildCalculatedRow('🥑 脂肪 (Fat)', '${calc.fat} g', '供能比 ${(calc.fatRatio * 100).toStringAsFixed(0)}%', const Color(0xFFDC2626)),
                  const SizedBox(height: 6),
                  _buildCalculatedRow('🍚 碳水化合物 (Carbs)', '${calc.carbs} g', '供能比 ${(calc.carbsRatio * 100).toStringAsFixed(0)}%', const Color(0xFF2563EB)),
                  const SizedBox(height: 6),
                  _buildCalculatedRow('🧂 钠含量 (Sodium)', '${calc.sodium} mg', calc.sodium > 400 ? '高钠注意' : '适中', const Color(0xFF7C3AED)),
                  if (calc.fiber != null) ...[
                    const SizedBox(height: 6),
                    _buildCalculatedRow('🥗 膳食纤维 (Fiber)', '${calc.fiber} g', '健康益生', const Color(0xFF10B981)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 三大宏量供能比进度条
            if (calc.proteinRatio + calc.fatRatio + calc.carbsRatio > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (calc.proteinRatio * 100).round().clamp(1, 100),
                        child: Container(color: const Color(0xFF059669)),
                      ),
                      Expanded(
                        flex: (calc.fatRatio * 100).round().clamp(1, 100),
                        child: Container(color: const Color(0xFFDC2626)),
                      ),
                      Expanded(
                        flex: (calc.carbsRatio * 100).round().clamp(1, 100),
                        child: Container(color: const Color(0xFF2563EB)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('蛋白质 ${(calc.proteinRatio * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Color(0xFF059669))),
                  Text('脂肪 ${(calc.fatRatio * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Color(0xFFDC2626))),
                  Text('碳水 ${(calc.carbsRatio * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB))),
                ],
              ),
            ],
          ] else ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('请输入有效摄入量（大于0克）进行精确换算', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE2E2DC)),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildCalculatedRow(String label, String value, String tag, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.text)),
        Row(
          children: [
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tag, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ],
    );
  }

  /// 底部入账与存库卡片
  Widget _buildBottomActionCard() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('记录到今日餐次：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  _buildSlotChoiceChip('早餐', 'breakfast'),
                  _buildSlotChoiceChip('午餐', 'lunch'),
                  _buildSlotChoiceChip('晚餐', 'dinner'),
                  _buildSlotChoiceChip('加餐', 'snack'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text('一键记入今日${_getSlotName(_selectedSlot)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  onPressed: _calculated == null ? null : _recordToToday,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: Color(0xFFDCDCD5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.star_border, size: 18),
                  label: const Text('存为常用', style: TextStyle(fontSize: 13)),
                  onPressed: _scanResult == null ? null : _saveAsPreset,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlotChoiceChip(String label, String slotKey) {
    final selected = _selectedSlot == slotKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      selected: selected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: selected ? AppColors.primary : AppColors.textSub),
      side: BorderSide(color: selected ? AppColors.primary : const Color(0xFFE2E2DC)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (val) {
        if (val) setState(() => _selectedSlot = slotKey);
      },
    );
  }
}
